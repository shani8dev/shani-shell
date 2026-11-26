#!/usr/bin/env python3
"""health — the Health app's private, local-first fitness journal.

One JSON answer per command, like every other bridge here:

    health.py summary                 steps (today/yesterday/week), sleep, stress,
                                      workouts, spot readings, watch provenance
    health.py log step <steps> [day]  journal a step count
    health.py log sleep <deep> <light> <awake> [day]
    health.py log workout <kind> <minutes> [steps] [calories] [day]
    health.py import <file.csv|.json> import steps/sleep/workouts from a file
    health.py history [days]          daily rows, oldest first (default 7)
    health.py workouts                the journaled workouts, newest first
    health.py spot <hr|spo2|bp>       one measurement from the watch
    health.py watch-connect state|on|off   read or set the companion switch
    health.py sync-time                    set the paired watch's clock
    health.py watch-settings               read the watch's settings
    health.py watch-set <setting> <value>  change one watch setting
    health.py watch-notify <text>           show a short message on the watch
    health.py watch-profile <cm> <kg> <age> <gender>  give the watch its profile

Everything written stays in a sqlite database under XDG_DATA_HOME — nothing is
uploaded, and there is no account. shani-shell is optional: when the package, a
paired watch or the hardware is missing, the read commands still return the
local journal with an `error` saying why the watch could not be reached.
"""

from __future__ import annotations

import csv
import json
import os
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

NOT_INSTALLED = "the phone backends are not installed"


def _module(name: str):
    """Import one piece of phone, or None when it is not there."""
    try:
        return __import__(name, fromlist=["*"])
    except Exception:  # noqa: BLE001 - any import failure means "no link here"
        return None


watch = _module("phone.watch")
moyoung = _module("phone.moyoung")
gatt = _module("phone.gatt")
phone_bluez = _module("phone.phone_bluez")


def _ok(error: str | None = None) -> dict:
    return {"ok": not error, "error": error or ""}


def _int(value: Any, default: int = 0) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def _day(value: Any = None) -> str:
    """A YYYY-MM-DD day key: an explicit one when given, else today."""
    if value:
        text = str(value).strip()[:10]
        try:
            datetime.strptime(text, "%Y-%m-%d")
            return text
        except ValueError:
            pass
    return datetime.now().date().isoformat()


def _fake_path() -> str:
    """Where a stand-in watch keeps its structured answer (dev only)."""
    return os.environ.get("SHANI_WATCH_FAKE") or ""


def _fake_watch() -> dict:
    """The readable stand-in watch JSON, or {} when there is none."""
    path = _fake_path()
    if not path:
        return {}
    try:
        data = json.loads(Path(path).expanduser().read_text(encoding="utf-8"))
    except (OSError, ValueError):  # no stand-in here: the real path still works
        return {}
    return data if isinstance(data, dict) else {}


def _stages(value: Any) -> list[dict]:
    if not isinstance(value, list):
        return []
    return [
        {"stage": str(row.get("stage") or ""), "minutes": _int(row.get("minutes"))}
        for row in value
        if isinstance(row, dict)
    ]


def _series(value: Any) -> list[dict]:
    if not isinstance(value, list):
        return []
    return [
        {"when": str(row.get("when") or ""), "value": _int(row.get("value"))}
        for row in value
        if isinstance(row, dict)
    ]


def _merge_fake(out: dict) -> None:
    """Overlay a stand-in watch's fields without touching the local journal."""
    fake = _fake_watch()
    if not fake:
        return
    for key in ("device_model", "device_firmware", "last_read"):
        if key in fake:
            out[key] = str(fake[key] or "")[:160]
    if "connected" in fake:
        out["connected"] = bool(fake["connected"])
    if "battery" in fake:
        out["battery"] = _int(fake["battery"], -1)
    if "distance_m" in fake:
        out["distance_m"] = max(0, _int(fake["distance_m"]))
    if "calories" in fake:
        out["calories"] = max(0, _int(fake["calories"]))
    if "sleep_stages" in fake:
        out["sleep_stages"] = _stages(fake["sleep_stages"])
    if "stress_series" in fake:
        out["stress_series"] = _series(fake["stress_series"])


def _db_path() -> Path:
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return Path(base) / "shani-shell" / "health.sqlite3"


def _db() -> sqlite3.Connection:
    path = _db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS days (
            day TEXT PRIMARY KEY, steps INTEGER DEFAULT 0,
            deep_min INTEGER DEFAULT 0, light_min INTEGER DEFAULT 0,
            awake_min INTEGER DEFAULT 0, rem_min INTEGER DEFAULT 0,
            distance_m INTEGER DEFAULT 0, calories INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS workouts (
            id INTEGER PRIMARY KEY AUTOINCREMENT, day TEXT NOT NULL,
            kind TEXT NOT NULL, minutes INTEGER DEFAULT 0,
            steps INTEGER DEFAULT 0, calories INTEGER DEFAULT 0, note TEXT DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS measures (
            id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL,
            kind TEXT NOT NULL, value TEXT NOT NULL, unit TEXT NOT NULL
        );
        """
    )
    return db


# ---- local journal ---------------------------------------------------------


def cmd_history(days: int = 7) -> list[dict]:
    count = max(1, min(365, _int(days, 7)))
    end = datetime.now().date()
    start = end - timedelta(days=count - 1)
    with _db() as db:
        rows = db.execute(
            "SELECT day, steps, deep_min, light_min, awake_min, rem_min, "
            "distance_m, calories FROM days WHERE day BETWEEN ? AND ? ORDER BY day",
            (start.isoformat(), end.isoformat()),
        ).fetchall()
    by_day = {r[0]: r for r in rows}
    out: list[dict] = []
    day = start
    while day <= end:
        r = by_day.get(day.isoformat())
        out.append(
            {
                "day": day.isoformat(),
                "steps": _int(r[1]) if r else 0,
                "deep_min": _int(r[2]) if r else 0,
                "light_min": _int(r[3]) if r else 0,
                "awake_min": _int(r[4]) if r else 0,
                "rem_min": _int(r[5]) if r else 0,
                "distance_m": _int(r[6]) if r else 0,
                "calories": _int(r[7]) if r else 0,
            }
        )
        day += timedelta(days=1)
    return out


def cmd_workouts() -> list[dict]:
    with _db() as db:
        rows = db.execute(
            "SELECT day, kind, minutes, steps, calories, note FROM workouts "
            "ORDER BY day DESC, id DESC LIMIT 50"
        ).fetchall()
    return [
        {
            "day": r[0],
            "kind": r[1],
            "minutes": _int(r[2]),
            "steps": _int(r[3]),
            "calories": _int(r[4]),
            "note": r[5] or "",
            "source": "local",
        }
        for r in rows
    ]


def cmd_measures() -> list[dict]:
    with _db() as db:
        rows = db.execute(
            "SELECT ts, kind, value, unit FROM measures ORDER BY ts DESC, id DESC LIMIT 20"
        ).fetchall()
    out = []
    for ts, kind, value, unit in rows:
        try:
            parsed = json.loads(value)
        except (TypeError, ValueError):
            parsed = []
        out.append({"when": _int(ts), "kind": kind, "value": parsed, "unit": unit})
    return out


def cmd_log(args: list[str]) -> dict:
    if not args:
        return _ok("log needs a kind: step, sleep or workout")
    kind, rest = args[0].lower(), args[1:]
    with _db() as db:
        if kind == "step":
            if not rest:
                return _ok("step needs a count")
            db.execute(
                "INSERT INTO days(day, steps) VALUES(?, ?) ON CONFLICT(day) "
                "DO UPDATE SET steps = excluded.steps",
                (_day(rest[1] if len(rest) > 1 else None), _int(rest[0])),
            )
        elif kind == "sleep":
            if len(rest) < 3:
                return _ok("sleep needs deep, light and awake minutes")
            db.execute(
                "INSERT INTO days(day, deep_min, light_min, awake_min) VALUES(?, ?, ?, ?) "
                "ON CONFLICT(day) DO UPDATE SET deep_min = excluded.deep_min, "
                "light_min = excluded.light_min, awake_min = excluded.awake_min",
                (
                    _day(rest[3] if len(rest) > 3 else None),
                    _int(rest[0]),
                    _int(rest[1]),
                    _int(rest[2]),
                ),
            )
        elif kind == "workout":
            if len(rest) < 2:
                return _ok("workout needs a kind and its minutes")
            db.execute(
                "INSERT INTO workouts(day, kind, minutes, steps, calories, note) "
                "VALUES(?, ?, ?, ?, ?, ?)",
                (
                    _day(rest[4] if len(rest) > 4 else None),
                    str(rest[0])[:80],
                    _int(rest[1]),
                    _int(rest[2] if len(rest) > 2 else 0),
                    _int(rest[3] if len(rest) > 3 else 0),
                    "",
                ),
            )
        else:
            return _ok("unknown log kind: " + kind)
    return _ok()


# ---- import ----------------------------------------------------------------


def _record(value: dict, source: str) -> tuple[str, dict] | None:
    """One CSV/JSON row -> ('day'|'workout', normalised fields)."""
    if not isinstance(value, dict):
        return None
    row = {str(k).strip().lower(): v for k, v in value.items()}
    day = _day(row.get("day") or row.get("date"))
    kind = str(row.get("kind") or row.get("type") or "").strip()
    if kind or "minutes" in row or "duration" in row:
        return "workout", {
            "day": day,
            "kind": kind[:80],
            "minutes": _int(row.get("minutes", row.get("duration"))),
            "steps": _int(row.get("steps")),
            "calories": _int(row.get("calories")),
            "note": str(row.get("note") or "")[:200],
        }
    fields = {
        "day": day,
        "steps": _int(row.get("steps")),
        "deep_min": _int(row.get("deep", row.get("deep_min"))),
        "light_min": _int(row.get("light", row.get("light_min"))),
        "awake_min": _int(row.get("awake", row.get("awake_min"))),
        "rem_min": _int(row.get("rem", row.get("rem_min"))),
        "distance_m": _int(row.get("distance_m")),
        "calories": _int(row.get("calories")),
    }
    return (
        ("day", fields)
        if any(
            fields[k]
            for k in ("steps", "deep_min", "light_min", "awake_min", "rem_min")
        )
        else None
    )


def _json_records(data: Any) -> list[tuple[str, dict]]:
    groups = (
        [data]
        if isinstance(data, list)
        else [
            data.get(key, []) if isinstance(data, dict) else []
            for key in ("days", "steps", "sleep", "workouts", "records")
        ]
    )
    out = []
    for group in groups:
        if isinstance(group, dict):
            group = [group]
        for row in group if isinstance(group, list) else []:
            got = _record(row, "json")
            if got:
                out.append(got)
    return out


def cmd_import(path: str) -> dict:
    try:
        text = Path(path).expanduser().read_text(encoding="utf-8-sig")
    except OSError as exc:
        return {**_ok(str(exc)[:160]), "imported": 0}
    suffix = Path(path).suffix.lower()
    if suffix == ".json":
        try:
            records = _json_records(json.loads(text))
        except ValueError as exc:
            return {**_ok("bad JSON: " + str(exc)[:120]), "imported": 0}
    elif suffix == ".csv":
        try:
            records = [
                got
                for got in (
                    _record(row, "csv") for row in csv.DictReader(text.splitlines())
                )
                if got
            ]
        except csv.Error as exc:
            return {**_ok("bad CSV: " + str(exc)[:120]), "imported": 0}
    else:
        return {**_ok("import needs a .csv or .json file"), "imported": 0}

    with _db() as db:
        for kind, row in records:
            if kind == "day":
                db.execute(
                    "INSERT INTO days(day, steps, deep_min, light_min, awake_min, rem_min, "
                    "distance_m, calories) VALUES(:day, :steps, :deep_min, :light_min, "
                    ":awake_min, :rem_min, :distance_m, :calories) ON CONFLICT(day) DO UPDATE SET "
                    "steps = MAX(days.steps, excluded.steps), "
                    "deep_min = MAX(days.deep_min, excluded.deep_min), "
                    "light_min = MAX(days.light_min, excluded.light_min), "
                    "awake_min = MAX(days.awake_min, excluded.awake_min), "
                    "rem_min = MAX(days.rem_min, excluded.rem_min), "
                    "distance_m = MAX(days.distance_m, excluded.distance_m), "
                    "calories = MAX(days.calories, excluded.calories)",
                    row,
                )
            else:
                db.execute(
                    "INSERT INTO workouts(day, kind, minutes, steps, calories, note) "
                    "VALUES(:day, :kind, :minutes, :steps, :calories, :note)",
                    row,
                )
    return {**_ok(), "imported": len(records)}


# ---- the watch (optional) ---------------------------------------------------


def _pick_watch() -> tuple[str, str] | None:
    """(mac, name) of the paired watch, or None when there is none to read."""
    if not all((watch, gatt, phone_bluez)):
        return None
    try:
        phones = {a for a, _n, _c in phone_bluez.phones()}
        found = [
            (m, n)
            for m, n in gatt.paired()
            if gatt.looks_like_low_energy(m) and m not in phones
        ]
        return found[0] if found else None
    except Exception:  # noqa: BLE001 - no bluez, no watch, no answer
        return None


def _steps(value: Any) -> int:
    return _int((value or {}).get("steps") if isinstance(value, dict) else value)


def cmd_summary() -> dict:
    history = cmd_history(7)
    today = history[-1]
    out: dict[str, Any] = {
        "steps_today": today["steps"],
        "steps_yesterday": history[-2]["steps"] if len(history) > 1 else 0,
        "steps_week": [row["steps"] for row in history],
        "step_goal": 10000,
        "sleep": {
            "deep": today["deep_min"],
            "light": today["light_min"],
            "awake": today["awake_min"],
            "rem": today["rem_min"],
            "asleep": today["deep_min"] + today["light_min"],
        },
        "stress": [],
        "workouts": cmd_workouts(),
        "measures": cmd_measures(),
        "battery": -1,
        "device": "",
        "history": history,
        "error": "",
        "device_model": "",
        "device_firmware": "",
        "last_read": "",
        "connected": False,
        "distance_m": 0,
        "calories": 0,
        "sleep_stages": [],
        "stress_series": [],
    }
    # A stand-in watch is the whole watch read in a test: do not also look for
    # real BlueZ/GATT hardware, which can block for seconds on a cold bus.
    if _fake_watch():
        _merge_fake(out)
        return out
    picked = _pick_watch()
    if not picked:
        out["error"] = (
            NOT_INSTALLED if not (moyoung and gatt) else "no paired watch found"
        )
        _merge_fake(out)
        return out
    mac, name = picked
    try:
        s = moyoung.health_summary(mac)
    except Exception as exc:  # noqa: BLE001 - an unreachable watch is not a crash
        out["error"] = "watch did not answer: " + str(exc)[:120]
        return out

    out["device"] = name
    out["battery"] = _int(s.get("battery"), -1)
    out["step_goal"] = _int(s.get("step_goal"), 10000) or 10000
    out["steps_today"] = _steps(s.get("steps_today")) or out["steps_today"]
    out["steps_yesterday"] = _steps(s.get("steps_yesterday")) or out["steps_yesterday"]
    out["steps_week"][-1] = out["steps_today"]
    out["steps_week"][-2] = out["steps_yesterday"]
    sleep = s.get("sleep_summary") or {}
    if sleep:
        out["sleep"] = {
            "deep": _int(sleep.get("deep_minutes")),
            "light": _int(sleep.get("light_minutes")),
            "awake": _int(sleep.get("awake_minutes")),
            "rem": 0,
            "asleep": _int(sleep.get("asleep_minutes")),
        }
    stress = []
    for when, value in s.get("stress_today") or []:
        stress.append(
            {
                "when": when.isoformat() if isinstance(when, datetime) else str(when),
                "value": _int(value),
            }
        )
    out["stress"] = stress
    for t in s.get("training") or []:
        start = t.get("start")
        out["workouts"].append(
            {
                "day": start.date().isoformat()
                if isinstance(start, datetime)
                else _day(),
                "kind": str(t.get("type") or "workout"),
                "minutes": _int(t.get("active_seconds")) // 60,
                "steps": _int(t.get("steps")),
                "calories": _int(t.get("calories")),
                "note": "",
                "source": "watch",
            }
        )
    out["workouts"].sort(key=lambda w: w["day"], reverse=True)

    # The dashboard wants the watch's own words for these; the summary is the
    # only read we do, so anything it does not carry stays honestly empty.
    out["connected"] = True
    out["last_read"] = datetime.now().astimezone().isoformat(timespec="minutes")
    steps = s.get("steps_today") or {}
    if isinstance(steps, dict):
        out["distance_m"] = max(0, _int(steps.get("distance_m")))
        out["calories"] = max(0, _int(steps.get("calories")))
    device = s.get("device") or {}
    if isinstance(device, dict):
        out["device_model"] = str(device.get("model") or device.get("product") or "")[
            :160
        ]
        out["device_firmware"] = str(
            device.get("software") or device.get("firmware") or ""
        )[:160]
    out["sleep_stages"] = _stages(s.get("sleep"))
    out["stress_series"] = stress
    _merge_fake(out)
    return out


def cmd_watch_connect(state: str) -> dict:
    """Read or set the companion switch, locally, with no upload."""
    state = str(state or "").strip().lower()
    if state not in ("state", "on", "off"):
        return {**_ok("use state, on or off"), "connected": False}
    data = _fake_watch()
    current = bool(data.get("connected", False))
    if state == "state":
        return {**_ok(), "connected": current}

    on = state == "on"
    path = _fake_path()
    if path:
        data["connected"] = on
        try:
            target = Path(path).expanduser()
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(
                json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
        except OSError as exc:
            return {**_ok(str(exc)[:160]), "connected": current}

    settings = _module("phone.settings")
    if settings is not None:
        try:
            store = settings.Settings()
            if hasattr(store, "set_bool"):
                store.set_bool("watch-companion-enabled", on)
            else:
                store.set("watch-companion-enabled", "true" if on else "false")
        except Exception as exc:  # noqa: BLE001 - a missing phone app is an answer
            return {**_ok("watch setting: " + str(exc)[:120]), "connected": current}
    return {**_ok(), "connected": on}


def cmd_spot(kind: str) -> dict:
    kind = {
        "hr": "heart_rate",
        "spo2": "blood_oxygen",
        "oxygen": "blood_oxygen",
        "bp": "blood_pressure",
    }.get(kind.lower() if kind else "", kind or "")
    if kind not in ("heart_rate", "blood_oxygen", "blood_pressure"):
        return {
            **_ok("spot needs hr, spo2 or bp"),
            "kind": kind,
            "value": [],
            "unit": "",
        }
    picked = _pick_watch()
    if not picked:
        reason = NOT_INSTALLED if not (moyoung and gatt) else "no paired watch found"
        return {**_ok(reason), "kind": kind, "value": [], "unit": ""}
    mac, _name = picked
    try:
        got = moyoung.measure(mac, kind)
    except Exception as exc:  # noqa: BLE001 - hardware errors are answers, not crashes
        return {
            **_ok("measurement failed: " + str(exc)[:120]),
            "kind": kind,
            "value": [],
            "unit": "",
        }
    if not got:
        return {
            **_ok("no reading — wear the watch snugly and keep still for a minute"),
            "kind": kind,
            "value": [],
            "unit": "",
        }
    values = [int(v) for v in got]
    unit = (
        "mmHg" if kind == "blood_pressure" else ("bpm" if kind == "heart_rate" else "%")
    )
    with _db() as db:
        db.execute(
            "INSERT INTO measures(ts, kind, value, unit) VALUES(?, ?, ?, ?)",
            (int(time.time()), kind, json.dumps(values), unit),
        )
    return {**_ok(), "kind": kind, "value": values, "unit": unit}


def cmd_find_watch() -> dict:
    """Ring the paired watch so a person can find it."""
    if not watch:
        return _ok(NOT_INSTALLED)
    try:
        answer = watch.run({"action": "find"})
    except Exception as exc:  # noqa: BLE001 - no radio here is an answer, not a crash
        return _ok(str(exc)[:160])
    return {**_ok(), "note": str(answer or "")}


# ---- watch actions: the one call to the watch's owner -----------------------


_WATCH_ARGS = (
    "setting",
    "value",
    "what",
    "text",
    "kind",
    "sender",
    "height_cm",
    "weight_kg",
    "age",
    "gender",
)


def _watch_action(arguments: dict) -> dict:
    """The single call to the paired watch (or its stand-in), returning data.

    `phone.watch` is the one owner of the watch; no logic is copied here. A dev
    stand-in takes the same verbs and values and refuses the same bad ones.
    """
    tool = os.environ.get("SHANI_WATCH_ACTION_TOOL", "").strip()
    if not tool:
        # A live part cannot export into an already-started shell, so the dev
        # watch file carries the stand-in's path (the bridge already reads it).
        tool = str(_fake_watch().get("action_tool") or "").strip()
    if tool:
        words = [str(arguments.get("action") or "")]
        words += [
            str(arguments[k])
            for k in _WATCH_ARGS
            if k in arguments and arguments[k] not in (None, "")
        ]
        try:
            proc = subprocess.run(
                [sys.executable, tool, "action"] + words,
                capture_output=True,
                text=True,
                timeout=30,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            return _ok("watch stand-in: " + str(exc)[:120])
        try:
            data = json.loads(proc.stdout)
        except (TypeError, ValueError):
            return _ok("watch stand-in did not answer")
        if not isinstance(data, dict):
            return _ok("watch stand-in did not answer")
        settings = (
            data.get("settings") if isinstance(data.get("settings"), dict) else {}
        )
        if proc.returncode != 0 or not data.get("ok"):
            return {
                **_ok(str(data.get("error") or "watch action failed")[:160]),
                "note": "",
                "settings": settings,
            }
        return {**_ok(), "note": str(data.get("note") or ""), "settings": settings}

    if not watch:
        return {**_ok(NOT_INSTALLED), "note": "", "settings": {}}
    run = getattr(watch, "run", None) or getattr(watch, "_run", None)
    if run is None:
        return {**_ok(NOT_INSTALLED), "note": "", "settings": {}}
    try:
        answer = run(arguments)
    except Exception as exc:  # noqa: BLE001 - no radio is an answer, not a crash
        return {**_ok(str(exc)[:160]), "note": "", "settings": {}}
    return {**_ok(), "note": str(answer or ""), "settings": {}}


def cmd_sync_time() -> dict:
    """Set the watch's clock from this computer."""
    return _watch_action({"action": "sync_time"})


def cmd_watch_settings() -> dict:
    """Read the watch's own settings."""
    return _watch_action({"action": "settings"})


def cmd_watch_set(setting: str, value: str) -> dict:
    """Change one setting; bool settings take on/off, enums take their word."""
    setting = str(setting or "").strip().lower().replace(" ", "_")
    value = str(value or "").strip().lower()
    if not setting or not value:
        return {**_ok("set needs a setting and a value"), "note": "", "settings": {}}
    return _watch_action({"action": "set", "setting": setting, "value": value})


def cmd_watch_notify(text: str) -> dict:
    """Show a short message on the watch."""
    text = str(text or "").strip()
    if not text:
        return {**_ok("notify needs text"), "note": "", "settings": {}}
    return _watch_action(
        {
            "action": "notify",
            "text": text[:200],
            "kind": "other",
            "sender": "Health",
        }
    )


def cmd_watch_profile(height: str, weight: str, age: str, gender: str) -> dict:
    """Give the watch the profile it uses for calories; it cannot measure it."""
    values = (height, weight, age, gender)
    if any(v in (None, "") for v in values):
        return {
            **_ok("profile needs height, weight, age and gender"),
            "note": "",
            "settings": {},
        }
    try:
        numbers = [int(float(v)) for v in values[:3]]
    except (TypeError, ValueError):
        return {
            **_ok("height, weight and age must be numbers"),
            "note": "",
            "settings": {},
        }
    if min(numbers) <= 0:
        return {
            **_ok("height, weight and age must be above zero"),
            "note": "",
            "settings": {},
        }
    return _watch_action(
        {
            "action": "profile",
            "height_cm": numbers[0],
            "weight_kg": numbers[1],
            "age": numbers[2],
            "gender": str(gender).strip().lower(),
        }
    )


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"error": "usage: health.py <command> [args]"}))
        return 2
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "summary":
        answer: Any = cmd_summary()
    elif cmd == "log":
        answer = cmd_log(args)
    elif cmd == "import":
        answer = cmd_import(args[0]) if args else _ok("import needs a file")
    elif cmd == "history":
        answer = cmd_history(_int(args[0], 7) if args else 7)
    elif cmd == "workouts":
        answer = cmd_workouts()
    elif cmd == "measures":
        answer = cmd_measures()
    elif cmd == "spot":
        answer = cmd_spot(args[0] if args else "")
    elif cmd == "find-watch":
        answer = cmd_find_watch()
    elif cmd == "watch-connect":
        answer = cmd_watch_connect(args[0] if args else "state")
    elif cmd == "sync-time":
        answer = cmd_sync_time()
    elif cmd == "watch-settings":
        answer = cmd_watch_settings()
    elif cmd == "watch-set":
        answer = cmd_watch_set(
            args[0] if args else "", args[1] if len(args) > 1 else ""
        )
    elif cmd == "watch-notify":
        answer = cmd_watch_notify(args[0] if args else "")
    elif cmd == "watch-profile":
        answer = cmd_watch_profile(*(args + [""] * 4)[:4])
    else:
        print(json.dumps({"error": "unknown command: " + cmd}))
        return 2
    print(json.dumps(answer, ensure_ascii=False, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
