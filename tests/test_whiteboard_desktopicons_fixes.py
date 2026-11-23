"""Static checks for Whiteboard and DesktopIcons fixes.

Each fix is in QML modules that cannot be exercised without a running shell,
so these assert the source carries the exact wiring.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_whiteboard_mutations_guarded_during_save():
    q = read("shani/Modules/Whiteboard/Whiteboard.qml")
    # Mutating actions must no-op while a PDF export is iterating pages.
    for fn in [
        "function undo()",
        "function clearPage()",
        "function newPage()",
        "function go(d)",
        "function addStroke(points)",
    ]:
        block = q.split(fn, 1)[1].split("function ", 1)[0]
        assert "if (saving >= 0) return;" in block, fn


def test_whiteboard_thickness_clears_eraser():
    q = read("shani/Modules/Whiteboard/Whiteboard.qml")
    assert (
        "onClicked: { win.thickness = Theme.px(parent.modelData); win.erasing = false; }"
        in q
    )


def test_whiteboard_clear_page_two_tap_confirm():
    q = read("shani/Modules/Whiteboard/Whiteboard.qml")
    assert "property bool clearArmed: false" in q
    assert "win.clearArmed = false" in q  # disarmed by timer/actions
    assert 'Tr.t("Tap clear again to erase this page")' in q
    assert "if (!clearArmed && strokes().length > 0)" in q


def test_desktop_icons_clear_stale_selection_and_state():
    q = read("shani/Modules/Background/DesktopIcons.qml")
    assert "onEntriesChanged:" in q
    assert 'if (selected !== "" && !keys[selected]) selected = "";' in q
    assert 'if (!found) renaming = "";' in q
    assert "if (!found) menu.visible = false;" in q
    assert (
        "if (!keys[stack.entry.key]) { stack.visible = false; stack.entry = null; }"
        in q
    )


def test_desktop_icons_keyboard_selection_open_rename_delete():
    q = read("shani/Modules/Background/DesktopIcons.qml")
    assert (
        'WlrLayershell.keyboardFocus: (renaming !== "" || selected !== "") ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None'
        in q
    )
    assert "Keys.onPressed: e => {" in q
    assert "Qt.Key_Return" in q and "win.activate(entry)" in q
    assert "Qt.Key_F2" in q and "win.renaming = entry.path" in q
    assert "Qt.Key_Delete" in q and '["gio", "trash", entry.path]' in q
    assert 'Keys.onEscapePressed: win.renaming = ""' in q
