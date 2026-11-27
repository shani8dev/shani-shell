"""Regressions in the QML wiring which pure profile/gesture rules cannot detect."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_lock_cards_use_their_surface_width_not_the_scope():
    source = (ROOT / "shani/Modules/Lock/LockScreen.qml").read_text()
    assert "root.width" not in source  # root is a Scope, not a window
    assert source.count("Math.min(Theme.px(380), surface.width - 40)") == 2


def test_phone_policy_is_not_rewritten_when_monitor_focus_changes():
    source = (ROOT / "shani/Services/WindowRules.qml").read_text()
    assert "FF.phoneOnly(FormFactor.screens)" in source
    assert "FormFactor.focused" not in source


def test_swipe_uses_movement_and_handles_cancellation():
    source = (ROOT / "shani/Modules/EdgeStrips/EdgeStrips.qml").read_text()
    assert "G.moveSwipe(" in source and "G.finishSwipe(" in source
    assert "onCanceled: swipe = null" in source
    assert "Date.now() - down" not in source


def test_trash_menu_and_clicks_keep_their_original_actions():
    source = (ROOT / "shani/Modules/Dock/Dock.qml").read_text()
    assert "onMenuRequested: requestEmpty()" in source
    assert "Hold.swallowed(held) || e.button === Qt.RightButton" in source
    assert "trashTile.activated();" in source
    assert 'Quickshell.execDetached(["gio", "trash", "--empty"]);' in source


def test_touch_controls_share_the_target_minimum():
    for name in ("Button", "IconButton", "Choice", "TextField", "ListRow"):
        source = (ROOT / f"shani/Common/{name}.qml").read_text()
        assert "Math.max(" in source and "Theme.touchTarget" in source, name
    source = (ROOT / "shani/Common/Theme.qml").read_text()
    assert '["phone", "tablet", "handheld", "board"]' in source


def test_compact_toolbar_keeps_actions_and_keyboard_scrolling():
    source = (ROOT / "shani/Common/AppWindow.qml").read_text()
    strip = (ROOT / "shani/Common/ActionStrip.qml").read_text()
    assert "Flickable.HorizontalFlick" in strip
    assert "default property alias content: body.data" in source
    assert "property alias tools: toolStrip.actions" in source
    source = (ROOT / "shani/Common/KeyFocus.qml").read_text()
    assert "p.contentX =" in source
    assert "p.contentY =" in source
