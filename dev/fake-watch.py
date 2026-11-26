#!/usr/bin/env python3
"""Deterministic paired-watch stand-in for bridge/health.py.

bridge/health.py overlays this JSON onto its local journal when the real watch
engines are absent (SHANI_WATCH_FAKE), so a shell flow can check the dashboard
without a radio or an account.

  fake-watch.py seed    write the full dashboard watch
  fake-watch.py empty   write a watch that is not connected, with no readings
  fake-watch.py on|off  change just the companion switch
  fake-watch.py show    print the current file

Env: SHANI_WATCH_FAKE (default /tmp/fake-watch.json)
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

FULL = {
    "device_model": "Pulse Watch 2",
    "device_firmware": "1.4.2",
    "last_read": "2026-11-26T09:30+05:30",
    "connected": True,
    "battery": 76,
    "distance_m": 7240,
    "calories": 412,
    "sleep_stages": [
        {"stage": "deep", "minutes": 92},
        {"stage": "light", "minutes": 240},
        {"stage": "rem", "minutes": 60},
        {"stage": "awake", "minutes": 18},
    ],
    "stress_series": [
        {"when": "08:00", "value": 22},
        {"when": "09:00", "value": 31},
        {"when": "10:00", "value": 45},
        {"when": "11:00", "value": 38},
        {"when": "12:00", "value": 26},
        {"when": "13:00", "value": 54},
        {"when": "14:00", "value": 41},
        {"when": "15:00", "value": 29},
    ],
}

EMPTY = {
    "connected": False,
    "battery": -1,
    "distance_m": 0,
    "calories": 0,
    "sleep_stages": [],
    "stress_series": [],
}


def path() -> Path:
    return Path(os.environ.get("SHANI_WATCH_FAKE", "/tmp/fake-watch.json"))


def load() -> dict:
    try:
        data = json.loads(path().read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
    except (OSError, ValueError):
        pass
    return {}


def write(data: dict) -> None:
    target = path()
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(".tmp")
    tmp.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    tmp.replace(target)


def main(argv: list[str]) -> int:
    verb = str(argv[1] if len(argv) > 1 else "show").lower()
    if verb in ("seed", "empty"):
        write(json.loads(json.dumps(FULL if verb == "seed" else EMPTY)))
    elif verb in ("on", "off"):
        data = load() or json.loads(json.dumps(EMPTY))
        data["connected"] = verb == "on"
        write(data)
    elif verb != "show":
        print(json.dumps({"error": "watch needs seed, empty, on, off or show"}))
        return 2
    print(json.dumps(load(), ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
