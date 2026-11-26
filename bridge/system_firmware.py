#!/usr/bin/env python3
"""system_firmware — the devices and updates behind Settings › System › Firmware updates.

    system_firmware.py devices   {"have", "devices": [{"id", "name", "version",
                                  "vendor", "updates": [{"version", "name",
                                  "description"}]}]}
    system_firmware.py updates   {"have", "updates": [{"id", "name", "version",
                                  "description"}]}
    system_firmware.py apply     {"ok", "output", "error"}

Reads the machine's own fwupd, as the person: no root, no password. `fwupdmgr
update` asks through polkit itself, so no pkexec wrapper is used here. The tool's
JSON fields (DeviceId, Name, Version, VendorId, Releases; VERSION, NAME,
DESCRIPTION) are read as they are; odd or partial shapes give empty lists, not
invented devices. SHANI_FWUPDMGR (tests and stand-ins).
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys

FWUPDMGR = shlex.split(os.environ.get("SHANI_FWUPDMGR", "fwupdmgr"))


def _text(item: dict, *names: str) -> str:
    for name in names:
        value = item.get(name)
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""


def _run(args: list[str], timeout: int = 60):
    if not FWUPDMGR or not shutil.which(FWUPDMGR[0]):
        return None, f"{FWUPDMGR[0] if FWUPDMGR else 'fwupdmgr'} is not available"
    try:
        return subprocess.run(
            FWUPDMGR + args, capture_output=True, text=True, timeout=timeout
        ), ""
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)


def _report(r, fallback: str):
    """fwupd's JSON answer, or an honest error."""
    if r is None:
        return None, fallback
    if r.returncode != 0:
        error = (r.stderr.strip().splitlines() or [f"exit {r.returncode}"])[-1]
        return None, error
    text = (r.stdout or "").strip()
    # fwupd can print a line before its JSON; start at the first JSON bracket.
    starts = [i for i in (text.find("["), text.find("{")) if i >= 0]
    if not starts:
        return None, "fwupd gave no JSON"
    try:
        return json.loads(text[min(starts) :]), ""
    except ValueError as exc:
        return None, f"could not read fwupd's answer: {exc}"


def _rows(data, *keys: str) -> list[dict]:
    if isinstance(data, list):
        return [d for d in data if isinstance(d, dict)]
    if isinstance(data, dict):
        for key in keys:
            if key in data:
                return _rows(data[key])
        if _text(data, "DeviceId", "Name", "Version"):
            return [data]
    return []


def _release(release: dict) -> dict:
    return {
        "version": _text(release, "VERSION", "version"),
        "name": _text(release, "NAME", "name"),
        "description": _text(release, "DESCRIPTION", "description"),
    }


def devices() -> dict:
    out: dict = {"have": False, "devices": [], "error": ""}
    r, error = _run(["get-devices", "--json"])
    data, error = _report(r, error or "could not read devices")
    if error:
        out["error"] = error
        return out
    for d in _rows(data, "Devices", "devices"):
        out["devices"].append(
            {
                "id": _text(d, "DeviceId", "DeviceID", "device_id", "id"),
                "name": _text(d, "Name", "name"),
                "version": _text(d, "Version", "version"),
                "vendor": _text(d, "VendorId", "Vendor", "vendor"),
                "updates": [
                    _release(x)
                    for x in _rows(
                        d.get("Releases", d.get("releases", [])), "Releases", "releases"
                    )
                ],
            }
        )
    out["have"] = True
    return out


def updates() -> dict:
    out: dict = {"have": False, "updates": [], "error": ""}
    r, error = _run(["get-updates", "--json"])
    data, error = _report(r, error or "could not read updates")
    if error:
        out["error"] = error
        return out
    for u in _rows(data, "Updates", "updates"):
        out["updates"].append(
            {
                "id": _text(u, "DeviceId", "device_id", "id"),
                "name": _text(u, "Name", "name"),
                "version": _text(u, "Version", "version"),
                "description": _text(u, "Description", "DESCRIPTION", "description"),
            }
        )
    out["have"] = True
    return out


def apply() -> dict:
    r, error = _run(["update", "--assume-yes", "--no-reboot-check"], timeout=300)
    if r is None:
        return {"ok": False, "output": "", "error": error}
    lines = [
        line.strip()
        for line in (r.stdout + "\n" + r.stderr).replace("\r", "\n").splitlines()
        if line.strip()
    ]
    ok = r.returncode == 0
    return {
        "ok": ok,
        "output": "\n".join(lines[-20:])[:4000],
        "error": ""
        if ok
        else ((r.stderr.strip().splitlines() or lines or [f"exit {r.returncode}"])[-1]),
    }


def main(argv: list[str]) -> int:
    verbs = {"devices": devices, "updates": updates, "apply": apply}
    if len(argv) != 2 or argv[1] not in verbs:
        print("usage: system_firmware.py devices|updates|apply", file=sys.stderr)
        return 2
    print(json.dumps(verbs[argv[1]]()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
