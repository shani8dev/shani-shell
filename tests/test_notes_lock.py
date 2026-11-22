"""The Notes "Lock…" button calls a subcommand the bridge must actually have."""

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "note-crypto.py"
SERVICE = ROOT / "shani/Services/QuickNotes.qml"


def test_bridge_implements_lock():
    assert 'cmd == "lock"' in BRIDGE.read_text()


def test_service_calls_lock_with_both_paths():
    s = SERVICE.read_text()
    assert '"lock", root.path' in s
    assert "lockedPath(n, root.currentNotebook)" in s


def test_lock_encrypts_and_removes_plaintext(tmp_path):
    if not shutil_which("gpg"):
        return
    plain = tmp_path / "note.md"
    locked = tmp_path / "note.locked.md"
    plain.write_text("secret text")
    env = {**os.environ}
    r = subprocess.run(
        ["python3", str(BRIDGE), "lock", str(plain), str(locked)],
        input=json.dumps({"passphrase": "hunter2", "text": "secret text"}),
        capture_output=True,
        text=True,
        env=env,
    )
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout)["ok"] is True
    assert not plain.exists()
    assert locked.exists()
    r2 = subprocess.run(
        ["python3", str(BRIDGE), "decrypt", str(locked)],
        input=json.dumps({"passphrase": "hunter2"}),
        capture_output=True,
        text=True,
        env=env,
    )
    assert json.loads(r2.stdout)["text"] == "secret text"


def shutil_which(name):
    import shutil

    return shutil.which(name)
