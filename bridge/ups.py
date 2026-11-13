#!/usr/bin/env python3
"""ups - the UPS this computer runs on, from NUT (shani-peripherals ships it,
shani-settings enables its server and monitor).

    ups.py                    {"present": false} or
                              {"present": true, "name", "model", "onBattery", "low",
                               "charge": 0-100, "minutes": n, "load": 0-100}

UPower does not see a UPS behind NUT, so a desktop on a UPS showed nothing during a
power cut - the moment it matters most. `upsc` reads upsd's variables; the first
UPS on localhost is the one reported. SHANI_UPSC replaces `upsc` (the tests).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

UPSC = os.environ.get("SHANI_UPSC", "upsc")


def run(*args: str) -> str:
    try:
        return subprocess.run([UPSC, *args], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def number(v: str | None) -> float | None:
    try:
        return float(v) if v is not None else None
    except ValueError:
        return None


def read() -> dict:
    names = run("-l", "localhost").split()
    if not names:
        return {"present": False}
    name = names[0]
    var = {}
    for line in run(f"{name}@localhost").splitlines():
        k, sep, v = line.partition(":")
        if sep:
            var[k.strip()] = v.strip()
    status = var.get("ups.status", "").split()
    runtime = number(var.get("battery.runtime"))
    return {"present": True, "name": name,
            "model": " ".join(x for x in (var.get("device.mfr") or var.get("ups.mfr"), var.get("device.model") or var.get("ups.model")) if x),
            "onBattery": "OB" in status, "low": "LB" in status,
            "charge": number(var.get("battery.charge")),
            "minutes": round(runtime / 60) if runtime is not None else None,
            "load": number(var.get("ups.load"))}


if __name__ == "__main__":
    print(json.dumps(read()))
    sys.exit(0)
