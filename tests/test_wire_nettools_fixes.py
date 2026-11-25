"""Static checks for the cross-wiring that makes Network Tools reachable from
Terminal, Maps and Files. Each of the four QML surfaces needs a running shell
to render, so these are source-level assertions (as in test_utilities2.py).

Because Ui.qml and shell.qml are not owned by this change, no new Ui flag or
signal was added: a "shani-nettools:<host>" clipboard marker carries the host
and Ui.netTools (the flag shell.qml's netToolsOpen() sets) opens the window.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_terminal_ping_dns_hands_the_host_to_nettools():
    t = source("shani/Modules/Terminal/TerminalAppWindow.qml")
    # documented clipboard handoff, since no Ui flag is owned here
    assert "do not own the Ui singleton" in t and "shell.qml" in t
    assert "function openNetTools(host)" in t
    assert 'Quickshell.clipboardText = "shani-nettools:" + h;' in t
    assert "Ui.netTools = true;" in t
    # a per-host action in both the pinned and the full host list
    assert t.count('Tr.t("Ping / DNS")') >= 2
    assert "onClicked: win.openNetTools(modelData.host)" in t


def test_maps_check_host_hands_the_place_domain_to_nettools():
    m = source("shani/Modules/Maps/MapsPanel.qml")
    assert "function checkHostTarget()" in m
    assert "function checkHost()" in m
    assert "win.placeWebsite" in m
    assert "win.hostFromText(win.tileUrl)" in m  # current-location fallback
    assert "Location.available" in m
    assert 'text: Tr.t("Check host")' in m
    assert "onClicked: win.checkHost()" in m
    assert 'Quickshell.clipboardText = "shani-nettools:" + h;' in m
    assert "Ui.netTools = true;" in m


def test_files_network_tools_handles_share_paths_and_desktop_urls():
    f = source("shani/Modules/Files/FilesPanel.qml")
    assert "function networkPathHost()" in f
    assert "/^(smb|nfs|cifs|sftp|ssh):\\/\\//i.test(Files.path)" in f
    assert "readonly property bool desktopSelected" in f
    assert "function checkNetworkHost()" in f
    assert "desktopUrlProc" in f
    assert 'grep -m1 "^URL=" "$1"' in f
    assert 'text: Tr.t("Network tools")' in f
    assert "onClicked: win.checkNetworkHost()" in f
    assert 'Quickshell.clipboardText = "shani-nettools:" + h;' in f


def test_nettools_reads_the_handoff_keeps_per_tool_history_and_copies_all():
    n = source("shani/Modules/NetTools.qml")
    # prefill on open, marker-gated so arbitrary clipboard text is ignored
    assert "function takeHandoff()" in n
    assert 'const marker = "shani-nettools:"' in n
    assert "raw.slice(marker.length)" in n
    assert "win.validHost(host)" in n
    assert "Component.onCompleted: win.takeHandoff()" in n
    assert "onVisibleChanged: if (visible) win.takeHandoff()" in n
    # per-tool history, with the flat history kept for existing callers
    assert "property var toolHistory: ({})" in n
    assert "function historyFor(tool)" in n
    assert "win.addToolHistory(kind, target);" in n
    assert "model: win.historyFor(win.tool)" in n
    # "Copy all" works before any results exist (the handoff case)
    assert "function copyAll()" in n
    assert "win.copyResults();" in n
    assert "onClicked: win.copyAll()" in n
