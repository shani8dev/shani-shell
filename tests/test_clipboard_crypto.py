"""Clipboard history encryption is real (gpg at rest), not just a toggle."""

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CRYPTO = ROOT / "bridge" / "clipboard-crypto.py"
WATCH = ROOT / "bridge" / "clipboard-watch.sh"
qml = (ROOT / "shani/Services/Clipboard.qml").read_text()


def run(args, env):
    return subprocess.run(
        ["python3", str(CRYPTO)] + args, capture_output=True, text=True, env=env
    )


def test_no_manual_age_instruction():
    assert "restart the session or run" not in qml
    assert "setEncrypted" in qml and "clipboard-crypto" in qml
    assert "notifyEncrypted" in qml


def test_all_cliphist_calls_wrapped():
    assert "function clip(args)" in qml
    assert qml.count("clip([") >= 4
    assert '"cliphist"' not in qml.replace('["cliphist"]', "")  # no direct calls
    for line in qml.splitlines():
        if line.strip().startswith("//"):
            continue
        assert (
            "cliphist list" not in line
            and "cliphist decode" not in line
            and "cliphist wipe" not in line
        )
    # the only direct "cliphist" is the clip() helper's fallback array


def test_enable_disable_roundtrip(tmp_path):
    env = {
        **os.environ,
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_DATA_HOME": str(tmp_path / "data"),
    }
    assert json.loads(run(["status"], env).stdout)["encrypted"] is False
    assert json.loads(run(["enable"], env).stdout)["ok"] is True
    assert json.loads(run(["status"], env).stdout)["encrypted"] is True
    assert json.loads(run(["disable"], env).stdout)["ok"] is True
    assert json.loads(run(["status"], env).stdout)["encrypted"] is False


def test_watcher_uses_wrapper():
    s = WATCH.read_text()
    assert "clipboard-crypto.py" in s
    assert "wrap store" in s
    assert "cliphist store" in s
