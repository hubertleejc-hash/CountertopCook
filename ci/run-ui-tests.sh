#!/usr/bin/env bash
# Builds the app once, then runs the UI test suite on each simulator.
# Simulators come from ci/pick_simulators.py, or from the command in $SIMULATOR_LIST_CMD
# (for example ci/create-duo.sh). Each line is 'label|udid|name[|destination]'.
# Screenshots land in ci-output/screenshots, result bundles in ci-output/*.xcresult.
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
  TEST_RUNNER_SCREENSHOT_DIR="$OUT/screenshots" xcodebuild test-without-building \
    -project "$ROOT/CountertopCook.xcodeproj" \
    -scheme CountertopCook \
    -destination "$destination" \
    -derivedDataPath "$DERIVED" \
    -resultBundlePath "$OUT/$label.xcresult" \
    > "$OUT/test-$label.log" 2>&1
  result=$?
  grep -E "Test Case .* (passed|failed)|error:|XCTAssert|\*\* TEST" "$OUT/test-$label.log" | tee "$OUT/summary-$label.txt"
  echo "::endgroup::"
  # Surface each failure as an annotation so it shows on the run page.
  grep -E "error:" "$OUT/test-$label.log" | sed -E 's#^.*/(UITests|App)/#\1/#' | sort -u | head -15 \
    | while IFS= read -r line; do echo "::error::[$label] $line"; done
  if [ $result -ne 0 ]; then
    echo "::error::UI tests failed on $name"
    status=1
  else
    echo "UI tests passed on $name"
  fi
  xcrun simctl shutdown "$udid" 2>/dev/null
done < "$OUT/simulators.txt"

exit $status
