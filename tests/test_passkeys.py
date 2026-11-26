"""Passkey references are honest, keyring-backed, and never fake credentials."""

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "passwords.py"
src = BRIDGE.read_text()


def test_no_plaintext_registry_on_disk():
    assert "shani-passkeys.json" not in src
    assert "PASSKEY_ATTRS" in src
    assert "_passkeys_save" in src and "set_secret" in src


def test_random_id_is_not_a_credential_id():
    # the local id is a reference; cred_id only comes from a real fido2 tool
    assert '"id": secrets.token_hex(16)' in src
    assert 'source if source in ("browser", "shell")' in src
    assert "fido2_cred" in src and "fido2_assert" in src


def test_the_passkeys_tab_shows_what_this_machine_supports():
    qml = (ROOT / "shani/Modules/Passwords/PasswordsWindow.qml").read_text()
    assert "passkey-capabilities" in qml and "id: capsLister" in qml
    assert "capsLister.running = true" in qml
    assert 'Tr.t("What this computer supports")' in qml
    for word in (
        "Keyring",
        "Security-key device",
        "Make a key here",
        "Sign a challenge here",
    ):
        assert f'Tr.t("{word}")' in qml
    assert 'Tr.t("Available")' in qml and 'Tr.t("Not available")' in qml


def test_capabilities_probe_reports_missing_tools():
    # with env pointing to nonexistent binaries, no capability is claimed
    env = {
        **os.environ,
        "SHANI_FIDO2_CRED": "/nonexistent/cred",
        "SHANI_FIDO2_ASSERT": "/nonexistent/assert",
        "SHANI_FIDO2_TOKEN": "/nonexistent/token",
    }
    r = subprocess.run(
        ["python3", str(BRIDGE), "passkey-capabilities"],
        capture_output=True,
        text=True,
        env=env,
    )
    assert r.returncode == 0, r.stderr
    caps = json.loads(r.stdout)
    assert caps["fido2_cred"] is False
    assert caps["fido2_assert"] is False
