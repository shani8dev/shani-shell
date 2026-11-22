"""Processes gaps: sorting, load/swap/PSI, details, renice, Users view."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_process_list_sorts_by_clicked_column():
    p = read("shani/Modules/Processes/Processes.qml")
    assert 'property string sortKey: "cpu"' in p
    assert "function setSort(key)" in p
    assert 'key: "pid"' in p and 'key: "disk"' in p
    assert 'Tr.t("Sort by %1"' in p
    assert "win.sortRows(" in p


def test_load_swap_and_psi_meters_use_proc_without_new_poller():
    s = read("shani/Services/SysStats.qml")
    assert "property real load1" in s and "property real swapUsedMb" in s
    assert "property real psiCpu" in s and "/proc/pressure/cpu" in s
    p = read("shani/Modules/Processes/Processes.qml")
    assert "SysStats.load1.toFixed(2)" in p
    assert "SysStats.psiCpu" in p and "SysStats.swapUsedMb" in p
    assert p.count("Sparkline {") == 3  # no extra poller/sparkline added


def test_process_details_dialog_and_renice():
    t = read("shani/Services/TopProcesses.qml")
    assert "function showDetails(pid)" in t and "function renice(pid, nice)" in t
    assert "/proc/%d/cmdline" in t and "pwd.getpwuid" in t
    p = read("shani/Modules/Processes/Processes.qml")
    assert "win.openDetails(" in p and "Dialog {" in p
    assert "TopProcesses.renice(win.detailPid" in p


def test_users_view_aggregates_the_same_samples():
    p = read("shani/Modules/Processes/Processes.qml")
    assert "property bool byUser" in p and "property var userList" in p
    assert "model: win.userList" in p
    assert 'Tr.t("Users")' in p
