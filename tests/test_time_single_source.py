"""Time.js is the single source for day labels and clock text.

These run the real shipped JS under node, so a change to a shared helper is
verified against the same code every surface calls.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TIME = ROOT / "shani/Common/Time.js"
NODE = shutil.which("node")


def run_js(body: str) -> str:
    prog = (
        "const T = {};\n"
        + TIME.read_text(encoding="utf-8").replace(".pragma library", "")
        + "\nObject.assign(T, { dayKey, dayLabel, fullDate, minutes, clock, duration });\n"
        + body
    )
    r = subprocess.run([NODE, "-e", prog], capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


def test_day_key_handles_date_ms_and_iso():
    out = run_js(
        "console.log(JSON.stringify({"
        " d: dayKey(new Date(2026, 10, 25)),"
        " iso: dayKey('2026-11-25T10:00:00'),"
        " bad: dayKey('not-a-date') }))"
    )
    got = json.loads(out)
    assert got["d"] == "2026-11-25"
    assert got["iso"] == "2026-11-25"
    assert got["bad"] == ""


def test_day_label_today_yesterday_and_date():
    out = run_js(
        "const now = new Date(2026, 10, 25, 12, 0, 0);"
        "console.log(JSON.stringify({"
        " today: dayLabel(now, now),"
        " yest: dayLabel(new Date(2026, 10, 24, 9, 0, 0), now),"
        " older: dayLabel(new Date(2026, 10, 21, 9, 0, 0), now) }))"
    )
    got = json.loads(out)
    assert got["today"] == "Today"
    assert got["yest"] == "Yesterday"
    assert got["older"] == "21 Nov"


def test_full_date_is_stable():
    out = run_js("console.log(fullDate(new Date(2026, 10, 25)))")
    assert out == "Wed 25 Nov 2026"


def test_minutes_parses_and_rejects():
    out = run_js(
        "console.log(JSON.stringify({"
        " a: minutes('07:30'), b: minutes('23:59'),"
        " bad1: minutes('24:00'), bad2: minutes('nope'), bad3: minutes('') }))"
    )
    got = json.loads(out)
    assert got["a"] == 450
    assert got["b"] == 1439
    assert got["bad1"] == -1 and got["bad2"] == -1 and got["bad3"] == -1


def test_clock_and_duration_unchanged():
    out = run_js(
        "console.log(JSON.stringify({"
        " c: clock(75), cl: clockLong(3725), d: duration(3725) }))"
    )
    got = json.loads(out)
    assert got["c"] == "1:15"
    assert got["cl"] == "1:02:05"
    assert got["d"] == "1-02-05"


def test_launcher_recent_uses_shared_day_key():
    q = (ROOT / "shani/Modules/Launcher/Launcher.qml").read_text(encoding="utf-8")
    assert 'import "../../Common/Time.js" as Time' in q
    assert "return Time.dayKey(v);" in q
    # the hand-rolled key algorithm is gone
    assert 'd.getFullYear() + "-" + String(d.getMonth()' not in q


def test_status_tone_comes_from_state_not_translated_text():
    """A translated note without the word 'saved' must still read as success.

    Tone is tracked in a boolean set at the same place the note is written;
    no surface may guess it from the note text.
    """
    for rel in (
        "shani/Modules/Settings/SettingsSecurity.qml",
        "shani/Modules/Settings/SettingsDateLanguage.qml",
        "shani/Modules/Settings/SettingsNetwork.qml",
    ):
        q = (ROOT / rel).read_text(encoding="utf-8")
        assert 'indexOf("saved")' not in q, f"{rel}: tone guessed from text"
        assert "NoteOk" in q, f"{rel}: no explicit success flag"
