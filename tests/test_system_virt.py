"""bridge/system_virt.py against dev/fake-system-virt.py: KVM readiness from
a device and /proc/modules, and a read-only inventory from the four runtimes.
Absent tools and an absent LXD socket give no machines at all; no verb here
can start, stop or create one.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_virt.py"
FAKE = ROOT / "dev" / "fake-system-virt.py"


def setup(tmp_path, commands=("virsh", "lxc-ls", "lxc", "machinectl")):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    for name in commands:
        (bin_dir / name).symlink_to(FAKE)
    env = dict(os.environ)
    env.update(
        {
            "FAKE_SYSTEM_VIRT": str(tmp_path),
            "PATH": str(bin_dir) + ":" + os.environ["PATH"],
            "SHANI_SYSTEM_VIRSH": "virsh",
            "SHANI_SYSTEM_LXC": "lxc-ls",
            "SHANI_SYSTEM_LXD": "lxc",
            "SHANI_SYSTEM_MACHINECTL": "machinectl",
            "SHANI_LXD_SOCKET": str(tmp_path / "lxd.sock"),
            "SHANI_KVM_PATH": str(tmp_path / "kvm"),
            "SHANI_MODULES_FILE": str(tmp_path / "modules"),
        }
    )
    return env


def call(env, verb):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), verb], capture_output=True, text=True, env=env
    )
    return json.loads(r.stdout), r


def test_kvm_device_and_modules(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "kvm").write_text("")
    (tmp_path / "modules").write_text(
        "kvm_intel 200000 0\nkvm 600000 1 kvm_intel\nother 10 0\n"
    )
    got, _ = call(env, "kvm")
    assert got["device"] is True
    assert got["modules"] == ["kvm_intel", "kvm"]
    assert got["usable"] is True and got["detail"]
    (tmp_path / "kvm").unlink()
    (tmp_path / "modules").unlink()
    gone, _ = call(env, "kvm")
    assert gone["device"] is False and gone["modules"] == []
    assert gone["usable"] is False and gone["detail"]


def test_inventory_reads_all_four_runtimes(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "virsh.out").write_text(
        " Id   Name                 State\n------------------------------\n"
        " 1    web                  running\n -    old-box              shut off\n"
    )
    (tmp_path / "lxc-ls.out").write_text(
        "NAME    STATE    AUTOSTART    GROUPS    IPV4    IPV6\n"
        "web     RUNNING  1            -         10.0.0.2 -\n"
    )
    (tmp_path / "lxc.out").write_text(
        "+-------+---------+\n| NAME  | STATE   |\n+-------+---------+\n"
        "| db    | RUNNING |\n+-------+---------+\n"
    )
    (tmp_path / "machinectl.out").write_text(
        "MACHINE    CLASS   SERVICE   OS   VERSION   ADDRESSES\n"
        "dev-vm     vm      systemd   os   1         10.0.0.3\n"
    )
    (tmp_path / "lxd.sock").write_text("")
    got, r = call(env, "inventory")
    assert r.returncode == 0 and got["error"] == ""
    assert all(got["have"].values())
    assert got["libvirt"] == [
        {"name": "web", "state": "running"},
        {"name": "old-box", "state": "shut off"},
    ]
    assert got["lxc"] == [{"name": "web", "state": "RUNNING"}]
    assert got["lxd"] == [{"name": "db", "state": "RUNNING"}]
    assert got["nspawn"] == [{"name": "dev-vm", "state": "running"}]


def test_missing_tools_report_no_machines(tmp_path):
    env = setup(tmp_path, commands=())
    empty_dir = tmp_path / "empty"
    empty_dir.mkdir()
    env["PATH"] = str(empty_dir)
    got, _ = call(env, "inventory")
    assert got["have"] == {
        "virsh": False,
        "lxc": False,
        "lxd": False,
        "machinectl": False,
    }
    assert got["libvirt"] == got["lxc"] == got["lxd"] == got["nspawn"] == []


def test_absent_lxd_socket_fabricates_nothing(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "lxc.out").write_text("| db | RUNNING |\n")
    got, _ = call(env, "inventory")
    assert got["have"]["lxd"] is True and got["lxd"] == []
    assert "lxc list" not in (tmp_path / "calls").read_text()


def test_no_lifecycle_verb(tmp_path):
    env = setup(tmp_path)
    for verb in ("start", "stop", "restart", "create", "remove"):
        result, r = call(env, verb)
        assert r.returncode == 2 and result["error"]
    assert call(env, "inventory")[1].returncode == 0
