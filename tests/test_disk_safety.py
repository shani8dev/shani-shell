"""Static/unit guards for the pass-21 disk safety fixes.

The bridge decides, as root and at call time, which device backs the running
root filesystem; the QML mirrors that decision and adds a typed-device gate.
"""

import importlib.machinery
import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WINDOW = ROOT / "shani" / "Modules" / "Disks" / "DisksWindow.qml"
SERVICE = ROOT / "shani" / "Services" / "Disks.qml"


def load_disks():
    loader = importlib.machinery.SourceFileLoader(
        "disks_safety", str(ROOT / "bridge" / "disks.py")
    )
    mod = importlib.util.module_from_spec(
        importlib.util.spec_from_loader("disks_safety", loader)
    )
    loader.exec_module(mod)
    return mod


SYSTEM_TREE = [
    {
        "name": "/dev/sda",
        "pkname": "",
        "mountpoints": [],
        "children": [
            {"name": "/dev/sda1", "pkname": "sda", "mountpoints": ["/boot"]},
            {"name": "/dev/sda2", "pkname": "sda", "mountpoints": ["/"]},
        ],
    },
    {
        "name": "/dev/sdb",
        "pkname": "",
        "mountpoints": [],
        "children": [
            {
                "name": "/dev/sdb1",
                "pkname": "sdb",
                "mountpoints": ["/run/media/me/STICK"],
            },
        ],
    },
]


def test_running_system_disk_is_never_a_destructive_target(monkeypatch, capsys):
    disks = load_disks()
    protected = disks.protected_devices(SYSTEM_TREE)
    assert {"/dev/sda", "/dev/sda1", "/dev/sda2"} <= protected, (
        "the whole system disk and all its partitions are protected"
    )
    assert not {"/dev/sdb", "/dev/sdb1"} & protected, "a USB stick is not protected"

    monkeypatch.setattr(disks, "_current_disks", lambda: SYSTEM_TREE)
    for target in ("/dev/sda2", "/dev/sda"):
        assert disks._block_running_root(target) is True, target
        assert "running system disk" in capsys.readouterr().out
    assert disks._block_running_root("/dev/sdb1") is False
    capsys.readouterr()

    monkeypatch.setattr(disks, "_current_disks", lambda: [])
    assert disks._block_running_root("/dev/sdb1") is True, (
        "fail closed when root is unknown"
    )
    assert "cannot identify the running system disk" in capsys.readouterr().out

    w = WINDOW.read_text()
    assert "function canDestroy()" in w
    assert "Disks.deviceIsSystem" in w
    assert "win.formConfirm.trim() === d.path" in w
    assert w.count("enabled: win.canDestroy()") >= 4, (
        "erase/format/encrypt buttons are gated"
    )
    s = SERVICE.read_text()
    assert "function deviceIsSystem(path)" in s


def test_encrypt_passphrase_is_confirmed_and_minimum_eight():
    w = WINDOW.read_text()
    assert "property string formPassphrase2" in w
    assert 'placeholder: Tr.t("Passphrase again")' in w
    assert "win.formPassphrase.length >= 8" in w
    assert "win.formPassphrase === win.formPassphrase2" in w
    assert "no way to recover this passphrase" in w.lower()

    disks = load_disks()
    assert disks.passphrase_ok("short") is False
    assert disks.passphrase_ok("longenough") is True


def test_unmount_offered_for_mounted_internal_device():
    w = WINDOW.read_text()
    m = re.search(r'Button \{\s*text: Tr\.t\("Unmount"\).*?\}', w, re.S)
    assert m, "an Unmount button exists"
    block = m.group(0)
    assert "Disks.unmount(modelData.path)" in block
    assert "!modelData.removable" in block
    assert "modelData.mountpoints.length > 0" in block
