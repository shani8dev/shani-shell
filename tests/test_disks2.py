"""Static/unit guards for the remaining pass-21 disk UX fixes.

Covers: standalone relabel, read-only fsck/bad-block scans, disk type/protocol,
and SMART self-test progress polling with a completion notification.
"""

import importlib.machinery
import importlib.util
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WINDOW = ROOT / "shani" / "Modules" / "Disks" / "DisksWindow.qml"
SERVICE = ROOT / "shani" / "Services" / "Disks.qml"

SYSTEM_TREE = [
    {
        "name": "/dev/sda",
        "pkname": "",
        "mountpoints": [],
        "children": [
            {"name": "/dev/sda1", "pkname": "sda", "mountpoints": ["/"]},
        ],
    },
    {
        "name": "/dev/sdb",
        "pkname": "",
        "mountpoints": [],
        "children": [
            {"name": "/dev/sdb1", "pkname": "sdb", "mountpoints": []},
        ],
    },
]


def load_disks():
    loader = importlib.machinery.SourceFileLoader(
        "disks_pass21", str(ROOT / "bridge" / "disks.py")
    )
    mod = importlib.util.module_from_spec(
        importlib.util.spec_from_loader("disks_pass21", loader)
    )
    loader.exec_module(mod)
    return mod


def fake_run(calls, stdout="", stderr="", code=0):
    def run(cmd, **kw):
        calls.append(list(cmd))
        return subprocess.CompletedProcess(cmd, code, stdout, stderr)

    return run


def test_relabel_uses_filesystem_tool_and_guards_system_disk(monkeypatch, capsys):
    disks = load_disks()
    calls = []
    monkeypatch.setattr(disks, "_current_disks", lambda: SYSTEM_TREE)
    monkeypatch.setattr(disks.shutil, "which", lambda name: True)
    monkeypatch.setattr(disks, "run", fake_run(calls))

    monkeypatch.setattr(disks, "device_fstype", lambda dev: "ext4")
    assert disks.relabel("/dev/sdb1", "STICK") == 0
    assert calls[-1] == ["e2label", "/dev/sdb1", "STICK"]

    monkeypatch.setattr(disks, "device_fstype", lambda dev: "xfs")
    assert disks.relabel("/dev/sdb1", "DATA") == 0
    assert calls[-1] == ["xfs_admin", "-L", "DATA", "/dev/sdb1"]

    monkeypatch.setattr(disks, "device_fstype", lambda dev: "vfat")
    assert disks.relabel("/dev/sdb1", "USB") == 0
    assert calls[-1] == ["dosfslabel", "/dev/sdb1", "USB"]

    assert disks.relabel("/dev/sda1", "ROOT") == 1
    assert "running system disk" in capsys.readouterr().out

    s, w = SERVICE.read_text(), WINDOW.read_text()
    assert "function relabel(device, label)" in s and '"relabel", device' in s
    assert 'Tr.t("Relabel…")' in w and "relabelDialog" in w
    assert "win.confirmAction === key" in w


def test_fsck_and_badblocks_are_read_only_with_visible_output(monkeypatch, capsys):
    disks = load_disks()
    calls = []
    monkeypatch.setattr(disks, "_block_running_root", lambda dev: False)
    monkeypatch.setattr(disks, "run", fake_run(calls, stdout="scan output"))

    assert disks.fsck_check("/dev/sdb1") == 0
    assert disks.badblocks_scan("/dev/sdb1") == 0
    assert calls[0] == ["fsck", "-n", "/dev/sdb1"]
    assert calls[1] == ["badblocks", "-n", "-s", "/dev/sdb1"]
    for cmd in calls:
        assert not any(flag in cmd for flag in ("-y", "-r", "-w", "--repair"))

    records = [
        json.loads(line)
        for line in capsys.readouterr().out.splitlines()
        if line.startswith("{")
    ]
    assert len(records) == 2
    assert all("output" in r and "scan output" in r["output"] for r in records)

    monkeypatch.setattr(disks, "_block_running_root", lambda dev: True)
    assert disks.fsck_check("/dev/sda1") == 1
    assert disks.badblocks_scan("/dev/sda1") == 1

    s, w = SERVICE.read_text(), WINDOW.read_text()
    assert "function fsck(device)" in s and "function badblocks(device)" in s
    assert '"fsck", device' in s and '"badblocks", device' in s
    assert "scanResult" in s and "id: scanDialog" in w
    assert 'Tr.t("Check filesystem")' in w and 'Tr.t("Bad blocks")' in w
    assert 'win.confirmAction === "fsck-" + modelData.path' in w
    assert "Disks.scanResult.output" in w


def test_list_and_ui_expose_transport_and_rotational(monkeypatch, capsys):
    disks = load_disks()
    calls = []
    payload = json.dumps(
        {
            "blockdevices": [
                {"name": "nvme0n1", "tran": "nvme", "rota": 0, "size": 1000},
            ]
        }
    )
    monkeypatch.setattr(disks, "run", fake_run(calls, stdout=payload))

    assert disks.list_disks() == 0
    assert any("TRAN" in " ".join(c) and "ROTA" in " ".join(c) for c in calls)
    listed = json.loads(capsys.readouterr().out)["blockdevices"][0]
    assert listed["tran"] == "nvme" and listed["rota"] == 0

    s, w = SERVICE.read_text(), WINDOW.read_text()
    assert "TRAN,ROTA" in s
    assert "transport: d.tran" in s and "rotational: d.rota" in s
    assert "function diskKind(d)" in w and "win.diskKind(modelData)" in w
    assert 'Tr.t("SSD")' in w and 'Tr.t("HDD")' in w


def test_smart_status_progress_is_polled_and_completion_notifies(monkeypatch, capsys):
    disks = load_disks()
    calls = []
    reports = [
        {
            "ata_smart_self_test_log": {
                "standard": {
                    "table": [
                        {
                            "status": {"string": "Self-test in progress"},
                            "progress": {"remaining": "90%"},
                        }
                    ]
                }
            }
        },
        {
            "ata_smart_self_test_log": {
                "standard": {
                    "table": [
                        {
                            "status": {"string": "Completed without error"},
                            "progress": {"remaining": "0%"},
                        }
                    ]
                }
            }
        },
    ]
    outputs = iter(json.dumps(r) for r in reports)
    monkeypatch.setattr(disks.shutil, "which", lambda name: True)
    monkeypatch.setattr(
        disks,
        "run",
        lambda cmd, **kw: (
            calls.append(list(cmd))
            or subprocess.CompletedProcess(cmd, 0, next(outputs), "")
        ),
    )

    assert disks.smart_status("/dev/sdb") == 0
    first = json.loads(capsys.readouterr().out)
    assert first["active"] is True and first["remaining"] == 90
    assert calls[-1] == ["smartctl", "-a", "-j", "/dev/sdb"]

    assert disks.smart_status("/dev/sdb") == 0
    second = json.loads(capsys.readouterr().out)
    assert second["active"] is False

    s, w = SERVICE.read_text(), WINDOW.read_text()
    assert "function pollSmartTest()" in s and '"smart-status"' in s
    assert "id: smartPollTimer" in s and "interval: 5000" in s
    assert "notify-send" in s and 'Tr.t("SMART self-test finished")' in s
    assert "smartTestPercent" in w and "win.smartEta()" in w
