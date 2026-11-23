"""Static checks for FlashAlert and AssistiveTouch fixes.

These are live QML surfaces; tests pin the wiring without a running shell.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_flash_alert_has_accessible_announcement():
    q = read("shani/Modules/Flash/FlashAlert.qml")
    # a screen reader hears the alert; the name carries the notification summary
    assert "Accessible.role: Accessible.AlertMessage" in q
    assert "Accessible.name" in q
    assert "Ui.lastFlash" in q


def test_flash_alert_stops_when_disabled_mid_pulse():
    q = read("shani/Modules/Flash/FlashAlert.qml")
    # turning the setting off while flashing must not leave a stuck glow
    assert "onFlashAlertsChanged" in q
    assert "pulse.stop()" in q
    assert "glow.opacity = 0" in q


def test_assistive_touch_has_accessible_press_action():
    q = read("shani/Modules/Touch/AssistiveTouch.qml")
    # AT-SPI button must be activatable without a pointer
    assert "Accessible.onPressAction" in q
    assert "Ui.openRingAt" in q


def test_assistive_touch_gives_press_feedback():
    q = read("shani/Modules/Touch/AssistiveTouch.qml")
    # a touch press needs visible feedback
    assert "pressed" in q
    assert "scale" in q


def test_assistive_touch_clamps_position_and_uses_actual_size():
    q = read("shani/Modules/Touch/AssistiveTouch.qml")
    # stale/off-screen positions are clamped; size comes from the window, not 56/28
    assert "function clampToScreen" in q or "clampToScreen" in q
    assert "win.implicitWidth" in q
    assert "win.implicitHeight" in q
    # no hardcoded half-size in the open-ring call
    assert "Settings.data.touchX + 28" not in q
    assert "Settings.data.touchY + 28" not in q
