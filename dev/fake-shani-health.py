#!/usr/bin/env python3
"""Stands in for shani-health (tests/test_system_health.py, dev/shell-parts:
system-health): five mixed checks in the tool's own JSON shape, a saved bundle
for --export-logs, and a call log in $FAKE_SHANI_HEALTH/calls like fake-podman."""

import json
import os
import sys
import traceback

D = os.environ["FAKE_SHANI_HEALTH"]


def _logged(t, v, tb):
    with open(os.path.join(D, "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged

CHECKS = [
    {
        "key": "updates",
        "title": "System updates",
        "status": "ok",
        "detail": "All updates installed",
    },
    {"key": "space", "title": "Free space", "status": "pass", "detail": "18 GB free"},
    {
        "key": "services",
        "title": "Background services",
        "status": "degraded",
        "detail": "Two did not start",
    },
    {
        "key": "permissions",
        "title": "File permissions",
        "status": "error",
        "detail": "One folder is open to all",
    },
    {
        "key": "backup",
        "title": "Backups",
        "status": "skipped",
        "detail": "No backup set up",
    },
]

a = sys.argv[1:]
with open(os.path.join(D, "calls"), "a") as f:
    f.write(os.path.basename(sys.argv[0]) + " " + " ".join(a) + "\n")

if "--export-logs" in a:
    folder = a[a.index("--export-logs") + 1]
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "health-bundle.txt")
    with open(path, "w") as f:
        f.write("Five checks; two need attention.\n")
    print(path)
    sys.exit(0)

if os.environ.get("FAKE_SHANI_HEALTH_BROKEN"):
    print("not json at all")
    sys.exit(0)

shape = os.environ.get("FAKE_SHANI_HEALTH_SHAPE", "checks")
if shape == "list":
    report = CHECKS
elif shape == "report":
    report = {"report": CHECKS}
elif shape == "empty":
    report = {"checks": []}
elif shape == "tool":
    report = {
        "ok": False,
        "errors": 1,
        "checks": [
            {
                "name": "System integrity",
                "status": "fail",
                "message": "One slot did not match",
            }
        ],
    }
else:
    report = {"checks": CHECKS}
print(json.dumps(report))
# The real tool exits 1 when a check fails and still prints its JSON.
sys.exit(1 if os.environ.get("FAKE_SHANI_HEALTH_EXIT") else 0)
