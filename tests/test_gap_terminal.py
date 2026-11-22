"""Terminal gaps: -R/-D tunnels, hosts JSON, advanced options, recents."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_tunnels_support_remote_and_dynamic_modes():
    s = read("shani/Services/TerminalApp.qml")
    assert '["L", "R", "D"].indexOf(mode)' in s
    assert '"-R"' in s and '"-D"' in s and "mode: m" in s
    w = read("shani/Modules/Terminal/TerminalAppWindow.qml")
    assert "win.tunnelMode" in w and '["L", Tr.t("Local (-L)")]' in w


def test_hosts_json_import_export():
    s = read("shani/Services/TerminalApp.qml")
    assert "function exportHosts(path)" in s and "function importHosts(path)" in s
    assert "shani-terminal-hosts.json" in s
    w = read("shani/Modules/Terminal/TerminalAppWindow.qml")
    assert 'Tr.t("Import hosts…")' in w and 'Tr.t("Export hosts…")' in w


def test_advanced_per_host_ssh_options_reach_argv():
    s = read("shani/Services/TerminalApp.qml")
    for token in (
        "proxyJump",
        "forwardAgent",
        "x11",
        "compression",
        "extraOpts",
        '"-J"',
        '"-A"',
    ):
        assert token in s
    assert "Quickshell.execDetached(sshArgs(host))" in s
    w = read("shani/Modules/Terminal/TerminalAppWindow.qml")
    assert "function hostOpts()" in w and 'Tr.t("ProxyJump' in w


def test_recents_and_connection_status():
    s = read("shani/Services/TerminalApp.qml")
    assert "lastConnected: Date.now()" in s and "recordTest(" in s
    w = read("shani/Modules/Terminal/TerminalAppWindow.qml")
    assert "function relativeTime(ms)" in w and 'Tr.t("Reachable")' in w
