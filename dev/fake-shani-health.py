#!/usr/bin/env python3
"""Stands in for shani-health (tests/test_system_health.py, dev/shell-parts:
system-health): five mixed checks in the tool's own JSON shape, a Btrfs
storage report for --storage-info, a saved bundle for --export-logs, and a
call log in $FAKE_SHANI_HEALTH/calls like fake-podman. Also stands in for
pkexec, which just passes the helper's argv through."""

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

STORAGE_CHECKS = [
    {
        "section": "storage_info",
        "key": "Free",
        "status": "ok",
        "message": "42 GB free of 512 GB",
    },
    {"section": "storage_info", "key": "Total", "status": "info", "message": "512 GB"},
    {
        "section": "storage_info",
        "key": "Used",
        "status": "info",
        "message": "470 GB (ratio: 480 GB)",
    },
    {
        "section": "storage_info",
        "key": "Snapshots",
        "status": "ok",
        "message": "12 snapshots",
    },
    {
        "section": "storage_info",
        "key": "Quotas",
        "status": "ok",
        "message": "consistent",
    },
    {
        "section": "storage_info",
        "key": "Scrub",
        "status": "ok",
        "message": "last run clean",
    },
    {
        "section": "storage_info",
        "key": "Scrub tmr",
        "status": "ok",
        "message": "enabled",
    },
    {
        "section": "storage_info",
        "key": "Maint tmrs",
        "status": "warning",
        "message": "2 of 4 timers not enabled",
    },
    {"section": "storage_info", "key": "bees", "status": "ok", "message": "running"},
    {
        "section": "storage_info",
        "key": "Dev errors",
        "status": "critical",
        "message": "non-zero error counters detected",
    },
    {
        "section": "storage_info",
        "key": "Dedup",
        "status": "info",
        "message": "not configured",
    },
    {
        "section": "storage_info",
        "key": "@home",
        "status": "ok",
        "message": "12G (ratio: 20G)",
    },
    {
        "section": "storage_info",
        "key": "@snapshots",
        "status": "warning",
        "message": "960K (ratio: 16M)",
    },
]
# Continuation rows from the real tool. They are not capacity keys and must
# never appear as summary rows or warnings.
STORAGE_CHECKS += [
    {
        "section": "storage_info",
        "key": "row2",
        "status": "info",
        "message": "detail line %d" % i,
    }
    for i in range(20)
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

if "-s" in a or "--storage-info" in a:
    # The real tool fails before it prints any JSON: a mount failure or a
    # cancelled pkexec leaves stdout empty and only a FATAL line on stderr.
    if os.environ.get("FAKE_SHANI_HEALTH_STORAGE_FAIL"):
        print("FATAL Could not mount root at subvolid=5", file=sys.stderr)
        sys.exit(1)
    print(
        json.dumps(
            {
                "timestamp": "2026-11-26T12:00:00+00:00",
                "checks": STORAGE_CHECKS,
            }
        )
    )
    sys.exit(1 if os.environ.get("FAKE_SHANI_HEALTH_STORAGE_EXIT") else 0)

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
