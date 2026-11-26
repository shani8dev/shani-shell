"""bridge/containers_waydroid.py against dev/fake-waydroid.py: status parsing,
session start/stop, the full-UI argv handed back for QML to launch, and pkexec
setup streaming - checked by what the stand-in recorded, not by reading the
bridge. SHANI_PKEXEC is empty so init calls the helper without real pkexec."""

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "containers_waydroid.py"
FAKE = ROOT / "dev" / "fake-waydroid.py"


@pytest.fixture
def fake(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    links = {}
    for n in ("waydroid", "waydroid-helper"):
        p = bindir / n
        p.symlink_to(FAKE)
        links[n] = str(p)
    env = dict(
        os.environ,
        FAKE_WAYDROID=str(tmp_path),
        PATH="%s:%s" % (bindir, os.environ["PATH"]),
        SHANI_WAYDROID=links["waydroid"],
        SHANI_WAYDROID_HELPER=links["waydroid-helper"],
        SHANI_PKEXEC="",
    )
    return tmp_path, env, links


def invoke(fake, *args, env=None):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *args],
        capture_output=True,
        text=True,
        env=env if env is not None else fake[1],
    )
    return [json.loads(l) for l in r.stdout.splitlines() if l.strip()], r


def one(fake, *args, env=None):
    lines, r = invoke(fake, *args, env=env)
    assert len(lines) == 1, lines
    return lines[0], r.returncode


def calls(fake):
    p = fake[0] / "calls"
    return p.read_text() if p.exists() else ""


def status(fake):
    return json.loads((fake[0] / "status.json").read_text())


def test_command_catalog():
    spec = importlib.util.spec_from_file_location("containers_waydroid", BRIDGE)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    assert set(m.COMMANDS) == {
        "waydroid-status",
        "waydroid-start",
        "waydroid-stop",
        "waydroid-ui",
        "waydroid-init",
    }


def test_waydroid_status(fake):
    d, rc = one(fake, "waydroid-status")
    assert rc == 0
    assert d == {
        "available": True,
        "helper": True,
        "initialised": True,
        "session": "STOPPED",
    }
    assert "waydroid status" in calls(fake)

    (fake[0] / "notinitialised").write_text("")
    d, rc = one(fake, "waydroid-status")
    assert rc == 0 and d["initialised"] is False and d["session"] == "STOPPED"


def test_waydroid_start(fake):
    assert one(fake, "waydroid-start") == ({"ok": True}, 0)
    assert "waydroid session start" in calls(fake)
    assert status(fake)["session"] == "RUNNING"
    assert one(fake, "waydroid-status")[0]["session"] == "RUNNING"


def test_waydroid_stop(fake):
    assert one(fake, "waydroid-start") == ({"ok": True}, 0)
    assert one(fake, "waydroid-stop") == ({"ok": True}, 0)
    assert "waydroid session stop" in calls(fake)
    assert status(fake)["session"] == "STOPPED"
    assert one(fake, "waydroid-status")[0]["session"] == "STOPPED"


def test_waydroid_ui(fake):
    d, rc = one(fake, "waydroid-ui")
    assert rc == 0 and d == {"argv": ["waydroid", "show-full-ui"]}
    assert calls(fake) == ""  # argv returned, never launched


def test_waydroid_init(fake):
    marker = fake[0] / "notinitialised"
    marker.write_text("")
    assert marker.exists()
    lines, r = invoke(fake, "waydroid-init")
    assert r.returncode == 0 and lines[-1] == {"ok": True}
    assert {"line": "Initialising Waydroid"} in lines
    assert {"line": "Android image installed"} in lines
    assert not marker.exists()
    assert "waydroid-helper init" in calls(fake)


def test_missing_helper_error(fake):
    tmp, _, _ = fake
    env = dict(fake[1], SHANI_WAYDROID_HELPER=str(tmp / "missing" / "waydroid-helper"))
    d, rc = one(fake, "waydroid-init", env=env)
    assert rc == 1 and d == {"error": "the Waydroid setup helper is not installed"}
    assert not (tmp / "calls").exists()  # no call reached the stand-ins

    d, rc = one(fake, "waydroid-status", env=env)
    assert rc == 0 and d["helper"] is False


def test_status_without_waydroid(fake):
    tmp, _, _ = fake
    env = dict(fake[1], SHANI_WAYDROID=str(tmp / "missing" / "waydroid"))
    d, rc = one(fake, "waydroid-status", env=env)
    assert rc == 0 and d["available"] is False and d["session"] == "unknown"
    assert not (tmp / "calls").exists()


def test_bad_args_rejected(fake):
    for args in (
        ("waydroid-status", "extra"),
        ("waydroid-start", "extra"),
        ("waydroid-stop", "extra"),
        ("waydroid-ui", "extra"),
        ("waydroid-init", "extra"),
        ("bogus",),
    ):
        d, rc = one(fake, *args)
        assert rc == 1 and "error" in d, args
    assert not (fake[0] / "calls").exists()
