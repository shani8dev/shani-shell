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
    # Qt 6 has no Keys.onHomePressed/onEndPressed; navigation lives in onPressed
    assert "Keys.onPressed:" in qml
    assert "event.key === Qt.Key_Home" in qml
    assert "event.key === Qt.Key_End" in qml
    assert "win.sel = 0" in qml
    assert "win.sel = Math.max(0, win.entries.length - 1)" in qml
    assert "win.run(win.entries[win.sel].id)" in qml


def test_window_layouts_tiles_are_keyboard_accessible():
    qml = read("shani/Modules/WindowLayouts/WindowLayouts.qml")
    assert "Accessible.role: Accessible.Button" in qml
    assert "Accessible.name: modelData.name" in qml
    # tiles have KeyFocus activation matching click behaviour
    assert "KeyFocus {" in qml
    assert "onActivated: win.applyLayout(modelData.id)" in qml
    assert "WindowLayouts.arrangeAll(id);" in qml
    assert "WindowLayouts.apply(id, Niri.focusedOutput);" in qml


def test_window_layouts_custom_delete_requires_confirmation():
    qml = read("shani/Modules/WindowLayouts/WindowLayouts.qml")
    assert "deleteLayoutConfirm" in qml
    assert "interval: 3000" in qml  # ConfirmButton owns the timer now
    assert 'deleteLayoutConfirm.armed ? "danger" : "plain"' in qml
    assert 'Tr.t("Click again to delete")' in qml
    assert "onConfirmed: WindowLayouts.removeCustom(modelData.id)" in qml
    # closing palette resets transient custom-edit/delete state
    assert (
        'deleteLayoutConfirm.disarm()'
        in qml
    )
