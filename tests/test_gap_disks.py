"""Disks gaps: space bar, SMART dialog, job progress, mount options, tools."""

import importlib.machinery
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def load_disks():
    loader = importlib.machinery.SourceFileLoader(
        "disks_gap", str(ROOT / "bridge" / "disks.py")
    )
    mod = importlib.util.module_from_spec(
        importlib.util.spec_from_loader("disks_gap", loader)
    )
    loader.exec_module(mod)
    return mod


def test_proportional_space_allocation_bar():
    s = read("shani/Services/Disks.qml")
    assert '"lsblk", "-J", "-b"' in s and "bytes: Number(d.size)" in s
    w = read("shani/Modules/Disks/DisksWindow.qml")
    assert "proportional space-allocation bar" in w
    assert "diskRow.modelData.bytes" in w


def test_detailed_smart_dialog_and_self_tests():
    b = read("bridge/disks.py")
    assert "def smart_details(device" in b and "def smart_test(device" in b
    assert '"smartctl", "-t"' in b
    s = read("shani/Services/Disks.qml")
    assert (
        "function smartDetails(device)" in s and "function smartTest(device, kind)" in s
    )
    w = read("shani/Modules/Disks/DisksWindow.qml")
    assert "smartDialog" in w and "Start self-test" in w


def test_job_progress_and_cancel_in_disks_surface():
    s = read("shani/Services/Disks.qml")
    assert "property real jobProgress" in s and "SplitParser" in s
    assert "function cancelJob()" in s
    w = read("shani/Modules/Disks/DisksWindow.qml")
    assert "Disks.jobProgress" in w and 'Tr.t("Cancel job")' in w


def test_mount_options_benchmark_ownership_and_detach():
    s = read("shani/Services/Disks.qml")
    assert "function mountWithOptions(device, options)" in s and '"-o"' in s
    assert "function detachLoop(device)" in s and "function takeOwnership(device)" in s
    b = read("bridge/disks.py")
    assert "def benchmark(device" in b and "mbps" in b
    assert "def take_ownership(device" in b
    w = read("shani/Modules/Disks/DisksWindow.qml")
    for token in ("mountDialog", 'Tr.t("Benchmark")', "Take ownership", "Detach loop"):
        assert token in w


def test_unknown_self_test_and_non_device_benchmark_are_refused(capsys):
    disks = load_disks()
    assert disks.smart_test("/dev/null", "bogus") == 1
    assert "unknown self-test" in capsys.readouterr().out
    assert disks.benchmark("/tmp/not-a-device") == 1
    assert "not a device path" in capsys.readouterr().out
