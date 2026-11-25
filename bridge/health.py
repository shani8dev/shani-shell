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

Everything written stays in a sqlite database under XDG_DATA_HOME — nothing is
uploaded, and there is no account. shani-link is optional: when the package, a
paired watch or the hardware is missing, the read commands still return the
local journal with an `error` saying why the watch could not be reached.
"""

from __future__ import annotations

import csv
import json
import os
import sqlite3
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

NOT_INSTALLED = "shani-link is not installed"


def _module(name: str):
    """Import one piece of shani_link, or None when it is not there."""
    try:
        return __import__(name, fromlist=["*"])
    except Exception:  # noqa: BLE001 - any import failure means "no link here"
        return None


watch = _module("shani_link.watch")
moyoung = _module("shani_link.moyoung")
gatt = _module("shani_link.gatt")
phone_bluez = _module("shani_link.phone_bluez")


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
    }
    picked = _pick_watch()
    if not picked:
        out["error"] = (
            NOT_INSTALLED if not (moyoung and gatt) else "no paired watch found"
        )
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
    return out


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
    else:
        print(json.dumps({"error": "unknown command: " + cmd}))
        return 2
    print(json.dumps(answer, ensure_ascii=False, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
