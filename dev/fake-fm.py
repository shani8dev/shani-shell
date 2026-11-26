#!/usr/bin/env python3
"""Deterministic FM tuner stand-in for dev/shell-parts/devices.sh.

No aerial, no rtl_fm: the radio's state is one small JSON file. What is asked
is logged to $SHANI_FM_LOG, so a live check can see each verb.

  fake-fm.py state                  {"ok":true,"state":"stopped","frequency":0}
  fake-fm.py start [frequency]      state "running"; keeps the last frequency
  fake-fm.py tune <frequency>       change frequency; keep playing state
  fake-fm.py stop                   state "stopped"; frequency kept

Env:
  SHANI_FM_STATE   state file (default /tmp/fake-fm-state.json)
  SHANI_FM_LOG     call log (default /tmp/fake-fm-calls)
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

DEFAULT_FREQUENCY = 98.5


def state_path() -> Path:
    return Path(os.environ.get("SHANI_FM_STATE", "/tmp/fake-fm-state.json"))


def load() -> dict:
    try:
        data = json.loads(state_path().read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
    except (OSError, ValueError):
        pass
    return {"ok": True, "state": "stopped", "frequency": 0}


def save(row: dict) -> None:
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(row), encoding="utf-8")


def main() -> int:
    argv = sys.argv[1:]
    try:
        path = Path(os.environ.get("SHANI_FM_LOG", "/tmp/fake-fm-calls"))
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(" ".join(argv) + "\n")
    except OSError:
        pass  # logging must never stop the radio answer

    row = load()
    cmd = (argv[0] if argv else "state").strip().lower()
    if cmd == "start":
        raw = argv[1] if len(argv) > 1 else ""
        try:
            freq = float(raw) if raw else float(row.get("frequency") or 0)
        except ValueError:
            freq = float(row.get("frequency") or 0)
        if not freq:
            freq = DEFAULT_FREQUENCY
        row = {"ok": True, "state": "running", "frequency": freq}
        save(row)
    elif cmd == "tune" and len(argv) > 1:
        try:
            row["frequency"] = float(argv[1])
        except ValueError:
            pass
        row["ok"] = True
        save(row)
    elif cmd == "stop":
        row["ok"] = True
        row["state"] = "stopped"
        save(row)

    print(
        json.dumps(
            {
                "ok": bool(row.get("ok", True)),
                "state": str(row.get("state", "stopped")),
                "frequency": row.get("frequency", 0),
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
