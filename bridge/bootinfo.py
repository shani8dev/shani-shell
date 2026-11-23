#!/usr/bin/env python3
"""bootinfo — the boot slots and what a boot left behind, for Settings.

`shani-deploy --status --json` is the documented read: it needs no root and no
deploy lock (shani-testbed/slot-tests/deploy-status.sh checks exactly that).
Rollback itself stays with shani-deploy and authorisation; this page only reads.

    bootinfo.py status      {"available": bool, "fields": {...}}
    bootinfo.py             the same
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys

TIMEOUT = 12
# what the deploy script reports, and what a person needs to see
FIELDS = [
    ("version", "Version"),
    ("profile", "Profile"),
    ("channel", "Channel"),
    ("booted_slot", "Running from"),
    ("current_slot", "Current slot"),
    ("previous_slot", "Previous slot"),
    ("candidate_boot", "Still a candidate boot"),
    ("update_available", "Update waiting"),
    ("boot_failure", "Boot failure marker"),
    ("auto_rollback_done", "Rolled back on its own"),
]


def _read(path):
    try:
        return open(path, encoding="utf-8").read().strip()
    except OSError:
        return ""


def _yes(v):
    if isinstance(v, bool):
        return "yes" if v else "no"
    return str(v) if v not in (None, "") else ""


def _secure_boot():
    if shutil.which("mokutil") is None:
        return ""
    try:
        p = subprocess.run(["mokutil", "--sb-state"], capture_output=True, text=True, timeout=4)
        t = (p.stdout or p.stderr).strip()
        if "SecureBoot enabled" in t:
            return "enabled"
        if "SecureBoot disabled" in t:
            return "disabled"
        return t.splitlines()[0][:80] if t else ""
    except Exception:
        return ""


def _encryption():
    # LUKS devices currently present; read-only, no root.
    if shutil.which("lsblk") is None:
        return []
    try:
        p = subprocess.run(["lsblk", "-J", "-o", "NAME,TYPE,FSTYPE"], capture_output=True, text=True, timeout=4)
        d = json.loads(p.stdout or "{}")
    except Exception:
        return []
    found = []
    def walk(nodes):
        for n in nodes or []:
            if n.get("fstype") == "crypto_LUKS" or n.get("type") == "crypt":
                found.append(n.get("name", ""))
            walk(n.get("children"))
    walk(d.get("blockdevices"))
    return found


def cmd_status():
    rows = []
    available = True
    note = ""
    if shutil.which("shani-deploy") is None:
        available = False
        note = "shani-deploy is not installed, so the slots cannot be read."
        # still report what we can read ourselves
        rows.append({"label": "Release file", "value": _read("/etc/shani-version"), "detail": "/etc/shani-version", "status": ""})
        rows.append({"label": "Selected slot", "value": _read("/data/current-slot"), "detail": "/data/current-slot", "status": ""})
    else:
        try:
            p = subprocess.run(
                ["shani-deploy", "--status", "--json"],
                capture_output=True,
                text=True,
                timeout=TIMEOUT,
            )
        except Exception as exc:  # noqa: BLE001
            return {"available": False, "note": f"Could not ask shani-deploy: {exc}"}
        try:
            d = json.loads(p.stdout) or {}
        except Exception:
            return {"available": False, "note": "shani-deploy did not answer with JSON."}
        for key, label in FIELDS:
            v = d.get(key)
            if v in (None, "", False, [], {}):
                continue
            status = ""
            if key == "booted_slot" and v:
                status = "ok"
            if key == "boot_failure" and v:
                status = "fail"
            if key == "auto_rollback_done" and v is True:
                status = "warn"
            rows.append({"label": label, "value": _yes(v), "detail": key, "status": status})
        rows.append({"label": "Release file", "value": _read("/etc/shani-version"), "detail": "/etc/shani-version", "status": ""})
        rows.append({"label": "Selected slot", "value": _read("/data/current-slot"), "detail": "/data/current-slot", "status": ""})
    sb = _secure_boot()
    if sb:
        rows.append({"label": "Secure Boot", "value": sb, "detail": "mokutil --sb-state", "status": "ok" if sb == "enabled" else "warn"})
    enc = _encryption()
    if enc:
        rows.append({"label": "Encrypted volumes", "value": ", ".join(enc), "detail": "lsblk", "status": "ok"})
    return {"available": available, "rows": rows, "note": note}


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "status":
        print(json.dumps(cmd_status(), ensure_ascii=False))
        return 0
    print(json.dumps({"error": "usage: bootinfo.py status"}))
    return 2


if __name__ == "__main__":
    sys.exit(main())
