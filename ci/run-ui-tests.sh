#!/usr/bin/env bash
# Builds the app once, then runs the UI test suite on each picked simulator.
# Screenshots land in ci-output/screenshots, result bundles in ci-output/*.xcresult.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/ci-output"
DERIVED="$ROOT/build/DerivedData"
mkdir -p "$OUT/screenshots"

python3 "$ROOT/ci/pick_simulators.py" | tee "$OUT/simulators.txt"

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
while IFS='|' read -r label udid name; do
  [ -z "$udid" ] && continue
  echo "::group::UI tests on $name"
  xcrun simctl boot "$udid" 2>/dev/null
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
  TEST_RUNNER_SCREENSHOT_DIR="$OUT/screenshots" xcodebuild test-without-building \
    -project "$ROOT/CountertopCook.xcodeproj" \
    -scheme CountertopCook \
    -destination "id=$udid" \
    -derivedDataPath "$DERIVED" \
    -resultBundlePath "$OUT/$label.xcresult" \
    > "$OUT/test-$label.log" 2>&1
  result=$?
  grep -E "Test Case .* (passed|failed)|error:|XCTAssert|\*\* TEST" "$OUT/test-$label.log"
  echo "::endgroup::"
  if [ $result -ne 0 ]; then
    echo "::error::UI tests failed on $name"
    status=1
  else
    echo "UI tests passed on $name"
  fi
  xcrun simctl shutdown "$udid" 2>/dev/null
done < "$OUT/simulators.txt"

exit $status
