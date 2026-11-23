"""Static checks for dock gaps found by reading Dock.qml, not listed in
docs/GAPS.md or docs/GAPS-RESEARCH.md.

The dock is a per-screen layer-shell surface driven by niri and desktop entries,
so these tests assert the source carries the wiring rather than driving QML.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
dock = (ROOT / "shani/Modules/Dock/Dock.qml").read_text(encoding="utf-8")


def test_move_menu_uses_pinned_list_index_not_visible_row_index():
    # cell.index counts the visible items; a skipped pin (uninstalled app or
    # AppFilter) shifts it, so Move left/right must gate on the real list index
    assert "readonly property int pinIndex: Settings.data.dockPinned.indexOf(" in dock
    assert "cell.pinIndex > 0" in dock
    assert "cell.pinIndex < Settings.data.dockPinned.length - 1" in dock
    assert "cell.index > 0" not in dock
    assert "cell.index < Settings.data.dockPinned.length - 1" not in dock


def test_cell_accessible_name_speaks_windows_and_pin_state():
    name = dock.split("Accessible.name: (modelData.entry", 1)[1].split(
        "Accessible.onPressAction", 1
    )[0]
    assert 'modelData.windows.length === 1 ? Tr.t("1 window")' in name
    assert 'Tr.t("%1 windows", modelData.windows.length)' in name
    assert 'modelData.pinned ? ", " + Tr.t("Pinned")' in name


def test_cell_tooltip_reports_running_windows_and_pin_state():
    tip = dock.split("visible: area.containsMouse && win.menuFor < 0", 1)[1]
    assert (
        "text: (cell.modelData.entry ? cell.modelData.entry.name : cell.modelData.id)"
        in tip
    )
    assert 'cell.modelData.windows.length === 1 ? Tr.t("1 window")' in tip
    assert 'Tr.t("%1 windows", cell.modelData.windows.length)' in tip
    assert 'cell.modelData.pinned ? " · " + Tr.t("Pinned")' in tip


def test_trash_accessible_name_reports_count_and_arming():
    trash = dock.split("id: trashTile", 1)[1].split("function requestEmpty()", 1)[0]
    aname = trash.split('Accessible.name: Tr.t("Trash")', 1)[1].split("on:", 1)[0]
    assert 'count === 1 ? Tr.t("1 item")' in aname
    assert 'Tr.t("%1 items").arg(count)' in aname
    assert 'arming ? ", " + Tr.t("Right-click again to empty the trash")' in aname


def test_stale_menu_index_is_dropped_when_items_shrink():
    # an uninstalled app drops its cell while its menu is open; the dock must
    # not stay shown behind a full-surface input mask forever
    assert "onItemsChanged: if (menuFor >= items.length) menuFor = -1" in dock
