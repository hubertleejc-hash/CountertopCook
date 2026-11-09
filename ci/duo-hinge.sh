#!/usr/bin/env bash
# Moves a booted iPhone Duo simulator's hinge: ci/duo-hinge.sh <udid> <degrees 0-180>
# 180 = fully open (inner display), about 120 = partially open, 0 = closed.
# Builds ci/duo-hinge.m for the simulator once, then runs it inside the simulator.
set -euo pipefail

UDID=${1:?usage: duo-hinge.sh <udid> <degrees>}
DEGREES=${2:?usage: duo-hinge.sh <udid> <degrees>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/duo-hinge"
HELPER="$BUILD/duo-hinge"

if [ ! -x "$HELPER" ]; then
  mkdir -p "$BUILD"
  cat > "$BUILD/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.springboard.sbdisplay.service</key><true/></dict></plist>
PLIST
  xcrun --sdk iphonesimulator clang -fobjc-arc -arch arm64 -mios-simulator-version-min=27.1 \
    -framework Foundation -Wl,-sectcreate,__TEXT,__entitlements,"$BUILD/entitlements.plist" \
    "$ROOT/ci/duo-hinge.m" -o "$HELPER"
  codesign -s - -f "$HELPER"
fi

xcrun simctl spawn "$UDID" "$HELPER" "$DEGREES" 2 < /dev/null
# The display hand-off after a fold takes a moment.
sleep 5
