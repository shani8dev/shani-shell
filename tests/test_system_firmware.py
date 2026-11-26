"""bridge/system_firmware.py against dev/fake-fwupdmgr.py: fwupd's own JSON fields
become devices and updates, apply gets exactly the two safety flags, and a
missing or malformed tool is reported rather than filled in."""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_firmware.py"
FAKE = ROOT / "dev" / "fake-fwupdmgr.py"


def run(tmp_path, *args, tool="fwupdmgr", extra=None):
    link = tmp_path / "fwupdmgr"
    if not link.exists():
        link.symlink_to(FAKE)
    env = dict(
        os.environ,
        FAKE_FWUPDMGR=str(tmp_path),
        PATH="%s:%s" % (tmp_path, os.environ["PATH"]),
        SHANI_FWUPDMGR=tool,
    )
    env.update(extra or {})
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *args], capture_output=True, text=True, env=env
    )
    lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
    return (lines[0] if len(lines) == 1 else lines), r


def calls(tmp_path):
    return (tmp_path / "calls").read_text()


def test_devices_keep_fwupd_fields_and_their_release(tmp_path):
    got, r = run(tmp_path, "devices")
    assert r.returncode == 0 and got["have"] is True and got["error"] == ""
    assert [
        (d["id"], d["name"], d["version"], d["vendor"]) for d in got["devices"]
    ] == [
        ("a1b2c3d4", "Laptop system firmware", "1.2.3", "shani"),
        ("e5f6a7b8", "Storage controller", "2.0.0", "storage"),
    ]
    assert got["devices"][0]["updates"] == [
        {
            "version": "1.3.0",
            "name": "System firmware 1.3.0",
            "description": "Improves battery life and fixes a boot problem.",
        }
    ]
    assert got["devices"][1]["updates"] == []
    assert "fwupdmgr get-devices --json" in calls(tmp_path)


def test_updates_are_their_own_list(tmp_path):
    got, _ = run(tmp_path, "updates")
    assert got["have"] is True and got["updates"] == [
        {
            "id": "a1b2c3d4",
            "name": "Laptop system firmware",
            "version": "1.3.0",
            "description": "Improves battery life and fixes a boot problem.",
        }
    ]
    assert "fwupdmgr get-updates --json" in calls(tmp_path)


def test_apply_has_exact_argv_and_returns_last_lines(tmp_path):
    got, r = run(tmp_path, "apply")
    assert r.returncode == 0 and got["ok"] is True and got["error"] == ""
    assert "Restart is not needed" in got["output"]
    assert got["output"].splitlines()[-1] == "Restart is not needed"
    assert "fwupdmgr update --assume-yes --no-reboot-check" in calls(tmp_path)


def test_wrapped_json_is_tolerated(tmp_path):
    devices, _ = run(tmp_path, "devices", extra={"FAKE_FWUPDMGR_SHAPE": "object"})
    updates, _ = run(tmp_path, "updates", extra={"FAKE_FWUPDMGR_SHAPE": "object"})
    assert len(devices["devices"]) == 2 and len(updates["updates"]) == 1


def test_missing_tool_and_bad_json_are_honest(tmp_path):
    missing, r = run(tmp_path, "devices", tool="no-such-fwupd")
    assert r.returncode == 0 and missing["have"] is False
    assert missing["devices"] == [] and "not available" in missing["error"]
    broken, _ = run(tmp_path, "updates", extra={"FAKE_FWUPDMGR_BROKEN": "1"})
    assert broken["have"] is False and broken["updates"] == [] and broken["error"]


def test_no_shell_in_the_tool_name(tmp_path):
    target = tmp_path / "PWNED"
    got, r = run(tmp_path, "devices", tool="fwupdmgr; touch %s" % target)
    assert not target.exists() and r.returncode == 0
    assert got["have"] is False and got["devices"] == []


def test_no_verb_beyond_apply(tmp_path):
    _, r = run(tmp_path, "apply", "--home")
    assert r.returncode == 2 and not r.stdout
