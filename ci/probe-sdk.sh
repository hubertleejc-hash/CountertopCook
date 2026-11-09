#!/usr/bin/env bash
# Reports the Xcode version, installed iOS runtimes, whether an iPhone Duo device type exists,
# and any fold-layout APIs (ArrangementView, ReservedRegion, hinge angle) in the SDK.
# Informational only; never fails.
set +e

echo "== Xcode"
xcode-select -p
xcodebuild -version
echo
echo "== iOS SDKs"
xcodebuild -showsdks | grep -i ios
echo
echo "== iOS simulator runtimes"
xcrun simctl list runtimes | grep -i "^iOS" || echo "(none)"
echo
echo "== iPhone Duo device type"
if xcrun simctl list devicetypes | grep -q "iPhone Duo"; then
  echo "YES: $(xcrun simctl list devicetypes | grep "iPhone Duo")"
else
  echo "NO: no 'iPhone Duo' device type in this Xcode"
fi
echo "Other Duo / Fold device types:"
xcrun simctl list devicetypes | grep -iE "duo|fold" || echo "(none)"
echo
echo "== Existing iPhone Duo simulators"
xcrun simctl list devices | grep -E "^-- |iPhone Duo" | grep -B1 "iPhone Duo" || echo "(none)"
echo
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
echo "== Fold-related symbols in $SDK"
for fw in SwiftUI UIKit; do
  echo "-- $fw"
  find "$SDK/System/Library/Frameworks/$fw.framework" \( -name "*.swiftinterface" -o -name "*.h" \) 2>/dev/null \
    | xargs grep -hoE "[A-Za-z_]*(ArrangementView|ReservedRegion|[Hh]ingeAngle|[Ff]oldState|[Hh]inge)[A-Za-z_]*" 2>/dev/null \
    | sort | uniq -c | sort -rn | head -30
done
exit 0
