"""Static checks for WindowMenu/WindowLayouts low-risk fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_window_menu_closes_when_target_window_disappears():
    qml = read("shani/Modules/WindowMenu/WindowMenu.qml")
    assert (
        "property bool targetAlive: target !== null && Niri.windows[target.id] !== undefined"
        in qml
    )
    assert (
        "onTargetAliveChanged: if (visible && !targetAlive) { target = null; Ui.windowMenu = false }"
        in qml
    )
    assert "if (e && win.targetAlive)" in qml
    assert "if (!win.targetAlive) win.target = Niri.focusedWindow;" in qml


def test_window_menu_escape_closes_app_submenu_first():
    qml = read("shani/Modules/WindowMenu/WindowMenu.qml")
    # main keyboard handler closes submenu before closing menu
    assert "if (win.openMenu >= 0) { win.openMenu = -1; win.expanded = ({}); }" in qml
    assert "else Ui.windowMenu = false;" in qml
    # Escape also works when focus is inside the opened app menu card
    assert "Keys.onEscapePressed:" in qml
    assert "keys.forceActiveFocus();" in qml


def test_window_menu_home_end_keyboard_navigation():
    qml = read("shani/Modules/WindowMenu/WindowMenu.qml")
    assert "Keys.onHomePressed: win.sel = 0" in qml
    assert "Keys.onEndPressed: win.sel = Math.max(0, win.entries.length - 1)" in qml
    assert "if (win.entries.length > 0) win.run(win.entries[win.sel].id)" in qml


def test_window_layouts_tiles_are_keyboard_accessible():
    qml = read("shani/Modules/WindowLayouts/WindowLayouts.qml")
    assert "Accessible.role: Accessible.Button" in qml
    assert "Accessible.name: modelData.name" in qml
    # tiles have KeyFocus activation matching click behaviour
    assert "KeyFocus {" in qml
    assert "onActivated: {" in qml
    assert "WindowLayouts.arrangeAll(modelData.id);" in qml
    assert "WindowLayouts.apply(modelData.id, Niri.focusedOutput);" in qml


def test_window_layouts_custom_delete_requires_confirmation():
    qml = read("shani/Modules/WindowLayouts/WindowLayouts.qml")
    assert 'property string pendingDeleteId: ""' in qml
    assert (
        'Timer { id: pendingDeleteTimer; interval: 3000; onTriggered: win.pendingDeleteId = "" }'
        in qml
    )
    assert (
        'win.pendingDeleteId === modelData.id ? "dialog-warning" : "edit-clear-all"'
        in qml
    )
    assert 'Tr.t("Click again to delete")' in qml
    assert "WindowLayouts.removeCustom(modelData.id);" in qml
    # closing palette resets transient custom-edit/delete state
    assert (
        'onVisibleChanged: if (!visible) { customEditing = false; customName = ""; pendingDeleteId = "" }'
        in qml
    )
