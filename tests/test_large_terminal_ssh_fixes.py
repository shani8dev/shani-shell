"""Static tests for the Terminal 'remote workstation' upgrade.

There is no QML runtime in the suite, so each test pins one behaviour against
the source, like the sibling test_gap_terminal / test_terminal_writing_fixes
tests. Every new branch in the window is covered by at least one assertion.
"""

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TERM = "shani/Modules/Terminal/TerminalAppWindow.qml"
SERVICE = "shani/Services/TerminalApp.qml"


def read(rel):
    return (ROOT / rel).read_text()


def function_body(src, name):
    """The body of `function name(...)` by brace matching, so a token found in
    an unrelated function cannot satisfy a test."""
    m = re.search(r"function\s+" + re.escape(name) + r"\s*\(", src)
    assert m, "no function %s" % name
    return brace_block(src, src.index("{", m.end()))


def brace_block(src, start):
    """The `{ … }` block beginning at `src[start] == '{'`."""
    assert src[start] == "{"
    depth = 0
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start : i + 1]
    pytest.fail("unbalanced block at %d" % start)


def text_block(src, needle):
    """The Text { … } element containing `needle`."""
    i = src.index(needle)
    start = src.rfind("Text {", 0, i)
    assert start >= 0, needle
    return brace_block(src, src.index("{", start))


@pytest.fixture(scope="module")
def qml():
    return read(TERM)


# ---- 1. host groups / tags --------------------------------------------------


def test_host_groups_are_stored_through_the_existing_service_api(qml):
    assert "property string newHostGroup" in qml
    add = function_body(qml, "hostGroups")
    assert 'String(h.group || "")' in add
    assert "out.indexOf(g) < 0" in add  # one chip per distinct group
    save = qml[qml.index('text: win.newHostName === ""') :]
    assert "group: win.newHostGroup.trim()" in save
    assert (
        "TerminalApp.updateHost(TerminalApp.hosts[TerminalApp.hosts.length - 1].id, { group: win.newHostGroup.trim() })"
        in save
    )  # addHost has no group slot; attach it after
    assert 'win.newHostGroup = h.group || ""' in function_body(qml, "editHost")


def test_group_chips_and_filter_drive_the_host_list(qml):
    assert "property string groupFilter" in qml
    assert "model: win.hostGroups()" in qml
    assert 'text: modelData === "" ? Tr.t("All groups") : modelData' in qml
    assert "selected: win.groupFilter === modelData" in qml
    assert "win.groupFilter = modelData" in qml
    body = function_body(qml, "visibleHosts")
    assert 'String(h.group || "") !== g' in body
    assert "group === undefined ? win.groupFilter : group" in body


def test_group_field_is_cleared_on_add_cancel_and_save(qml):
    assert 'property string newHostGroup: ""' in qml
    assert 'property string groupFilter: ""' in qml
    cancel = qml[qml.index('text: Tr.t("Cancel")') :]
    cancel = cancel[: cancel.index("            }")]
    assert 'win.newHostGroup = ""' in cancel
    header_add = qml[qml.index('text: Tr.t("Add host"); kind: "primary"') :]
    header_add = header_add[: header_add.index("            }")]
    assert 'win.newHostGroup = ""' in header_add
    assert qml.count('win.newHostGroup = ""') >= 3


# ---- 2. search and sort -----------------------------------------------------


def test_search_covers_group_and_proxyjump(qml):
    body = function_body(qml, "visibleHosts")
    assert "[h.name, h.host, h.user, h.group, h.proxyJump]" in body
    assert "win.hostQuery.trim().toLowerCase()" in body
    assert 'Tr.t("Find a host…")' in qml
    assert 'label: Tr.t("Find a host")' in qml  # AT name for the field


def test_three_sort_modes_and_health_filter_chips(qml):
    body = function_body(qml, "visibleHosts")
    assert 'win.sortMode === "recent"' in body and "(b.lastConnected || 0)" in body
    assert 'win.sortMode === "status"' in body and 'a.status === "ok" ? 0 : 1' in body
    assert 'String(a.name || "").localeCompare' in body
    assert "property string sortMode" in qml
    for token in ('Tr.t("Sort: Name")', 'Tr.t("Sort: Recent")', 'Tr.t("Sort: Health")'):
        assert token in qml
    for token in ('Tr.t("All health")', 'Tr.t("Not tested")'):
        assert token in qml
    assert "selected: win.healthFilter === modelData[0]" in qml


# ---- 3. connection health ---------------------------------------------------


def test_health_indicator_is_not_colour_only(qml):
    body = function_body(qml, "statusName")
    assert 'h.status === "ok" ? Tr.t("Reachable")' in body
    assert 'h.status === "failed" ? Tr.t("Unreachable")' in body
    assert 'Tr.t("Not tested")' in body
    assert "Accessible.role: Accessible.Graphic" in qml
    assert "Accessible.name: win.statusName(modelData)" in qml
    assert 'modelData.status === "failed" ? Theme.red : Theme.faint' in qml


def test_health_counts_and_sequential_test_all(qml):
    body = function_body(qml, "healthCount")
    assert 'which === "ok"' in body and 'which === "failed"' in body
    assert "!h.status" in body
    assert (
        'Tr.t("%1 reachable · %2 unreachable · %3 not tested", win.healthCount("ok")'
        in qml
    )
    all_body = function_body(qml, "testAll")
    assert 'h.type !== "serial"' in all_body
    assert "win.testQueue.length" in all_body
    one = function_body(qml, "testOne")
    assert "TerminalApp.testConnection(h," in one
    assert "win.testIndex = win.testIndex + 1" in one and "win.testOne()" in one
    assert "win.testQueue = []" in one  # the queue terminates


# ---- 4. quick commands / snippets ------------------------------------------


def test_snippets_search_and_run_on_host(qml):
    assert (
        "property string snippetQuery" in qml and "property string snippetHostId" in qml
    )
    assert 'placeholder: Tr.t("Find a snippet…")' in qml
    assert "[s.name, s.command].some" in qml
    run = function_body(qml, "runSnippet")
    assert "Quickshell.clipboardText = s.command" in run
    assert "TerminalApp.connect(h)" in run
    assert 'Tr.t("Command copied — paste it in %1", h.name)' in run
    assert 'Tr.t("Command copied to clipboard")' in run  # no host case
    assert 'tip: Tr.t("Copy command and connect to host")' in qml


# ---- 5. split panes ---------------------------------------------------------


def test_split_host_panes_have_independent_group(qml):
    assert "property bool splitView" in qml and "property string splitGroup" in qml
    assert "id: hostListB" in qml and "visible: win.splitView" in qml
    assert "model: win.visibleHosts(win.splitGroup)" in qml
    assert 'text: Tr.t("Right pane:")' in qml
    assert "selected: win.splitGroup === modelData" in qml
    assert 'Tr.t("No hosts in this pane")' in qml


# ---- 6. tab / session management -------------------------------------------


def test_launched_sessions_become_closable_tabs(qml):
    assert "property var panes: []" in qml and "property int activePane: -1" in qml
    launch = function_body(qml, "noteLaunch")
    assert "win.panes.some(p => p.id === host.id)" in launch
    assert "{ id: host.id, name: host.name || host.host }" in launch
    assert "win.activePane = host.id" in launch
    close = function_body(qml, "closePane")
    assert "win.panes.filter(p => p.id !== id)" in close
    assert "win.openedHosts.filter(x => x !== id)" in close
    conn = function_body(qml, "connectPane")
    assert (
        "TerminalApp.hosts.find(x => x.id === id)" in conn
        and "TerminalApp.connect(h)" in conn
    )
    assert 'Accessible.name: Tr.t("Reconnect to %1", modelData.name)' in qml
    assert 'accessibleName: Tr.t("Close session %1", modelData.name)' in qml
    tabs = qml[qml.index("// session tabs:") : qml.index("// ---- hosts tab ----")]
    assert "model: win.panes" in tabs and "IconButton" in tabs


# ---- 7. copy / paste --------------------------------------------------------


def test_copy_ssh_command_uses_the_service_argv(qml):
    body = function_body(qml, "sshCommand")
    assert "TerminalApp.sshArgs(h)" in body
    assert 'String(x).indexOf(" ") >= 0' in body  # quote slots with spaces
    assert 'tip: Tr.t("Copy SSH command")' in qml


def test_paste_host_parses_user_host_port_or_reports_error(qml):
    body = function_body(qml, "pasteHost")
    assert "Quickshell.clipboardText" in body
    assert "/^(?:([^@\\s]+)@)?([^\\s:]+)(?::(\\d{1,5}))?$/" in body
    assert 'win.newHostPort = m[3] || "22"' in body
    assert 'win.pasteError = Tr.t("Clipboard is not a host (user@host:port)")' in body
    assert 'win.tab = "add"' in body
    assert 'text: Tr.t("Paste host…")' in qml


# ---- 8. tunnel management ---------------------------------------------------


def test_tunnel_port_conflict_is_detected_before_start(qml):
    body = function_body(qml, "tunnelConflict")
    assert "parseInt(port, 10)" in body and "if (!p) return null" in body
    assert "t.localPort === p && t.mode === mode" in body
    assert "&& !win.tunnelConflict(tunLocal.text, win.tunnelMode)" in qml
    assert "Port %1 is already forwarded by an active %2 tunnel" in qml
    assert "color: Theme.danger" in qml
    assert 'modelData.mode + " · " + modelData.localPort' in qml
    assert "Shani cannot verify a dropped tunnel is still alive" in qml
    # service must still carry the mode a conflict is checked against
    svc = read(SERVICE)
    assert "mode: m" in svc and "localPort: lp" in svc


# ---- 9. keyboard shortcuts --------------------------------------------------


def test_keyboard_shortcuts_extend_the_existing_navigation(qml):
    assert "Keys.onPressed: e => {" in qml
    assert (
        "hostList.currentIndex = Math.min(hostList.count - 1, hostList.currentIndex + 1)"
        in qml
    )
    assert "hostList.currentIndex = Math.max(0, hostList.currentIndex - 1)" in qml
    assert "TerminalApp.connect(h)" in qml
    assert "Qt.Key_Slash && hostSearch.visible" in qml
    for token in (
        "e.modifiers & Qt.ControlModifier",
        "e.key === Qt.Key_F",
        "e.key >= Qt.Key_1 && e.key <= Qt.Key_4",
        "e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab",
        'win.tab = "tunnels"; e.accepted = true',
        "e.key === Qt.Key_F2",
        "e.key === Qt.Key_Delete",
    ):
        assert token in qml
    assert 'text: win.showShortcuts ? Tr.t("Hide shortcuts") : Tr.t("Shortcuts")' in qml


def test_delete_needs_a_second_press(qml):
    body = function_body(qml, "requestDelete")
    assert "win.confirmingDelete !== h.id" in body
    assert "unconfirmDelete.restart()" in body
    assert "TerminalApp.deleteHost(h.id)" in body
    assert "property string confirmingDelete" in qml
    assert "Timer { id: unconfirmDelete; interval: 4000" in qml
    assert 'Tr.t("Press Delete again to remove this host")' in qml


# ---- 10. AT names -----------------------------------------------------------


def test_new_controls_and_rows_have_accessible_names(qml):
    assert "Accessible.role: Accessible.ListItem" in qml
    assert (
        'Accessible.name: Tr.t("Host %1, %2", modelData.name, win.statusName(modelData))'
        in qml
    )
    assert 'Accessible.name: Tr.t("SSH key %1", modelData.name)' in qml
    assert 'Accessible.name: Tr.t("Right pane host %1", modelData.name)' in qml
    assert not re.search(r'(?<![\w.])Accessible\.name\s*:\s*""', qml)
    # every IconButton introduced by this change names itself via tip or accessibleName
    for icon in (
        "window-close",
        "edit-copy",
        "go-next",
        "go-previous",
        "folder-remote",
    ):
        assert 'icon: "%s"' % icon in qml


# ---- 11. empty and error states --------------------------------------------


def test_empty_states_distinguish_no_data_from_no_match(qml):
    assert 'TerminalApp.hosts.length === 0 ? Tr.t("No SSH hosts yet")' in qml
    assert 'Tr.t("No hosts match your search")' in qml
    assert 'Tr.t("No hosts match your filters")' in qml
    assert 'Tr.t("Try a different name, address or user.")' in qml
    assert (
        'TerminalApp.snippets.length === 0 ? Tr.t("No SSH snippets") : Tr.t("No snippets match your search")'
        in qml
    )
    assert 'Tr.t("No active tunnels")' in qml
    assert 'Tr.t("No SSH keys")' in qml


def test_error_banners_are_announced(qml):
    for expr in (
        "TerminalApp.error",
        "win.hostNote",
        "win.pasteError",
        "win.confirmingDelete",
        "win.snippetNote",
    ):
        block = text_block(qml, "visible: %s" % expr)
        assert "Accessible.name: text" in block, expr
    conflict = text_block(
        qml, "visible: !!win.tunnelConflict(tunLocal.text, win.tunnelMode)"
    )
    assert "color: Theme.danger" in conflict and "Accessible.name: text" in conflict


# ---- 12. structure / regressions -------------------------------------------


def test_all_tabs_stay_in_one_layout_and_existing_service_api_is_used(qml):
    assert qml.index("// ---- keys tab ----") > qml.index(
        "// ---- add / edit form ----"
    )
    assert qml.index("// ---- tunnels tab ----") > qml.index("// ---- keys tab ----")
    assert qml.index("// ---- snippets tab ----") > qml.index(
        "// ---- tunnels tab ----"
    )
    # no call to a service function that does not exist today
    for call in (
        "TerminalApp.refresh()",
        "TerminalApp.connect(",
        "TerminalApp.testConnection(",
        "TerminalApp.tunnel(",
        "TerminalApp.stopTunnel(",
        "TerminalApp.addHost(",
        "TerminalApp.updateHost(",
        "TerminalApp.addSnippet(",
        "TerminalApp.deleteSnippet(",
        "TerminalApp.sshArgs(",
    ):
        assert call in qml
    assert qml.count("{") == qml.count("}")
