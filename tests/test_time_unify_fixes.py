"""Time.js unification: helper behaviour + one static check per migrated site.

Run: python3 -m pytest tests/test_time_unify_fixes.py -q
"""

import os
import re
import subprocess
import textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIME_JS = os.path.join(ROOT, "shani", "Common", "Time.js")

OWNED = [
    "shani/Modules/Calendar/CalendarPanel.qml",
    "shani/Services/PlayQueue.qml",
    "shani/Services/WorldClock.qml",
    "shani/Services/Link.qml",
    "shani/Services/VoiceRecorder.qml",
    "shani/Services/Camera.qml",
    "shani/Services/CallRecorder.qml",
    "shani/Services/Recorder.qml",
]


def _read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return fh.read()


def _load_helpers():
    """Execute Time.js in node and hand back its functions as JSON assertions."""
    src = _read("shani/Common/Time.js").replace(".pragma library", "")
    exports = (
        "Object.assign(exports,{clock,clockLong,duration,clockPadded,"
        "hhmmss,stopwatch,fileStamp,dayKey,dayLabel,fullDate,minutes});"
    )
    script = textwrap.dedent(
        f"""
        const fs = require("fs");
        let src = {src!r};
        new Function("exports", src + {exports!r})(
            (global.__t = {{}})
        );
        const t = global.__t;
        const out = [];
        const eq = (name, got, want) => out.push([name, got === want, got, want]);
        eq("clockPadded 9:05", t.clockPadded("9:05"), "09:05");
        eq("clockPadded 13:05", t.clockPadded("13:05"), "13:05");
        eq("hhmmss 0", t.hhmmss(0), "00:00:00");
        eq("hhmmss 3661", t.hhmmss(3661), "01:01:01");
        eq("hhmmss 100h", t.hhmmss(360000), "100:00:00");
        eq("stopwatch 0", t.stopwatch(0), "00:00.00");
        eq("stopwatch 61230", t.stopwatch(61230), "01:01.23");
        eq("stopwatch 1h", t.stopwatch(3661230), "1:01:01.23");
        eq("clockLong 95", t.clockLong(95), "1:35");
        eq("clockLong 3661", t.clockLong(3661), "1:01:01");
        eq("clock 95", t.clock(95), "1:35");
        eq("fileStamp", t.fileStamp(new Date(Date.UTC(2026,10,25,13,4,5))),
           "2026-11-25-13-04-05");
        eq("dayKey", t.dayKey(new Date(2026,10,5)), "2026-11-05");
        console.log(JSON.stringify(out));
        """
    )
    res = subprocess.run(
        ["node", "-e", script], capture_output=True, text=True, check=True
    )
    import json

    return json.loads(res.stdout)


def test_helpers_match_legacy_output():
    for name, ok, got, want in _load_helpers():
        assert ok, f"{name}: got {got!r}, want {want!r}"


# --- static checks: one per migrated site ---------------------------------


def test_calendarpanel_uses_time():
    s = _read("shani/Modules/Calendar/CalendarPanel.qml")
    assert 'import "../../Common/Time.js" as Time' in s
    assert "Time.clockPadded(t[1]" in s
    assert "Time.dayKey(new Date(ms))" in s
    assert "padStart" not in s
    assert '("0" + (d.getMonth()' not in s


def test_playqueue_uses_time():
    s = _read("shani/Services/PlayQueue.qml")
    assert 'import "../Common/Time.js" as Time' in s
    assert "Time.clockLong(Math.max(0, s))" in s
    assert "padStart" not in s


def test_worldclock_uses_time():
    s = _read("shani/Services/WorldClock.qml")
    assert 'import "../Common/Time.js" as Time' in s
    assert "Time.clockPadded(t)" in s
    assert "Time.stopwatch(ms)" in s
    assert "padStart" not in s


def test_link_uses_time():
    s = _read("shani/Services/Link.qml")
    assert 'import "../Common/Time.js" as Time' in s
    assert "Time.clock(Math.max(0, Math.floor(secs || 0)))" in s
    assert "padStart" not in s


def test_voicerecorder_uses_time():
    s = _read("shani/Services/VoiceRecorder.qml")
    assert 'import "../Common/Time.js" as Time' in s
    assert "Time.hhmmss(seconds)" in s
    assert "padStart" not in s


def test_camera_uses_time():
    s = _read("shani/Services/Camera.qml")
    assert 'import "../Common/Time.js" as Time' in s
    assert "Time.clock(seconds)" in s
    assert "padStart" not in s


def test_callrecorder_uses_time():
    s = _read("shani/Services/CallRecorder.qml")
    assert 'import "../Common/Time.js" as Time' in s
    assert "Time.clock(seconds)" in s
    assert "Time.fileStamp()" in s
    assert "padStart" not in s
    assert "toISOString().slice" not in s


def test_recorder_uses_time():
    s = _read("shani/Services/Recorder.qml")
    assert 'import "../Common/Time.js" as Time' in s
    assert "Time.clock(seconds)" in s
    assert "Time.fileStamp()" in s
    assert "padStart" not in s
    assert "toISOString().slice" not in s
