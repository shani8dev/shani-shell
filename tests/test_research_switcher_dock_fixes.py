"""Static checks for the lowest-risk Switcher/Dock gaps in the competitive review.

Both modules are layer-shell surfaces driven by niri, so these tests assert the
source carries the wiring rather than driving a live QML session.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
switcher = (ROOT / "shani/Modules/Switcher/Switcher.qml").read_text(encoding="utf-8")
dock = (ROOT / "shani/Modules/Dock/Dock.qml").read_text(encoding="utf-8")


def section(src, start, stop):
    """The text between two landmarks, so a change cannot hide elsewhere."""
    return src.split(start, 1)[1].split(stop, 1)[0]


def test_switcher_marks_the_selected_tile_as_accessible_focused():
    """Orca must be able to say which window Enter will focus."""
    tile = section(switcher, "Accessible.role: Accessible.Button", "KeyFocus {")
    assert "Accessible.focused: index === win.sel" in tile
    # no undefined typed roles crept in
    assert "Accessible.Menu" not in switcher
    assert "Accessible.Image" not in switcher


def test_switcher_tile_title_comes_from_the_live_window():
    """A window renamed while open must not keep its MRU-snapshot title."""
    titles = section(
        switcher, "readonly property string title: isGroup", "width: Theme.px(120)"
    )
    assert "(Niri.windows[cell.modelData.id] || cell.modelData).title" in titles
    assert ": (cell.modelData.title || cell.appId)" not in titles


def test_switcher_wheel_cycles_the_tiles():
    """A mouse user can cycle tiles without the keyboard."""
    area = section(switcher, "id: cellArea", "Accessible.role: Accessible.Button")
    assert "onWheel: w => win.step(w.angleDelta.y < 0 ? 1 : -1)" in area


def test_dock_reports_windows_hidden_behind_the_pips():
    """Three pips are drawn, but an app with more windows must say how many."""
    ind = section(dock, "// Latte-style indicators", "// files dragged onto an app")
    assert "model: Math.min(3, cell.modelData.windows.length)" in ind
    assert "visible: cell.modelData.windows.length > 3" in ind
    assert 'text: "+" + (cell.modelData.windows.length - 3)' in ind


def test_dock_home_and_end_move_keyboard_focus_to_the_ends():
    """The dock's keyboard surface handled Escape only; Home/End now jump."""
    keys = section(dock, "focus: Ui.dockFocus", "id: controls")
    assert "Keys.onPressed: e =>" in keys
    assert "Qt.Key_Escape" in keys
    assert "win.setMenu(-1)" in keys and "Ui.dockFocus = false" in keys
    assert "Qt.Key_Home" in keys and "Ui.focusFirst(row)" in keys
    assert "Qt.Key_End" in keys and "row.nextItemInFocusChain(false)" in keys
    assert "last.forceActiveFocus(Qt.TabFocusReason)" in keys
    assert "e.accepted = true" in keys
