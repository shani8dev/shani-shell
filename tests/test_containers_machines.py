"""bridge/containers_machines.py against dev/fake-machinectl.py: the machines and
images tables, actions through machinectl, shell and boot argv handed back for QML
to launch, importctl progress streams, and names/URLs/files checked before use."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "containers_machines.py"


@pytest.fixture
def fake(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    tools = {}
    for n in ("machinectl", "importctl", "systemd-vmspawn"):
        p = bindir / n
        p.symlink_to(ROOT / "dev" / "fake-machinectl.py")
        tools[n] = str(p)
    env = dict(
        os.environ,
        FAKE_PODMAN=str(tmp_path),
        PATH="%s:%s" % (bindir, os.environ["PATH"]),
        SHANI_MACHINECTL=tools["machinectl"],
        SHANI_IMPORTCTL=tools["importctl"],
        SHANI_VMSPAWN=tools["systemd-vmspawn"],
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
    p = fake[0] / "machines.json"
    return json.loads(p.read_text()) if p.exists() else None


def test_machines_list(fake):
    lines, r = invoke(fake, "machines-list")
    assert r.returncode == 0 and len(lines) == 1
    l = lines[0]
    assert l["machinectl"] and l["importctl"] and l["vmspawn"]
    assert [m["name"] for m in l["machines"]] == ["archlinux"]
    assert l["machines"][0]["class"] == "systemd-nspawn"
    assert l["machines"][0]["state"] in ("unknown", "running")
    assert [(i["name"], i["type"], i["size"]) for i in l["images"]] == [
        ("archlinux", "raw/directory", "1.2G"),
        ("fedora", "raw/directory", "900M"),
    ]
    assert "machinectl list --no-pager --no-legend" in calls(fake)
    assert "machinectl list-images --no-pager --no-legend" in calls(fake)


def test_machine_start(fake):
    assert one(fake, "machine-poweroff", "archlinux") == ({"ok": True}, 0)
    assert state(fake)["machines"][0]["State"] == "exited"
    assert one(fake, "machine-start", "archlinux") == ({"ok": True}, 0)
    assert "machinectl start archlinux" in calls(fake)
    assert state(fake)["machines"][0]["State"] == "running"
    d, rc = one(fake, "machine-start", "archlinux; rm -rf ~")
    assert rc == 1 and "error" in d


def test_machine_poweroff(fake):
    assert one(fake, "machine-poweroff", "archlinux") == ({"ok": True}, 0)
    assert "machinectl poweroff archlinux" in calls(fake)
    assert state(fake)["machines"][0]["State"] == "exited"
    d, rc = one(fake, "machine-poweroff", "bad name")
    assert rc == 1 and "error" in d


def test_machine_reboot(fake):
    assert one(fake, "machine-reboot", "archlinux") == ({"ok": True}, 0)
    assert "machinectl reboot archlinux" in calls(fake)
    d, rc = one(fake, "machine-reboot", "../archlinux")
    assert rc == 1 and "error" in d


def test_machine_remove(fake):
    assert one(fake, "machine-remove", "archlinux") == ({"ok": True}, 0)
    assert "machinectl remove archlinux" in calls(fake)
    assert state(fake)["machines"] == []
    d, rc = one(fake, "machine-remove", "")
    assert rc == 1 and "error" in d


def test_machine_shell(fake):
    tools = fake[2]
    d, rc = one(fake, "machine-shell", "archlinux")
    assert rc == 0
    assert d["argv"] == [
        "xdg-terminal-exec",
        "sudo",
        tools["machinectl"],
        "shell",
        "archlinux",
        "/bin/bash",
    ]
    assert calls(fake) == ""  # argv returned, never launched
    d, rc = one(fake, "machine-shell", "bad;name")
    assert rc == 1 and "error" in d


def test_machine_image_pull(fake):
    url = "https://example.test/alpine.tar"
    lines, r = invoke(fake, "machine-image-pull", url, "alpine", "tar")
    assert r.returncode == 0 and lines[-1] == {"ok": True}
    assert {"line": "Pulling " + url} in lines
    assert {"line": "Imported alpine"} in lines
    assert "importctl pull-tar %s alpine" % url in calls(fake)
    assert (
        next(i for i in state(fake)["images"] if i["Name"] == "alpine")["Type"] == "tar"
    )

    raw = "http://example.test/disk.raw"
    lines, r = invoke(fake, "machine-image-pull", raw, "disk", "raw")
    assert r.returncode == 0 and lines[-1] == {"ok": True}
    assert "importctl pull-raw %s disk" % raw in calls(fake)
    assert (
        next(i for i in state(fake)["images"] if i["Name"] == "disk")["Type"] == "raw"
    )

    before = calls(fake)
    for bad in (
        ("ftp://example.test/a", "a", "tar"),
        ("https://example.test/a", "bad;name", "tar"),
        ("https://example.test/a", "ok", "zip"),
    ):
        d, rc = one(fake, "machine-image-pull", *bad)
        assert rc == 1 and "error" in d
    assert calls(fake) == before


def test_machine_image_clone(fake):
    assert one(fake, "machine-image-clone", "archlinux", "arch-copy") == (
        {"ok": True},
        0,
    )
    assert "machinectl clone archlinux arch-copy" in calls(fake)
    assert "arch-copy" in [i["Name"] for i in state(fake)["images"]]
    d, rc = one(fake, "machine-image-clone", "archlinux", "bad;name")
    assert rc == 1 and "error" in d


def test_machine_image_rename(fake):
    assert one(fake, "machine-image-rename", "fedora", "fedora-new") == (
        {"ok": True},
        0,
    )
    assert "machinectl rename fedora fedora-new" in calls(fake)
    names = [i["Name"] for i in state(fake)["images"]]
    assert "fedora" not in names and "fedora-new" in names
    d, rc = one(fake, "machine-image-rename", "fedora", "../escape")
    assert rc == 1 and "error" in d


def test_machine_image_remove(fake):
    assert one(fake, "machine-image-remove", "fedora") == ({"ok": True}, 0)
    assert "machinectl remove fedora" in calls(fake)
    assert "fedora" not in [i["Name"] for i in state(fake)["images"]]
    d, rc = one(fake, "machine-image-remove", "fedora; rm -rf ~")
    assert rc == 1 and "error" in d


def test_vmspawn_boot(fake):
    tmp, _, tools = fake
    for suffix in (".raw", ".qcow2"):
        disk = tmp / ("disk" + suffix)
        disk.write_bytes(b"disk")
        d, rc = one(fake, "vmspawn-boot", str(disk))
        assert rc == 0
        assert d["argv"] == [
            "xdg-terminal-exec",
            tools["systemd-vmspawn"],
            "--image",
            str(disk),
        ]
    assert calls(fake) == ""  # argv returned, never launched
    d, rc = one(fake, "vmspawn-boot", str(tmp / "missing.raw"))
    assert rc == 1 and "error" in d
    text = tmp / "notes.txt"
    text.write_text("x")
    d, rc = one(fake, "vmspawn-boot", str(text))
    assert rc == 1 and "error" in d
