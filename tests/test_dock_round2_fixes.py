"""Static checks for dock gaps found in round 2.

The dock is a per-screen layer-shell surface driven by niri and desktop entries,
so these tests assert the source carries the wiring rather than driving QML.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
dock = (ROOT / "shani/Modules/Dock/Dock.qml").read_text(encoding="utf-8")


def test_menu_tracks_app_identity_across_reorder():
    assert "property string menuAppId" in dock
    assert "function setMenu(index, anchor)" in dock
    assert "win.menuAppId = win.items[index].id" in dock
    # reorder keeps menu on the same app, or closes when app is gone
    assert "const i = menuAppId ? items.findIndex(x => x.id === menuAppId) : -1" in dock
    assert "if (i >= 0)" in dock
    assert "menuFor = i" in dock


def test_menu_container_is_accessible_popup_menu():
    block = dock.split("id: menuBox", 1)[1].split("Column {", 1)[0]
    assert "Accessible.role: Accessible.Pane" in block
    assert "Accessible.name:" in block


def test_menu_close_restores_focus_to_tile():
    assert "property Item menuAnchor" in dock
    assert "a.forceActiveFocus(Qt.TabFocusReason)" in dock
    # menu item activations close menu and restore focus
    assert "win.setMenu(-1); tileFocus.forceActiveFocus(Qt.TabFocusReason);" in dock
    assert (
        "onMenu: { win.setMenu(cell.index, tileFocus); Ui.focusFirst(menuBox); }"
        in dock
    )


def test_activate_cycles_via_focusWin():
    act = dock.split("function activate(it) {", 1)[1].split("function movePin", 1)[0]
    assert "const target = Niri.windows[targetId];" in act
    assert "Niri.focusWin(target);" in act
    assert 'Niri.action("focus-window", "--id", targetId);' in act
    assert (
        'Niri.action("focus-window", "--id", ids[cur < 0 ? 0 : (cur + 1) % ids.length]);'
        not in act
    )


def test_indicator_highlights_only_focused_pip():
    ind = dock.split("// Latte-style indicators", 1)[1].split(
        "// files dragged onto an app", 1
    )[0]
    assert "readonly property bool activePip: cell.focused && index === 0" in ind
    assert "width: activePip ? 14 : 5" in ind
    assert "color: activePip ? Theme.accent : Theme.dim" in ind
    assert "width: cell.focused ? 14 : 5" not in ind
    assert "color: cell.focused ? Theme.accent : Theme.dim" not in ind
