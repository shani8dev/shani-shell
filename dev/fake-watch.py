#!/usr/bin/env python3
"""Deterministic paired-watch stand-in for bridge/health.py.

bridge/health.py overlays this JSON onto its local journal when the real watch
engines are absent (SHANI_WATCH_FAKE), so a shell flow can check the dashboard
without a radio or an account.

  fake-watch.py seed    write the full dashboard watch
  fake-watch.py empty   write a watch that is not connected, with no readings
  fake-watch.py on|off  change just the companion switch
  fake-watch.py show    print the current file
  fake-watch.py action <verb> [args...]   the watch engine's actions, no radio

`action` takes the same verbs and values as bridge/phone/watch.py and refuses
the same bad ones. Every action is appended to SHANI_WATCH_ACTION_LOG so a
live check can see the exact call the shell made.

Env: SHANI_WATCH_FAKE (default /tmp/fake-watch.json)
     SHANI_WATCH_ACTION_LOG (default /tmp/fake-watch-actions.jsonl)
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
    "settings": {
        "raise_to_wake": "off",
        "time_format": "24h",
        "units": "metric",
        "step_goal": "10000",
    },
}

EMPTY = {
    "connected": False,
    "battery": -1,
    "distance_m": 0,
    "calories": 0,
    "sleep_stages": [],
    "stress_series": [],
    "settings": {
        "raise_to_wake": "off",
        "time_format": "24h",
        "units": "metric",
        "step_goal": "10000",
    },
}


def seed_fields() -> dict:
    """Where the bridge finds this stand-in and its action log.

    The shell's environment is fixed before a part runs, so a live part cannot
    export a new SHANI_* tool into the already-started QML process. The seeded
    watch file carries the paths instead; the bridge already reads that file.
    """
    return {
        "action_tool": str(Path(__file__).resolve()),
        "action_log": os.environ.get(
            "SHANI_WATCH_ACTION_LOG", "/tmp/fake-watch-actions.jsonl"
        ),
    }


FULL.update(seed_fields())
EMPTY.update(seed_fields())

ACTIONS = (
    "summary",
    "measure",
    "settings",
    "set",
    "sync_time",
    "notify",
    "profile",
    "find",
)
BOOL_SETTINGS = (
    "raise_to_wake",
    "other_app_notifications",
    "sedentary_reminder",
    "breathing_light",
    "power_saving",
)
ENUMS = {"time_format": ("12h", "24h"), "units": ("metric", "imperial")}
INTS = ("step_goal",)
MEASUREMENTS = ("heart_rate", "blood_oxygen", "blood_pressure")


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


def log_path() -> Path:
    env = os.environ.get("SHANI_WATCH_ACTION_LOG", "")
    if env:
        return Path(env)
    return Path(str(load().get("action_log") or "/tmp/fake-watch-actions.jsonl"))


def record(action: str, words: list[str], settings: dict) -> None:
    target = log_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    row = {"action": action, "args": words, "settings": settings}
    with target.open("a", encoding="utf-8") as out:
        out.write(json.dumps(row, ensure_ascii=False) + "\n")


def refuse(message: str) -> int:
    print(json.dumps({"ok": False, "error": message}, ensure_ascii=False), flush=True)
    return 2


def run_action(words: list[str]) -> int:
    """Answer one watch action from state, with the real engine's refusals."""
    action = str(words[0] if words else "summary").strip().lower()
    rest = [str(w) for w in words[1:]]
    if action not in ACTIONS:
        return refuse(
            "action must be one of %s, not %r." % (", ".join(ACTIONS), action)
        )

    data = load() or json.loads(json.dumps(EMPTY))
    settings = data.get("settings")
    if not isinstance(settings, dict):
        settings = json.loads(json.dumps(EMPTY["settings"]))

    note = ""
    if action == "set":
        if len(rest) < 2 or not rest[0] or not rest[1]:
            return refuse("set needs a setting and a value.")
        setting, value = (
            rest[0].strip().lower().replace(" ", "_"),
            rest[1].strip().lower(),
        )
        if setting in BOOL_SETTINGS:
            if value not in ("on", "off", "true", "false", "1", "0"):
                return refuse("%s must be on or off, not %r." % (setting, value))
            value = "on" if value in ("on", "true", "1") else "off"
        elif setting in ENUMS:
            if value not in ENUMS[setting]:
                return refuse(
                    "%s must be one of %s." % (setting, ", ".join(ENUMS[setting]))
                )
        elif setting in INTS:
            try:
                value = str(max(1, int(float(value))))
            except ValueError:
                return refuse("%s must be a whole number." % setting)
        else:
            return refuse("unknown setting %r." % setting)
        settings[setting] = value
        note = "%s is now %s." % (setting.replace("_", " "), value)
    elif action == "sync_time":
        note = "The watch clock was set."
    elif action == "settings":
        note = ", ".join("%s: %s" % (k, v) for k, v in sorted(settings.items()))
    elif action == "notify":
        text = str(rest[0] if rest else "").strip()
        if not text:
            return refuse("notify needs text. Nothing was sent.")
        note = (
            "Sent to the watch: %s. The watch does not confirm it was shown."
            % text[:80]
        )
    elif action == "profile":
        if len(rest) < 4 or any(not w for w in rest[:4]):
            return refuse("profile needs height_cm, weight_kg, age and gender.")
        try:
            numbers = [int(float(w)) for w in rest[:3]]
        except ValueError:
            return refuse("height, weight and age must be numbers.")
        if min(numbers) <= 0:
            return refuse("height, weight and age must be above zero.")
        note = "The watch has your profile (%d cm, %d kg)." % (numbers[0], numbers[1])
    elif action == "measure":
        what = str(rest[0] if rest else "heart_rate").strip().lower().replace(" ", "_")
        what = {"hr": "heart_rate", "spo2": "blood_oxygen", "bp": "blood_pressure"}.get(
            what, what
        )
        if what not in MEASUREMENTS:
            return refuse("what must be heart_rate, blood_oxygen or blood_pressure.")
        note = "The watch measured %s 72." % what.replace("_", " ")
    elif action == "find":
        note = "The watch is ringing."
    elif action == "summary":
        note = "The watch answered."

    data["settings"] = settings
    write(data)
    record(action, rest, settings)
    print(
        json.dumps(
            {"ok": True, "note": note, "settings": settings}, ensure_ascii=False
        ),
        flush=True,
    )
    return 0


def main(argv: list[str]) -> int:
    verb = str(argv[1] if len(argv) > 1 else "show").lower()
    if verb in ("seed", "empty"):
        write(json.loads(json.dumps(FULL if verb == "seed" else EMPTY)))
    elif verb in ("on", "off"):
        data = load() or json.loads(json.dumps(EMPTY))
        data["connected"] = verb == "on"
        write(data)
    elif verb == "action":
        return run_action(argv[2:])
    elif verb != "show":
        print(json.dumps({"error": "watch needs seed, empty, on, off, action or show"}))
        return 2
    print(json.dumps(load(), ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
