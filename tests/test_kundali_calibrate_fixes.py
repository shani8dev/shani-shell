"""Static guards for five small fixes in the Kundali and Calibrate windows.

Both are layer-shell/QML surfaces with no bridge call to assert on for these
behaviours: a chart that outlives its inputs, an error that looks like a chart,
a result with no copy path, a step count frozen at four, and a Cancel button a
keyboard or a screen reader cannot press. Each is checked in the source.

Five fixes, one test each.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KUNDALI = ROOT / "shani" / "Modules" / "Kundali" / "KundaliPanel.qml"
CALIBRATE = ROOT / "shani" / "Modules" / "Calibrate" / "CalibrateOverlay.qml"


def kundali():
    return KUNDALI.read_text(encoding="utf-8")


def calibrate():
    return CALIBRATE.read_text(encoding="utf-8")


def body_of(text, signature):
    m = re.search(re.escape(signature) + r"\s*\{([^{}]*)\}", text)
    assert m, f"{signature} is missing"
    return m.group(1)


def test_editing_an_input_drops_the_chart_that_input_made():
    """The chart belongs to the inputs that made it (the window redesign kept
    this: every date, time, place and mode change clears what was shown)."""
    t = kundali()
    clear = body_of(t, "function clearResult()")
    for line in ("win.chart = null", "win.day = null", 'win.error = ""', "win.copied = false", "win.chartCopied = false"):
        assert line in clear, line
    assert "win.clearResult()" in body_of(t, "function calculate()"), "a new calculation does not reset the card"
    assert 'onPicked: date => { win.dateInput = date; win.clearResult(); }' in t
    assert 'onPicked: time => { win.timeInput = time; win.clearResult(); }' in t
    assert 'win.mode = index === 1 ? "panchang" : "kundali"; win.clearResult();' in t
    assert "win.clearResult();" in t[t.index("function pickPlace(r)"):t.index("function useThisComputer()")]


def test_the_result_can_be_copied_without_selecting_it_by_mouse():
    t = kundali()
    assert 'Tr.t("Copy chart")' in t and 'Tr.t("Copy result")' in t, "no copy button"
    assert "wl-copy" in t and "(win.chart || {}).text" in t, "copy does not carry the chart"
    assert 'visible: win.mode === "kundali" && win.chart !== null && win.error === ""' in t
    assert 'Accessible.name: win.chartCopied ? Tr.t("Copied") : Tr.t("Copy chart")' in t


def test_an_error_is_not_styled_or_announced_as_a_chart():
    """An error is a banner of its own (tone error), never drawn in the
    chart's place; a failed or unreadable answer says so."""
    t = kundali()
    assert 'property string error: ""' in t
    assert 'tone: "error"' in t and 'title: Tr.t("Could not compute")' in t
    assert "if (d.error) { win.error = d.error; return; }" in t
    assert 'win.error = Tr.t("The result could not be read")' in t
    assert "is the Kundali helper installed?" in t


def test_the_step_count_comes_from_the_service_not_a_literal_four():
    """A fifth target must be announced as '1 of 5', not '1 of 4'."""
    t = calibrate()
    assert "of 4" not in t, "step total is hard-coded"
    assert "of %2" in t, "no placeholder for the total"
    line = next(l for l in t.splitlines() if "of %2" in l)
    assert ".arg(Calibrate.step + 1).arg(Calibrate.targets.length)" in line, line
    # the instruction itself, not just the ring, is exposed to assistive tech
    assert "Accessible.role: Accessible.StaticText" in t
    assert "Accessible.name: text" in t


def test_cancel_can_be_pressed_by_keyboard_and_assistive_tech():
    """TapHandler alone strands a keyboard or screen-reader user in a bad calibration."""
    t = calibrate()
    assert 'Accessible.onPressAction: Calibrate.cancel("cancelled")' in t
    assert "activeFocusOnTab: true" in t
    assert 'Keys.onReturnPressed: Calibrate.cancel("cancelled")' in t
    assert 'Keys.onSpacePressed: Calibrate.cancel("cancelled")' in t
