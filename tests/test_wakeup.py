"""bridge/wakeup.py and shani-admin.py's `wakeup`: what may wake the computer.

The fake /sys is laid out as the kernel's is: /sys/bus/usb/devices/<port> and
/sys/class/net/<if>/device are symlinks into /sys/devices, and each device's
switch is power/wakeup ("enabled"/"disabled"). A hub (bDeviceClass 09) and a USB
interface (no idVendor) are not listed; a device without the switch is not either.
"""
import importlib.util
import json
from pathlib import Path

import pytest

BRIDGE = Path(__file__).resolve().parent.parent / "bridge"


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, BRIDGE / file)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def dev(root, rel, wake=None, **attrs):
    d = root / "devices" / rel
    d.mkdir(parents=True, exist_ok=True)
    if wake:
        (d / "power").mkdir()
        (d / "power" / "wakeup").write_text(wake + "\n")
    for k, v in attrs.items():
        (d / k).write_text(v + "\n")
    return d


@pytest.fixture
def sysfs(tmp_path, monkeypatch):
    s = tmp_path / "sys"
    usb = s / "bus/usb/devices"; usb.mkdir(parents=True)
    kbd = dev(s, "pci0000:00/0000:00:14.0/usb1/1-3", "enabled", idVendor="046d", product="USB Keyboard", manufacturer="Logitech", bDeviceClass="00")
    hub = dev(s, "pci0000:00/0000:00:14.0/usb1", "disabled", idVendor="1d6b", product="xHCI Host Controller", bDeviceClass="09")
    intf = dev(s, "pci0000:00/0000:00:14.0/usb1/1-3/1-3:1.0", "disabled")
    nowake = dev(s, "pci0000:00/0000:00:14.0/usb1/1-4", None, idVendor="0bda", product="Card Reader", bDeviceClass="00")
    for name, d in (("1-3", kbd), ("usb1", hub), ("1-3:1.0", intf), ("1-4", nowake)):
        (usb / name).symlink_to(d)
    acpi = s / "bus/acpi/devices"; acpi.mkdir(parents=True)
    lid = dev(s, "LNXSYSTM:00/LNXSYBUS:00/PNP0C0D:00", "enabled")
    (acpi / "PNP0C0D:00").symlink_to(lid)
    net = s / "class/net"; net.mkdir(parents=True)
    nic = dev(s, "pci0000:00/0000:00:1f.6", "disabled")
    (net / "enp0s31f6").mkdir(); (net / "enp0s31f6" / "device").symlink_to(nic)
    (net / "lo").mkdir()                                  # no device: not a card
    monkeypatch.setenv("SHANI_SYSFS", str(s))
    return s, kbd, lid, nic


def test_list_names_what_a_person_recognises(sysfs, capsys):
    s, kbd, lid, nic = sysfs
    w = load("wakeup", "wakeup.py")
    assert w.main(["x", "list"]) == 0
    got = json.loads(capsys.readouterr().out)
    assert got == [
        {"path": str(kbd), "name": "Logitech USB Keyboard", "kind": "usb", "enabled": True},
        {"path": str(lid), "name": "Opening the lid", "kind": "lid", "enabled": True},
        {"path": str(nic), "name": "Wake-on-LAN (enp0s31f6)", "kind": "network", "enabled": False},
    ]


def test_the_admin_action_switches_it_now_and_at_every_boot(sysfs, tmp_path, monkeypatch):
    s, kbd, lid, nic = sysfs
    sa = load("shani_admin_wakeup", "shani-admin.py")
    monkeypatch.setattr(sa, "SYSFS_DEVICES", s / "devices")
    conf = tmp_path / "50-shani-wakeup.conf"
    monkeypatch.setattr(sa, "WAKEUP_TMPFILES", conf)
    assert sa.wakeup({"path": str(kbd), "enabled": False}) == {}
    assert (kbd / "power/wakeup").read_text() == "disabled\n"
    assert sa.wakeup({"path": str(nic), "enabled": True}) == {}
    lines = conf.read_text().splitlines()
    assert f"w {kbd}/power/wakeup - - - - disabled" in lines
    assert f"w {nic}/power/wakeup - - - - enabled" in lines
    sa.wakeup({"path": str(kbd), "enabled": True})         # changed again: one line, the latest
    assert [l for l in conf.read_text().splitlines() if str(kbd) in l] == [f"w {kbd}/power/wakeup - - - - enabled"]


@pytest.mark.parametrize("req,why", [
    ({"path": "/etc", "enabled": False}, "not a device"),
    ({"path": "DEV/../../../../../../etc", "enabled": False}, "not a device"),
    ({"path": "NOWAKE", "enabled": False}, "cannot wake"),
    ({"path": "DEV", "enabled": "no"}, "enabled true or false"),
])
def test_the_admin_action_refuses(sysfs, tmp_path, monkeypatch, req, why):
    s, kbd, lid, nic = sysfs
    sa = load("shani_admin_wakeup2", "shani-admin.py")
    monkeypatch.setattr(sa, "SYSFS_DEVICES", s / "devices")
    monkeypatch.setattr(sa, "WAKEUP_TMPFILES", tmp_path / "w.conf")
    req = dict(req)
    req["path"] = req["path"].replace("DEV", str(kbd)).replace("NOWAKE", str(s / "devices/pci0000:00/0000:00:14.0/usb1/1-4"))
    with pytest.raises(sa.Refused, match=why):
        sa.wakeup(req)
    assert not (tmp_path / "w.conf").exists()
