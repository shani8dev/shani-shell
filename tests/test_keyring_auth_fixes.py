"""Pass-19 keyring/authenticator fixes: static wiring for the QML changes and a
unit check that a mistyped OTP setup key is refused before it is stored."""

import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
WINDOW = ROOT / "shani" / "Modules" / "Authenticator" / "AuthenticatorWindow.qml"
OTP = ROOT / "bridge" / "otp.py"


def test_totp_countdown_is_a_draining_ring():
    src = WINDOW.read_text()
    assert "StatusRing {" in src
    assert "value: row.secondsLeft / row.modelData.period" in src
    assert "border.width: 3" not in src  # the old fixed circle is gone


def test_locked_key_shows_a_note_that_times_out():
    src = WINDOW.read_text()
    assert 'Tr.t("Unlock the key in the terminal…")' in src
    assert "win.note = win.unlockNote;" in src
    assert "unlockTimer.restart();" in src
    assert "id: unlockTimer" in src
    assert "win.note === win.unlockNote" in src


def test_countdown_name_is_spoken_with_context():
    src = WINDOW.read_text()
    assert 'Tr.t("%1 seconds left").arg(row.secondsLeft)' in src
    assert "Accessible.name:" in src


def test_otp_rejects_bad_secrets_on_add():
    spec = importlib.util.spec_from_file_location("otp", OTP)
    otp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(otp)

    assert otp.validate_secret("jbsw y3dp ehpk 3pxp") == "JBSWY3DPEHPK3PXP"
    for bad in ("ABC123", "AB", "!!!!", ""):
        with pytest.raises(ValueError):
            otp.validate_secret(bad)

    def add(secret):
        return otp.parse(
            json.dumps({"issuer": "X", "account": "a@b.c", "secret": secret})
        )

    with pytest.raises(ValueError):
        add("AB")
    assert add("JBSWY3DPEHPK3PXP")["secret"] == "JBSWY3DPEHPK3PXP"
