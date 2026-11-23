"""Static checks for PinCapture and ScreenSaver Cover fixes.

QML cannot run under pytest here, so each test pins the source binding that
carries one fix: pin Esc dismiss needs keyboard focus, missing pin images get a
fallback, pin image decode is bounded, preview shows a dismiss hint, and photo
screensaver guards/resets stale state.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_pin_capture_esc_dismiss_gets_keyboard_focus():
    q = read("shani/Modules/Screenshots/PinCapture.qml")
    assert "WlrKeyboardFocus.OnDemand" in q
    assert "WlrKeyboardFocus.None" not in q
    assert "forceActiveFocus()" in q
    assert "Keys.onEscapePressed" in q


def test_pin_capture_missing_image_shows_fallback():
    q = read("shani/Modules/Screenshots/PinCapture.qml")
    assert "Image.Error" in q
    assert "Screenshot not found" in q
    # broken image should not leave an empty frame with no explanation
    assert "shot.status === Image.Error" in q or "shot.status == Image.Error" in q


def test_pin_capture_limits_decoded_image_size():
    q = read("shani/Modules/Screenshots/PinCapture.qml")
    assert "sourceSize.width" in q
    assert "sourceSize.height" in q


def test_screensaver_preview_shows_dismiss_hint():
    q = read("shani/Modules/ScreenSaver/Cover.qml")
    assert "ScreenSaver.preview" in q
    assert "Press any key or click to dismiss" in q


def test_screensaver_photo_mode_guards_and_resets_state():
    q = read("shani/Modules/ScreenSaver/Cover.qml")
    assert "pics.count <= 0" in q
    # re-show should not flash a stale photo from the previous activation
    assert 'a.source = ""' in q
    assert 'b.source = ""' in q
    assert "stage.onA = true" in q
