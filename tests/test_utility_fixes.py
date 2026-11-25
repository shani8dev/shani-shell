"""Static checks for four utility-app fixes (pass 22).

Each fix lives in a QML singleton/card that cannot be exercised without a
running shell, so these assert the source carries the exact wiring.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_calculator_log_is_base_10_ln_is_natural():
    # the evaluator is Common/Calc.js, shared with the launcher; the service passes its angle unit
    q = read("shani/Services/Calculator.qml") + read("shani/Common/Calc.js")
    assert '"Math.log10("' in q and '"Math.log("' in q
    assert "/Math\\.log\\(/g" in q and "/Math\\.ln\\(/g" in q
    assert 'replace(/\\bln\\(/gi, "log(")' not in q


def test_ruler_scale_uses_focused_output():
    q = read("shani/Services/Ruler.qml")
    assert "Displays.outputs.find(o => o.name === Niri.focusedOutput)" in q
    assert "Displays.outputs[0]" in q  # fallback when nothing is focused


def test_sidebar_alarm_removal_confirms_with_two_taps():
    q = read("shani/Modules/ControlCenter/SidebarClock.qml")
    assert "property int confirmAlarm: -1" in q
    assert "root.confirmAlarm === index" in q
    assert 'Tr.t("Tap again to remove")' in q
    assert "if (root.confirmAlarm === index) { WorldClock.removeAlarm(index)" in q
    assert "onClicked: WorldClock.removeAlarm(index)" not in q


def test_note_widget_opens_notes():
    q = read("shani/Modules/Background/MoreWidgets.qml")
    note = q.split('key: "note"')[1].split('key: "clocks"')[0]
    assert "onOpen: Ui.openNotes()" in note
    assert "onOpen: Ui.toggleControlCenter()" not in note
    ui = read("shani/Common/Ui.qml")
    assert "function openNotes()" in ui
