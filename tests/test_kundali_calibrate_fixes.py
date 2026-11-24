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
    """A result computed for 1990-01-01 must not sit under a freshly typed date."""
    t = kundali()
    clear = body_of(t, "function clearResult()")
    assert 'win.result = ""' in clear
    assert "win.error = false" in clear
    assert "win.copied = false" in clear
    calc = body_of(t, "function calculate()")
    assert "win.clearResult()" in calc, "a new calculation does not reset the card"
    # every editable field, and both modes, must invalidate the old result
    for prop in ("dateInput", "timeInput", "latInput", "lonInput"):
        line = next(
            l for l in t.splitlines() if f"onTextChanged: {{ win.{prop} = text;" in l
        )
        assert "win.clearResult()" in line, line
    assert t.count("win.clearResult() }") >= 4
    assert 'onClicked: { win.mode = "panchang"; win.clearResult() }' in t
    assert 'onClicked: { win.mode = "kundali"; win.clearResult() }' in t


def test_the_result_can_be_copied_without_selecting_it_by_mouse():
    """A read-only TextEdit is not a copy affordance for keyboard/AT users."""
    t = kundali()
    assert 'Tr.t("Copy result")' in t, "no copy button"
    assert "wl-copy" in t and "win.result" in t, "copy does not carry the chart"
    line = next(l for l in t.splitlines() if "enabled: win.result" in l)
    assert 'win.result !== "" && !win.error' in line, line
    assert 'win.copied ? Tr.t("Copied") : Tr.t("Copy result")' in t
    assert 'Accessible.name: win.copied ? Tr.t("Copied")' in t


def test_an_error_is_not_styled_or_announced_as_a_chart():
    """'The calculation failed' must read as an error, not as a normal result."""
    t = kundali()
    assert "property bool error: false" in t
    assert "color: win.error ? Theme.danger : Theme.text" in t
    assert 'Accessible.name: win.error ? Tr.t("Calculation error")' in t
    # all three failure paths set the flag; a successful parse clears it
    assert "if (code !== 0) {" in t and t.count("win.error = true") == 3
    assert "const data = JSON.parse(text);" in t
    assert "win.error = false;\n                    if (data.error)" in t
    assert 'win.result = Tr.t("The result could not be read")' in t


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
