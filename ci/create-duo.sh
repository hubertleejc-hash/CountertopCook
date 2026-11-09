#!/usr/bin/env bash
# Makes sure an "iPhone Duo" simulator exists on the iOS 27.1 runtime and prints its line in
# the same 'label|udid|name|destination' format as pick_simulators.py.
# Fails loudly if the runtime or device type is missing: never substitutes another iPhone.
set -euo pipefail

fail() {
  echo "::error::$1" >&2
  echo "--- iOS runtimes ---" >&2; xcrun simctl list runtimes >&2 || true
  echo "--- Duo / Fold device types ---" >&2; xcrun simctl list devicetypes | grep -iE "duo|fold" >&2 || echo "(none)" >&2
  exit 1
}

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
for r in json.load(sys.stdin)["runtimes"]:
    ident = r.get("identifier", "")
    if r.get("isAvailable") and ("iOS-27-1" in ident or r.get("name") == "iOS 27.1"):
        print(ident)
        break
')
[ -n "$RUNTIME" ] || fail "iOS 27.1 simulator runtime is not installed, so the iPhone Duo tests cannot run."

DEVTYPE=$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
for d in json.load(sys.stdin)["devicetypes"]:
    if d["name"] == "iPhone Duo":
        print(d["identifier"])
        break
')
[ -n "$DEVTYPE" ] || fail "The 'iPhone Duo' simulator device type does not exist in this Xcode."

UDID=$(xcrun simctl list devices -j | RUNTIME="$RUNTIME" python3 -c '
import json, os, sys
for d in json.load(sys.stdin)["devices"].get(os.environ["RUNTIME"], []):
    if d["name"] == "iPhone Duo" and d.get("isAvailable"):
        print(d["udid"])
        break
')
if [ -z "$UDID" ]; then
  echo "Creating iPhone Duo simulator ($DEVTYPE on $RUNTIME)" >&2
  UDID=$(xcrun simctl create "iPhone Duo" "$DEVTYPE" "$RUNTIME") || fail "Could not create the iPhone Duo simulator."
else
  echo "Using existing iPhone Duo simulator $UDID on $RUNTIME" >&2
fi

echo "Duo|$UDID|iPhone Duo (iOS 27.1)|platform=iOS Simulator,OS=27.1,name=iPhone Duo"
