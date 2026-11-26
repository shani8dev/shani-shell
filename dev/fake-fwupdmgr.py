#!/usr/bin/env python3
"""Stands in for fwupdmgr (tests/test_system_firmware.py, dev/shell-parts:
firmware): two devices in fwupd's own JSON shape, one release offered, and a
progress-printing update. Calls go to $FAKE_FWUPDMGR/calls like fake-podman."""

import json
import os
import sys
import time
import traceback

D = os.environ["FAKE_FWUPDMGR"]


def _logged(t, v, tb):
    with open(os.path.join(D, "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged

RELEASE = {
    "VERSION": "1.3.0",
    "NAME": "System firmware 1.3.0",
    "DESCRIPTION": "Improves battery life and fixes a boot problem.",
}
DEVICES = [
    {
        "DeviceId": "a1b2c3d4",
        "Name": "Laptop system firmware",
        "Version": "1.2.3",
        "VendorId": "shani",
        "Releases": [RELEASE],
    },
    {
        "DeviceId": "e5f6a7b8",
        "Name": "Storage controller",
        "Version": "2.0.0",
        "VendorId": "storage",
        "Releases": [],
    },
]
UPDATES = [
    {
        "DeviceId": "a1b2c3d4",
        "Name": "Laptop system firmware",
        "Version": "1.3.0",
        "Description": "Improves battery life and fixes a boot problem.",
    }
]

a = sys.argv[1:]
with open(os.path.join(D, "calls"), "a") as f:
    f.write(os.path.basename(sys.argv[0]) + " " + " ".join(a) + "\n")

if os.environ.get("FAKE_FWUPDMGR_BROKEN"):
    print("not json at all")
    sys.exit(0)

wrapped = os.environ.get("FAKE_FWUPDMGR_SHAPE") == "object"
if a[:2] == ["get-devices", "--json"]:
    print(json.dumps({"Devices": DEVICES} if wrapped else DEVICES))
elif a[:2] == ["get-updates", "--json"]:
    print(json.dumps({"Updates": UPDATES} if wrapped else UPDATES))
elif a[:1] == ["update"]:
    for line in ("Fetching update", "Writing firmware", "Restart is not needed"):
        print(line)
        sys.stdout.flush()
        time.sleep(0.05)
    sys.exit(0)
else:
    print("unknown fwupdmgr command", file=sys.stderr)
    sys.exit(2)
