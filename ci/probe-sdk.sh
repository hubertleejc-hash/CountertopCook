#!/usr/bin/env bash
# Reports whether this Xcode has iPhone Duo simulators and fold-layout APIs
# (ArrangementView, ReservedRegion, hinge angle). Informational only; never fails.
set +e

echo "== Xcode"
xcodebuild -version
echo
echo "== iOS SDKs"
xcodebuild -showsdks | grep -i ios
echo
echo "== Simulator device types mentioning Duo / Fold"
xcrun simctl list devicetypes | grep -iE "duo|fold" || echo "(none)"
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
