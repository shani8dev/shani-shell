"""Locked notes are really encrypted with gpg, not just hidden in the UI.

Drives bridge/note-crypto.py and checks the QML wiring.
"""

import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "note-crypto.py"
QML = (ROOT / "shani/Services/QuickNotes.qml").read_text()


def call(args, payload, tmp_path):
    return subprocess.run(
        ["python3", str(BRIDGE)] + args,
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env={**os.environ, "XDG_RUNTIME_DIR": str(tmp_path)},
    )


@pytest.fixture
def gpg():
    if (
        not subprocess.run(
            ["sh", "-c", "command -v gpg"], capture_output=True
        ).returncode
        == 0
    ):
        pytest.skip("gpg not installed")


def test_probe_reports_gpg():
    r = subprocess.run(
        ["python3", str(BRIDGE), "probe"], capture_output=True, text=True
    )
    assert r.returncode == 0
    assert "gpg" in json.loads(r.stdout)


def test_roundtrip_and_wrong_passphrase(tmp_path, gpg):
    p = tmp_path / "secret.locked.md.gpg"
    r = call(
        ["encrypt", str(p)], {"passphrase": "right", "text": "my diary body"}, tmp_path
    )
    assert r.returncode == 0, r.stderr
    assert b"my diary body" not in p.read_bytes()
    ok = call(["decrypt", str(p)], {"passphrase": "right"}, tmp_path)
    assert ok.returncode == 0
    assert json.loads(ok.stdout)["text"] == "my diary body"
    bad = call(["decrypt", str(p)], {"passphrase": "wrong"}, tmp_path)
    assert bad.returncode != 0
    assert "text" not in json.loads(bad.stdout)


def test_passphrase_not_in_argv(tmp_path, gpg):
    src = BRIDGE.read_text()
    assert "--passphrase-fd" in src
    assert "--passphrase=" not in src and '"--passphrase"' not in src
    assert "input=(passphrase" in src   # gpg's stdin, never argv


def test_qml_uses_bridge_not_sha256_sidecar():
    assert "note-crypto.py" in QML
    assert "sha256sum" not in QML
    assert "runLock" not in QML
    assert "stdinEnabled" in QML
