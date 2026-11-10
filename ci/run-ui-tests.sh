#!/usr/bin/env bash
# Builds the app once, then runs the UI test suite on each simulator.
# Set UI_TEST_RETRIES=N to rerun a failed test up to N more times (every attempt is logged).
# Simulators come from ci/pick_simulators.py, or from the command in $SIMULATOR_LIST_CMD
# (for example ci/create-duo.sh). Each line is 'label|udid|name[|destination]'.
# Screenshots land in ci-output/screenshots, result bundles in ci-output/*.xcresult.
# Set FOLD_POSES (iPhone Duo only), for example "open:180 partial:120", to run the suite with
# the hinge closed and then the layout test again with the hinge at each of those angles.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/ci-output"
DERIVED="$ROOT/build/DerivedData"
mkdir -p "$OUT/screenshots"

if [ -n "${SIMULATOR_LIST_CMD:-}" ]; then
  if ! $SIMULATOR_LIST_CMD > "$OUT/simulators.txt"; then
    echo "::error::'$SIMULATOR_LIST_CMD' failed; not running UI tests on any other device."
    exit 1
  fi
else
  python3 "$ROOT/ci/pick_simulators.py" > "$OUT/simulators.txt" || exit 1
fi
cat "$OUT/simulators.txt"

set -e
xcodebuild build-for-testing \
  -project "$ROOT/CountertopCook.xcodeproj" \
  -scheme CountertopCook \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED" \
  | tee "$OUT/build.log" | grep -E "error:|warning: .*CountertopCook|BUILD (SUCCEEDED|FAILED)|\*\* " || true
set +e
if ! grep -q "TEST BUILD SUCCEEDED" "$OUT/build.log"; then
  echo "Build failed; errors:"
  grep -E "error:" "$OUT/build.log" | sort -u
  exit 1
fi

status=0

# The link-import test fetches these pages over HTTP. The simulator shares this Mac's network,
# so it reaches the server at 127.0.0.1 (an IP address, which App Transport Security allows).
FIXTURE_PORT=8765
python3 -m http.server "$FIXTURE_PORT" --bind 127.0.0.1 --directory "$ROOT/ci/fixtures" \
  > "$OUT/fixture-server.log" 2>&1 &
FIXTURE_PID=$!
trap 'kill $FIXTURE_PID 2>/dev/null' EXIT
for _ in $(seq 1 20); do
  curl -sf "http://127.0.0.1:$FIXTURE_PORT/recipe.html" > /dev/null && break
  sleep 0.5
done
curl -sf "http://127.0.0.1:$FIXTURE_PORT/recipe.html" > /dev/null \
  || echo "::error::Fixture server for the link-import test didn't start"

# run_tests <label> <name> <destination> <fold pose or ""> [xcodebuild args...]
run_tests() {
  local label=$1 name=$2 destination=$3 pose=$4
  shift 4
  TEST_RUNNER_SCREENSHOT_DIR="$OUT/screenshots" TEST_RUNNER_FOLD_POSE="$pose" \
    TEST_RUNNER_IMPORT_FIXTURE_URL="http://127.0.0.1:$FIXTURE_PORT" xcodebuild test-without-building \
    -project "$ROOT/CountertopCook.xcodeproj" \
    -scheme CountertopCook \
    -destination "$destination" \
    -derivedDataPath "$DERIVED" \
    -resultBundlePath "$OUT/$label.xcresult" \
    ${UI_TEST_RETRIES:+-retry-tests-on-failure -test-iterations $((UI_TEST_RETRIES + 1))} \
    "$@" \
    > "$OUT/test-$label.log" 2>&1
  local result=$?
  # The preview runner's test process sometimes crashes before any test starts. Test retries
  # don't cover that, so run the whole set once more (only when no test ran at all).
  if [ $result -ne 0 ] && [ "${RUNNER_RETRY:-0}" = 0 ] && grep -q "never finished bootstrapping" "$OUT/test-$label.log" \
     && ! grep -q "Test Case .* started" "$OUT/test-$label.log"; then
    echo "::warning::[$label] Test runner crashed before starting; running the tests again"
    mv "$OUT/test-$label.log" "$OUT/test-$label-crashed.log"
    rm -rf "$OUT/$label.xcresult"
    RUNNER_RETRY=1 run_tests "$label" "$name" "$destination" "$pose" "$@"
    return
  fi
  grep -E "Test Case .* (passed|failed)|error:|XCTAssert|NOTE:|FOLD:|CARDS:|\*\* TEST" "$OUT/test-$label.log" | tee "$OUT/summary-$label.txt"
  # Surface each failure as an annotation so it shows on the run page.
  grep -E "error:" "$OUT/test-$label.log" | sed -E 's#^.*/(UITests|App)/#\1/#' | sort -u | head -15 \
    | while IFS= read -r line; do echo "::error::[$label] $line"; done
  if [ $result -ne 0 ]; then
    echo "::error::UI tests failed on $name${pose:+ (hinge $pose)}"
    status=1
  else
    echo "UI tests passed on $name${pose:+ (hinge $pose)}"
  fi
}

while IFS='|' read -r label udid name destination; do
  [ -z "$udid" ] && continue
  destination=${destination:-id=$udid}
  echo "::group::UI tests on $name ($destination)"
  xcrun simctl boot "$udid" 2>/dev/null
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
  # Warm up: the first launch on a freshly booted simulator can exceed XCUITest's launch timeout.
  APP="$DERIVED/Build/Products/Debug-iphonesimulator/CountertopCook.app"
  xcrun simctl install "$udid" "$APP" \
    && xcrun simctl launch "$udid" com.hubertlee.countertopcook -uitesting >/dev/null \
    && sleep 20 \
    && xcrun simctl terminate "$udid" com.hubertlee.countertopcook
  # A freshly booted iPhone Duo starts folded shut, on the outer display.
  run_tests "$label" "$name" "$destination" "${FOLD_POSES:+closed}"
  echo "::endgroup::"

  for entry in ${FOLD_POSES:-}; do
    pose=${entry%%:*}
    degrees=${entry#*:}
    echo "::group::Layout test on $name with the hinge $pose ($degrees degrees)"
    if ! "$ROOT/ci/duo-hinge.sh" "$udid" "$degrees"; then
      echo "::error::Could not move the $name hinge to $degrees degrees ($pose); unfolded layout not tested."
      status=1
      echo "::endgroup::"
      continue
    fi
    run_tests "$label-$pose" "$name" "$destination" "$pose" \
      -only-testing:CountertopCookUITests/CountertopCookUITests/testLayoutKeepsTimersVisibleAndCentreLineClear
    echo "::endgroup::"
  done
  xcrun simctl shutdown "$udid" 2>/dev/null
done < "$OUT/simulators.txt"

exit $status
