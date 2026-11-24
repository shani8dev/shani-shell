"""Static checks for the competitive calculator/Clocks gaps closed in this pass.

Competitors compared: GNOME Calculator, KDE KCalc, macOS Calculator (angle
modes, paste input, copy expression) and GNOME Clocks/World Clock (alarm
on/off, timer restart). Every check reads the shipped QML — no runtime.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CALC = (ROOT / "shani/Modules/Calculator/Calculator.qml").read_text(encoding="utf-8")
CLOCKS = (ROOT / "shani/Modules/Clocks/ClocksWindow.qml").read_text(encoding="utf-8")


def test_calculator_has_angle_unit_switch():
    # GNOME Calculator / KCalc expose DEG/RAD/GRAD next to the trig keys; the
    # service already honours angleUnit, only the surface lacked the switch.
    assert 'visible: win.tab === "scientific"' in CALC
    angle = CALC[CALC.index('model: ["deg", "rad", "grad"]') :]
    angle = angle[: angle.index("// ---- scientific keys")]
    assert "selected: Services.Calculator.angleUnit === modelData" in angle
    assert "Services.Calculator.setAngleUnit(modelData)" in angle


def test_calculator_supports_paste_input():
    # macOS Calculator / KCalc accept a pasted expression; route each char
    # through press() so the service whitelist still applies.
    paste = CALC[CALC.index("if (e.key === Qt.Key_V") :]
    paste = paste[: paste.index("// typing goes to the calculator")]
    assert "(e.modifiers & Qt.ControlModifier)" in paste
    assert "Quickshell.clipboardText" in paste
    assert "Services.Calculator.press(ch)" in paste


def test_calculator_history_rows_copy_expression():
    # GNOME Calculator lets you copy a history entry, not just the current
    # result; copy "expr = value" to the clipboard.
    hist = CALC[CALC.index("model: Services.Calculator.history") :]
    hist = hist[: hist.index("Text {\n                Layout.fillWidth: true")]
    assert 'modelData.expr + " = " + modelData.value' in hist
    assert "Quickshell.clipboardText = modelData.expr" in hist
    assert 'Tr.t("Copied expression")' in hist


def test_clocks_alarms_can_be_toggled():
    # GNOME Clocks keeps an alarm and switches it on/off; ours only offered
    # remove, which lost the label and repeat days.
    assert "function toggleAlarm(index)" in CLOCKS
    fn = CLOCKS[CLOCKS.index("function toggleAlarm(index)") :]
    fn = fn[: fn.index("Item {")]
    # toggling now edits in place (preserves group + position); the old
    # remove+addAlarm path duplicated alarms and lost their group
    assert "WorldClock.updateAlarm(index, item.time, item.label" in fn
    assert "item.enabled === false" in fn
    assert "array.isarray(item.days)" in fn.lower()
    assert "onClicked: win.toggleAlarm(index)" in CLOCKS
    assert 'Tr.t("Repeats")' in CLOCKS
    assert 'Tr.t("Off")' in CLOCKS


def test_clocks_timer_has_restart():
    # GNOME Clocks / macOS let you restart the last timer in one tap.
    assert "property int lastTimerMinutes: 0" in CLOCKS
    assert "win.lastTimerMinutes = modelData; FocusTimer.start(modelData)" in CLOCKS
    restart = CLOCKS[CLOCKS.index('Tr.t("Restart %1 min")') :]
    assert "FocusTimer.start(win.lastTimerMinutes)" in restart
