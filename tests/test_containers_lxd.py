"""bridge/containers_lxd.py against dev/fake-lxc.py: listing with the
uninitialised case, lxd init progress, launch and state changes through lxc,
shell argv handed back for QML to launch, and names/images checked before use.
Each COMMANDS command has its own test."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "containers_lxd.py"


@pytest.fixture
def fake(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    tools = {}
    for n in ("lxc", "lxd"):
        p = bindir / n
        p.symlink_to(ROOT / "dev" / "fake-lxc.py")
        tools[n] = str(p)
    env = dict(
        os.environ,
        FAKE_LXC=str(tmp_path),
        PATH="%s:%s" % (bindir, os.environ["PATH"]),
        SHANI_LXC=tools["lxc"],
        SHANI_LXD=tools["lxd"],
    )
    return tmp_path, env, tools


def invoke(fake, *args):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *args],
        capture_output=True,
        text=True,
        env=fake[1],
    )
    return [json.loads(l) for l in r.stdout.splitlines() if l.strip()], r


def one(fake, *args):
    lines, r = invoke(fake, *args)
    assert len(lines) == 1, lines
    return lines[0], r.returncode


def calls(fake):
    p = fake[0] / "calls"
    return p.read_text() if p.exists() else ""


def state(fake):
    p = fake[0] / "instances.json"
    return json.loads(p.read_text()) if p.exists() else None


def seed(fake, status):
    data = {
        "instances": [
            {
                "name": "web-lxd",
                "status": status,
                "image": "ubuntu:24.04",
                "type": "container",
                "address": "10.0.0.12",
            }
        ]
    }
    (fake[0] / "instances.json").write_text(json.dumps(data))


def test_lxd_list(fake):
    lines, r = invoke(fake, "lxd-list")
    assert r.returncode == 0 and len(lines) == 1
    d = lines[0]
    assert d["ready"] is True and d["hasLxc"] is True
    assert [i["name"] for i in d["instances"]] == ["web-lxd"]
    assert d["instances"][0]["status"] == "RUNNING"
    assert d["instances"][0]["image"] == "ubuntu:24.04"
    assert d["instances"][0]["type"] == "container"
    assert d["instances"][0]["address"] == "10.0.0.12"
    assert "lxc list --format json" in calls(fake)


def test_lxd_list_uninitialised(fake):
    (fake[0] / "uninitialised").write_text("")
    d, rc = one(fake, "lxd-list")
    assert rc == 0
    assert d["ready"] is False and d["instances"] == []
    assert d["hasLxc"] is True
    assert "error" not in d


def test_lxd_init(fake):
    marker = fake[0] / "uninitialised"
    marker.write_text("")
    lines, r = invoke(fake, "lxd-init")
    assert r.returncode == 0
    assert {"line": "LXD is configured"} in lines
    assert lines[-1] == {"ok": True}
    assert "lxd init --auto" in calls(fake)
    assert not marker.exists()
    d, rc = one(fake, "lxd-list")
    assert rc == 0 and d["ready"] is True and len(d["instances"]) == 1


def test_lxd_launch(fake):
    assert one(fake, "lxd-launch", "ubuntu:24.04", "newbox") == ({"ok": True}, 0)
    assert "lxc launch ubuntu:24.04 newbox" in calls(fake)
    c = next(i for i in state(fake)["instances"] if i["name"] == "newbox")
    assert c["image"] == "ubuntu:24.04" and c["status"] == "RUNNING"


def test_lxd_start(fake):
    seed(fake, "STOPPED")
    assert one(fake, "lxd-start", "web-lxd") == ({"ok": True}, 0)
    assert "lxc start web-lxd" in calls(fake)
    assert state(fake)["instances"][0]["status"] == "RUNNING"


def test_lxd_stop(fake):
    seed(fake, "RUNNING")
    assert one(fake, "lxd-stop", "web-lxd") == ({"ok": True}, 0)
    assert "lxc stop web-lxd" in calls(fake)
    assert state(fake)["instances"][0]["status"] == "STOPPED"


def test_lxd_restart(fake):
    seed(fake, "STOPPED")
    assert one(fake, "lxd-restart", "web-lxd") == ({"ok": True}, 0)
    assert "lxc restart web-lxd" in calls(fake)
    assert state(fake)["instances"][0]["status"] == "RUNNING"


def test_lxd_delete(fake):
    assert one(fake, "lxd-delete", "web-lxd") == ({"ok": True}, 0)
    assert "lxc delete web-lxd --force" in calls(fake)
    assert state(fake)["instances"] == []


def test_lxd_shell(fake):
    tools = fake[2]
    d, rc = one(fake, "lxd-shell", "web-lxd")
    assert rc == 0
    assert d["argv"] == [
        "xdg-terminal-exec",
        tools["lxc"],
        "exec",
        "web-lxd",
        "--",
        "bash",
    ]
    assert calls(fake) == ""  # argv returned, never launched


def test_bad_names(fake):
    before = calls(fake)
    for args in (
        ("lxd-launch", "ubuntu:24.04", "bad;name"),
        ("lxd-launch", "ubuntu;rm", "okname"),
        ("lxd-start", "../evil"),
        ("lxd-stop", "a b"),
        ("lxd-restart", "$(id)"),
        ("lxd-delete", "x; rm -rf ~"),
        ("lxd-shell", "bad|name"),
    ):
        d, rc = one(fake, *args)
        assert rc == 1 and "error" in d, args
    assert calls(fake) == before
