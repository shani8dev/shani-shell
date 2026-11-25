"""Static checks for the privacy fixes: notification content, lock concealment,
keyring audit opt-in, and generated-password masking."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(p):
    return (ROOT / p).read_text()


def test_notif_summary_needs_consent_and_drops_bodies_and_codes():
    s = read("shani/Services/Notifs.qml")
    assert "summarizeConsent" in s and "summarizePending" in s
    assert r"\b\d{4,8}\b" in s  # 4-8 digit codes stripped
    assert "_safeSummary" in s and "Chronoa.ask(" in s
    body = s.split("function summarize()")[1].split("function clearAll()")[0]
    assert "n.body" not in body  # message bodies are never sent


def test_revealed_secret_cleared_on_screen_lock():
    s = read("shani/Modules/Passwords/PasswordsWindow.qml")
    assert "target: Lock" in s
    assert "function onLockedChanged()" in s
    assert "if (Lock.locked)" in s
    assert 'win.shownSecret = ""; hideTimer.stop();' in s


def test_keyring_audit_is_opt_in_with_explicit_button():
    s = read("shani/Modules/Passwords/PasswordsWindow.qml")
    assert "Settings.data.passwordAuditEnabled === true" in s
    assert 'Tr.t("Run security check")' in s
    assert "runAudit();" in s


def test_generated_password_is_masked_after_30s():
    s = read("shani/Modules/Passwords/PasswordGenerator.qml")
    assert "generatedHidden" in s
    assert "Timer { id: hideTimer; interval: 30000" in s
    assert "hideTimer.restart()" in s
    assert "••••••••" in s
