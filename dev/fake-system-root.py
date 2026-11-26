#!/usr/bin/env python3
"""Stands in for pkexec and the three root helpers (tests/test_maintenance.py,
dev/shell-parts: system-maintenance). Symlink it as pkexec, shani-deploy,
shani-health or shani-reset; every call lands in $FAKE_SYSTEM_ROOT/calls. The
health helper writes a bundle into the folder it is given; nothing prints it."""

import os
import sys
import traceback

D = os.environ["FAKE_SYSTEM_ROOT"]


def _logged(t, v, tb):
    with open(os.path.join(D, "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged


def handle(prog: str, a: list[str]) -> int:
    with open(os.path.join(D, "calls"), "a") as f:
        f.write(prog + " " + " ".join(a) + "\n")
    if prog == "pkexec":
        return handle(os.path.basename(a[0]), a[1:]) if a else 2
    if prog == "shani-deploy":
        print("Old update images and journal entries cleaned.")
        return 0
    if prog == "shani-reset":
        print("Reset done.")
        return 0
    if prog == "shani-health" and "--export-logs" in a:
        folder = a[a.index("--export-logs") + 1]
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, "health-bundle.txt")
        with open(path, "w") as f:
            f.write("Bundle text must never reach the page.\n")
        print(path)
        return 0
    return 2


sys.exit(handle(os.path.basename(sys.argv[0]), sys.argv[1:]))
