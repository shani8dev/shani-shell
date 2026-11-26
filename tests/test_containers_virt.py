"""bridge/containers_virt.py against dev/fake-virsh.py: VMs from both libvirt
URIs, actions through virsh, viewer/terminal argv handed back for QML to launch,
remove with or without disks, and names/URIs checked before use."""

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "containers_virt.py"
FAKE = ROOT / "dev" / "fake-virsh.py"


@pytest.fixture
def fake(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    virsh = bindir / "virsh"
    viewer = bindir / "virt-viewer"
    virsh.symlink_to(FAKE)
    viewer.symlink_to(FAKE)
    env = dict(
        os.environ,
        FAKE_VIRSH=str(tmp_path),
        PATH=str(bindir),  # no flatpak unless a test adds one
        SHANI_VIRSH=shlex.join([sys.executable, str(virsh)]),
        SHANI_VIRT_VIEWER=shlex.join([sys.executable, str(viewer)]),
    )
    env.pop("SHANI_KVM", None)

    def run(*args, override=None):
        r = subprocess.run(
            [sys.executable, str(BRIDGE), *map(str, args)],
            capture_output=True,
            text=True,
            env=override if override is not None else env,
        )
        lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
        out = lines if len(lines) != 1 else lines[0]
        return out, r.returncode

    def text(name):
        p = tmp_path / name
        return p.read_text() if p.exists() else ""

    ns = SimpleNamespace(
        dir=tmp_path,
        bin=bindir,
        env=env,
        run=run,
        calls=lambda: text("calls"),
        domains=lambda: (
            json.loads(text("domains.json")) if text("domains.json") else None
        ),
        undefined=lambda: text("undefined").splitlines(),
        viewer=shlex.split(env["SHANI_VIRT_VIEWER"])[0],
    )
    return ns


def test_virt_list(fake):
    out, rc = fake.run("virt-list")
    assert rc == 0
    assert out["hasVirsh"] and out["hasViewer"] and out["systemAllowed"]
    assert out["hasBoxes"] is False
    assert [(d["name"], d["uri"]) for d in out["domains"]] == [
        ("dev-vm", "qemu:///session"),
        ("server-vm", "qemu:///system"),
    ]
    assert all(d["state"] == "unknown" for d in out["domains"])
    c = fake.calls()
    assert "virsh -c qemu:///session list --all --name" in c
    assert "virsh -c qemu:///session list --all\n" in c
    assert "virsh -c qemu:///system list --all --name" in c
    assert "virsh -c qemu:///system list --all\n" in c


def test_kvm_flag(fake):
    out, rc = fake.run("virt-list", override=dict(fake.env, SHANI_KVM="1"))
    assert rc == 0 and out["kvm"] is True
    plain = dict(fake.env)
    plain.pop("SHANI_KVM", None)
    out, rc = fake.run("virt-list", override=plain)
    assert rc == 0 and out["kvm"] == os.path.exists("/dev/kvm")


def test_virt_start(fake):
    assert fake.run("virt-shutdown", "dev-vm") == ({"ok": True}, 0)
    assert fake.domains()["session"][0]["state"] == "shut off"
    assert fake.run("virt-start", "dev-vm") == ({"ok": True}, 0)  # default session
    assert "virsh -c qemu:///session start dev-vm" in fake.calls()
    assert fake.domains()["session"][0]["state"] == "running"


def test_virt_shutdown(fake):
    assert fake.run("virt-start", "server-vm", "qemu:///system") == ({"ok": True}, 0)
    assert fake.run("virt-shutdown", "server-vm", "qemu:///system") == ({"ok": True}, 0)
    assert "virsh -c qemu:///system shutdown server-vm" in fake.calls()
    assert fake.domains()["system"][0]["state"] == "shut off"


def test_virt_force_off(fake):
    assert fake.run("virt-force-off", "dev-vm") == ({"ok": True}, 0)
    assert "virsh -c qemu:///session destroy dev-vm" in fake.calls()
    assert fake.domains()["session"][0]["state"] == "shut off"


def test_virt_reboot(fake):
    assert fake.run("virt-reboot", "dev-vm") == ({"ok": True}, 0)
    assert "virsh -c qemu:///session reboot dev-vm" in fake.calls()
    assert fake.domains()["session"][0]["state"] == "running"


def test_virt_console(fake):
    out, rc = fake.run("virt-console", "dev-vm", "qemu:///session")
    assert rc == 0 and out["argv"] == [fake.viewer, "dev-vm"]
    assert fake.calls() == ""  # argv returned, never launched
    hidden = dict(fake.env, SHANI_VIRT_VIEWER=str(fake.dir / "no-viewer"))
    out, rc = fake.run("virt-console", "dev-vm", "qemu:///session", override=hidden)
    assert rc == 0
    assert out["argv"] == [
        "xdg-terminal-exec",
        "virsh",
        "-c",
        "qemu:///session",
        "console",
        "dev-vm",
    ]
    assert fake.calls() == ""


def test_virt_remove(fake):
    assert fake.run("virt-remove", "dev-vm") == ({"ok": True}, 0)
    assert "virsh -c qemu:///session undefine dev-vm" in fake.calls()
    assert fake.domains()["session"] == []
    assert fake.undefined() == ["dev-vm|0"]  # disks kept


def test_virt_remove_disks(fake):
    assert fake.run("virt-remove-disks", "server-vm", "qemu:///system") == (
        {"ok": True},
        0,
    )
    assert (
        "virsh -c qemu:///system undefine server-vm --remove-all-storage"
        in fake.calls()
    )
    assert fake.domains()["system"] == []
    assert fake.undefined() == ["server-vm|1"]


def test_virt_open_boxes(fake):
    out, rc = fake.run("virt-open-boxes")
    assert rc == 1 and out == {"error": "Boxes is not installed"}
    flatpak = fake.bin / "flatpak"
    flatpak.write_text("#!/bin/sh\nexit 0\n")
    flatpak.chmod(0o755)
    listing, rc = fake.run("virt-list")
    assert rc == 0 and listing["hasBoxes"] is True
    before = fake.calls()
    out, rc = fake.run("virt-open-boxes")
    assert rc == 0 and out == {"argv": ["flatpak", "run", "org.gnome.Boxes"]}
    assert fake.calls() == before  # argv returned, never launched


@pytest.mark.parametrize(
    "cmd",
    [
        "virt-start",
        "virt-shutdown",
        "virt-force-off",
        "virt-reboot",
        "virt-console",
        "virt-remove",
        "virt-remove-disks",
    ],
)
def test_bad_name_and_uri(fake, cmd):
    out, rc = fake.run(cmd, "bad;name")
    assert rc == 1 and "error" in out
    out, rc = fake.run(cmd, "dev-vm", "qemu://evil")
    assert rc == 1 and "error" in out
    assert fake.calls() == ""
