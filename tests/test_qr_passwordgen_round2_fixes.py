"""Static checks for QrView/PasswordGeneratorPanel round-2 fixes.

These are source-level assertions (the style of test_utilities2.py) because the
QML panels need a running shell. Each test guards one concrete fix.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_qr_image_load_error_shows_fallback():
    q = read("shani/Modules/QrView/QrView.qml")
    # The QR image must report load failures instead of leaving a blank white box.
    assert "Image.Error" in q
    assert "QrLoadError" in q or "qrLoadError" in q or "QR code unavailable" in q


def test_qr_action_buttons_guard_missing_data():
    q = read("shani/Modules/QrView/QrView.qml")
    # Copy/Save must be guarded by the data they need, not just visibility.
    assert 'enabled: Qr.text !== ""' in q
    assert 'enabled: Qr.image !== ""' in q


def test_password_generate_reports_failure():
    q = read("shani/Modules/Passwords/PasswordGenerator.qml")
    # A failed/empty generation must not silently keep stale state.
    assert "onExited" in q
    assert "code !== 0" in q or "code != 0" in q
    assert "generateFailed" in q or 'Tr.t("Could not generate a password")' in q


def test_password_hidden_can_be_revealed():
    q = read("shani/Modules/Passwords/PasswordGenerator.qml")
    # After the 30s auto-hide, the person must be able to reveal the password again.
    assert "reveal" in q.lower()
    assert "generatedHidden = false" in q
    # There must be an explicit reveal/show control, not only the auto-hide reset.
    assert "view-hidden" in q or "view-visible" in q or "Show" in q


def test_password_words_fallback_is_reported():
    q = read("shani/Modules/Passwords/PasswordGenerator.qml")
    # Words mode falls back to characters when no usable dict exists; say so.
    assert "wordsFallback" in q
    assert "FALLBACK" in q
    assert "word list" in q.lower() or "dictionary" in q.lower()
