"""Prints 'label|udid|name' for the fallback simulators: one iPhone and one iPad on the
newest installed iOS runtime. Foldables are skipped here; ci/create-duo.sh handles the Duo."""
import json
import re
import subprocess

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))


def runtime_version(key):
    m = re.search(r"iOS-(\d+)-(\d+)", key)
    return tuple(int(x) for x in m.groups()) if m else None


runtimes = sorted(
    ((runtime_version(k), k, v) for k, v in data["devices"].items() if runtime_version(k) and v),
    reverse=True,
)
if not runtimes:
    raise SystemExit("No iOS simulators available")
version, key, devices = runtimes[0]


def is_fold(name):
    return bool(re.search(r"duo|fold", name, re.I))


def pick(patterns):
    for pattern in patterns:
        for d in devices:
            if re.search(pattern, d["name"]) and not is_fold(d["name"]):
                return d
    return None


choices = []
iphone = pick([r"^iPhone \d+ Pro$", r"^iPhone \d+$", r"^iPhone"])
if iphone:
    choices.append(("iPhone", iphone))
ipad = pick([r"^iPad Pro 13", r"^iPad Pro", r"^iPad Air", r"^iPad"])
if ipad:
    choices.append(("iPad", ipad))

for label, d in choices:
    print(f"{label}|{d['udid']}|{d['name']} (iOS {version[0]}.{version[1]})")
