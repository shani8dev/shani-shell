"""bridge/sshkeys.py: the user's authorized_keys, read and edited as them."""

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("sshkeys", ROOT / "bridge/sshkeys.py")
sk = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sk)


def _run(cmd, home):
    env = os.environ.copy()
    env["HOME"] = str(home)
    r = subprocess.run([sys.executable, str(ROOT / "bridge/sshkeys.py")] + cmd, capture_output=True, text=True, env=env)
    return json.loads(r.stdout)


def test_list_empty(tmp_path):
    got = _run(["list"], tmp_path)
    assert got["keys"] == []
    assert got["exists"] is False


def test_add_list_remove(tmp_path):
    (tmp_path / ".ssh").mkdir(mode=0o700)
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG1vb2t0ZXN0a2V5Zm9ydGVzdGluZw test@host"
    got = _run(["add", "--key", key], tmp_path)
    assert got["ok"] is True
    listed = _run(["list"], tmp_path)
    assert len(listed["keys"]) == 1
    assert listed["keys"][0]["type"] == "ssh-ed25519"
    assert listed["keys"][0]["comment"] == "test@host"
    got = _run(["remove", "--index", "0"], tmp_path)
    assert got["ok"] is True
    assert _run(["list"], tmp_path)["keys"] == []


def test_rejects_bad_key(tmp_path):
    (tmp_path / ".ssh").mkdir(mode=0o700)
    got = _run(["add", "--key", "not a key"], tmp_path)
    assert got["ok"] is False
    assert "key" in got["error"].lower() or "SSH" in got["error"]


def test_rejects_duplicate(tmp_path):
    (tmp_path / ".ssh").mkdir(mode=0o700)
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG1vb2t0ZXN0a2V5Zm9ydGVzdGluZw test@host"
    assert _run(["add", "--key", key], tmp_path)["ok"] is True
    got = _run(["add", "--key", key], tmp_path)
    assert got["ok"] is False
