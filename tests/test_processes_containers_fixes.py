"""New Process/Container fixes, as static invariants on the QML they touch.

1. a process search is a flat hit list, not indented orphans, and says when nothing matched;
2. the End confirmation is scoped to a PID, not to a recycled delegate row;
3. container start/stop/restart report success instead of changing state silently;
4. a refresh drops confirmation/log state whose item has vanished from the list.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(p):
    return (ROOT / p).read_text()


def test_process_search_is_flat():
    s = read("shani/Modules/Processes/Processes.qml")
    # a name hit keeps its parent's indent in the tree, which shows an indented
    # child under a parent that did not match; a search is a flat list instead
    assert ".map(x => ({ p: x.p, indent: 0 }))" in s


def test_process_search_says_when_nothing_matched():
    s = read("shani/Modules/Processes/Processes.qml")
    # an empty result used to leave a blank ListView
    assert "win.shownList.length === 0" in s
    assert 'Tr.t("No process matches' in s


def test_end_confirmation_follows_the_pid_not_the_row():
    s = read("shani/Modules/Processes/Processes.qml")
    assert "property int confirmPid: -1" in s
    assert 'win.confirmPid === procRow.p.pid ? Tr.t("Tap again")' in s
    assert "TopProcesses.end(procRow.p.pid, win.endSignal)" in s
    assert "onClicked: {" in s
    # an armed confirm on a killed process must not survive a refresh
    assert "!TopProcesses.list.some(p => p.pid === win.confirmPid)" in s
    assert "property bool confirming" not in s


def test_container_actions_report_success():
    s = read("shani/Modules/Containers/ContainersWindow.qml")
    # one-shot actions previously changed the list with no positive acknowledgement
    assert 'Tr.t("%1 %2", name, verb === "stop"' in s
    assert 'Tr.t("Restarted %1", name)' in s
    assert 'Tr.t("Stopped %1", name)' in s
    # a stale note must not outlive the action that set it
    assert (
        'function run(args, after) {\n        if (act.running) return;\n        win.note = "";'
        in s
    )


def test_refresh_drops_state_for_vanished_items():
    s = read("shani/Modules/Containers/ContainersWindow.qml")
    assert "!win.containers.some(c => c.name === win.logsOf)" in s
    assert 'win.logsText = "";' in s
    assert 'win.removing !== "__prune__"' in s
    assert "!win.containers.some(c => c.name === win.removing)" in s
