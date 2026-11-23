"""Vault security (pass-19 #14/#15/#17): a locked shell must not leave vault
plaintext readable, two same-named vaults must not share a mount, and the
one-time master key must reach the JSON result.

Fake-bridge style: stand-in gocryptfs/fusermount3 on PATH, as in test_lock.py.
"""

import importlib.util
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "lock.py"
LOCK_QML = ROOT / "shani" / "Services" / "Lock.qml"


def load():
    spec = importlib.util.spec_from_file_location("lock_under_test", BRIDGE)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _on_path(tmp_path, name, body):
    """Put one fake tool on PATH; return nothing (PATH set by the caller)."""
    b = tmp_path / name
    b.mkdir()
    tool = b / name
    tool.write_text(body)
    tool.chmod(0o755)
    return b


def test_lock_unmounts_every_vault(tmp_path, monkeypatch):
    lock = load()
    run = tmp_path / "run"
    vaults = run / "vaults"
    vaults.mkdir(parents=True)
    p1 = vaults / "Private-a1b2c3d4"
    p2 = vaults / "Work-1e2f3a4b"
    p1.mkdir()
    p2.mkdir()
    log = tmp_path / "unmount.log"
    b = _on_path(tmp_path, "fusermount3", '#!/bin/sh\necho "$*" >> %s\n' % log)
    monkeypatch.setenv("PATH", str(b) + os.pathsep + os.environ["PATH"])
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(run))
    monkeypatch.setattr(lock, "_mounted", lambda p: True)

    assert lock.vault_close_all() == {"closed": 2}
    lines = log.read_text().splitlines()
    assert "-u %s" % p1 in lines and "-u %s" % p2 in lines
    # Lock.qml drives it through the existing bridge tool, not a new daemon.
    qml = LOCK_QML.read_text()
    assert "vault-close-all" in qml and "Quickshell.Io" in qml


def test_mount_point_unique_per_absolute_path(tmp_path, monkeypatch):
    lock = load()
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path / "run"))
    a = lock.vault_point(str(tmp_path / "alice" / "Private"))
    b = lock.vault_point(str(tmp_path / "bob" / "Private"))
    assert a != b
    assert a.startswith(str(tmp_path / "run" / "vaults" / "Private-"))
    assert b.startswith(str(tmp_path / "run" / "vaults" / "Private-"))
    assert lock.vault_point(str(tmp_path / "alice" / "Private/")) == a  # stable


def test_vault_new_returns_master_key(tmp_path, monkeypatch):
    lock = load()
    key = "deadbeef-12345678-cafebabe-87654321-0f0f0f0f-f0f0f0f0-11112222-33334444"
    body = (
        "#!/bin/sh\n"
        '[ "$1" = -init ] || exit 1\n'
        'eval "d=\\${$#}"\n'
        'touch "$d/gocryptfs.conf"\n'
        'echo "Your master key is:"\n'
        'echo "    %s"\n' % key
    )
    b = _on_path(tmp_path, "gocryptfs", body)
    monkeypatch.setenv("PATH", str(b) + os.pathsep + os.environ["PATH"])

    out = lock.vault_new(str(tmp_path / "Private"), "pw")
    assert out == {"saved": str(tmp_path / "Private"), "masterKey": key}
