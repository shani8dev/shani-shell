"""Static guards for Scanner/Ruler/VideoTrimmer fixes.

Each fix is a QML-side wiring that cannot be exercised without a running shell,
so these assert the source carries the exact guard.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_scanner_clears_stale_error_on_setting_change():
    q = read("shani/Modules/Scanner/ScannerPanel.qml")
    assert 'onClicked: { win.device = modelData.id; win.error = ""; }' in q
    assert 'onClicked: { win.resolution = modelData[0]; win.error = ""; }' in q
    assert 'onClicked: { win.format = modelData[0]; win.error = ""; }' in q


def test_ruler_hint_is_translatable():
    q = read("shani/Modules/Ruler/RulerPanel.qml")
    assert (
        'text: Tr.t("Drag to measure  ·  Shift: straight line  ·  Right-click: clear  ·  Esc: close  ·  Ctrl+C: copy")'
        in q
    )


def test_ruler_dpi_input_has_accessible_name():
    q = read("shani/Modules/Ruler/RulerPanel.qml")
    assert 'Accessible.name: Tr.t("DPI calibration")' in q
    assert "Accessible.role: Accessible.EditableText" in q


def test_ruler_keyboard_clear_shortcuts():
    q = read("shani/Modules/Ruler/RulerPanel.qml")
    assert 'sequence: "Delete"' in q
    assert 'sequence: "Backspace"' in q
    # both clear, not close
    assert q.count("onActivated: Ruler.clear()") >= 2


def test_trimmer_start_end_apply_on_focus_out():
    q = read("shani/Modules/VideoTrimmer/VideoTrimmerPanel.qml")
    assert "target: startField.input" in q
    assert "target: endField.input" in q
    assert (
        "function onEditingFinished() { VideoTrimmer.setStart(parseFloat(startField.text)); }"
        in q
    )
    assert (
        "function onEditingFinished() { VideoTrimmer.setEnd(parseFloat(endField.text)); }"
        in q
    )
