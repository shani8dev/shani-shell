"""Static checks for the pass-22 ruler/clock fixes: physical units + diagonal
readout in the ruler, and weekday/enabled/snooze support in WorldClock alarms.

Mirrors tests/test_clock_timers.py: the QML is compiled by the render harness,
so these assert on the shape of the source rather than launching a shell.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_ruler_dpi_calibration_adds_physical_units():
    t = read("shani/Services/Ruler.qml")
    assert "property real dpi: 0" in t  # px is the default
    assert "function setDpi(" in t and "calib.setText(" in t
    assert "2.54" in t and '" cm / "' in t and '" in"' in t
    assert "function sizeLabel()" in t and "withUnits(" in t
    p = read("shani/Modules/Ruler/RulerPanel.qml")
    assert "dpiInput" in p and "Ruler.setDpi(" in p
    assert "Set DPI for cm/in" in p  # short hint when unknown


def test_ruler_reports_diagonal_length_and_angle():
    t = read("shani/Services/Ruler.qml")
    assert "readonly property bool hasSecond:" in t
    assert "diagonalPx" in t and "Math.sqrt(" in t
    assert "lineAngle" in t and "Math.atan2(" in t
    assert "function lineLabel(" in t and "Tr.t(" in t
    p = read("shani/Modules/Ruler/RulerPanel.qml")
    assert "Ruler.lineLabel()" in p and "Ruler.straight" in p


def test_worldclock_alarms_have_weekdays_enabled_and_snooze():
    t = read("shani/Services/WorldClock.qml")
    assert "function addAlarm(time, label, days, enabled)" in t
    assert "a.enabled !== false" in t and "getDay()" in t  # old records still fire
    assert "function snooze(" in t and "function checkSnoozes(" in t
    assert "snoozeTick" in t and "interval: 30000" in t
    assert "function ring(" in t and "notify-send" in t
