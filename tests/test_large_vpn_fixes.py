"""Guards for the VPN client: bridge/vpn.py (nmcli JSON commands, strict
validation, graceful degradation) and its two QML surfaces, Services/Vpn.qml
and Modules/Vpn/VpnPanel.qml.
"""

import ast
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("vpn_bridge", ROOT / "bridge" / "vpn.py")
vpn = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(vpn)

SERVICE = (ROOT / "shani" / "Services" / "Vpn.qml").read_text()
PANEL = (ROOT / "shani" / "Modules" / "Vpn" / "VpnPanel.qml").read_text()


def proc(code=0, stdout="", stderr=""):
    return SimpleNamespace(returncode=code, stdout=stdout, stderr=stderr)


def test_bridge_is_stdlib_only_and_documents_secret_agent_scope():
    tree = ast.parse((ROOT / "bridge" / "vpn.py").read_text())
    mods = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            mods.update(a.name.split(".")[0] for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            mods.add(node.module.split(".")[0])
    assert mods <= set(sys.stdlib_module_names), mods
    doc = ast.get_docstring(tree)
    assert "SecretAgent" in doc and "out of scope" in doc
    for command in ("list", "up", "down", "import", "autoconnect", "stats", "delete"):
        assert f"vpn.py {command}" in doc


def test_list_filters_vpn_types_and_unescapes_colons(monkeypatch):
    calls = []

    def fake(*args):
        calls.append(args)
        return proc(
            stdout=(
                "Home VPN:vpn:activated:yes\n"
                "Wired:ethernet:activated:yes\n"
                "Work\\:VPN:wireguard:deactivated:no\n"
            )
        )

    monkeypatch.setattr(vpn, "nmcli_bin", lambda: "nmcli")
    monkeypatch.setattr(vpn, "run_nmcli", fake)
    got = vpn.cmd_list()
    assert got["ok"] is True and got["available"] is True
    assert calls[0][:2] == ("-t", "-f") and calls[0][-2:] == ("connection", "show")
    assert got["connections"] == [
        {"name": "Home VPN", "type": "vpn", "state": "activated", "autoconnect": True},
        {
            "name": "Work:VPN",
            "type": "wireguard",
            "state": "deactivated",
            "autoconnect": False,
        },
    ]


def test_list_degrades_without_nmcli(monkeypatch):
    monkeypatch.setattr(vpn, "nmcli_bin", lambda: None)

    def no_process(*args, **kwargs):
        raise AssertionError("no subprocess when nmcli is absent")

    monkeypatch.setattr(vpn.subprocess, "run", no_process)
    got = vpn.cmd_list()
    assert got["ok"] is True and got["available"] is False
    assert got["connections"] == [] and "nmcli" in got["error"]
    assert vpn.cmd_up("Any VPN")["ok"] is False


def test_list_reports_nmcli_failure(monkeypatch):
    monkeypatch.setattr(vpn, "nmcli_bin", lambda: "nmcli")
    monkeypatch.setattr(
        vpn,
        "run_nmcli",
        lambda *a: proc(4, stderr="Error: Could not connect to NetworkManager.\n"),
    )
    got = vpn.cmd_list()
    assert got["ok"] is True and got["available"] is False
    assert "Could not connect" in got["error"]


def test_names_are_validated_before_any_process(monkeypatch):
    def no_process(*args):
        raise AssertionError("invalid name reached nmcli")

    monkeypatch.setattr(vpn, "run_nmcli", no_process)
    for bad in ("", "   ", "-delete", "x\nup y", "vpn;rm -rf /", "a" * 129, None):
        with pytest.raises(vpn.VpnError):
            vpn.cmd_up(bad)
        with pytest.raises(vpn.VpnError):
            vpn.cmd_delete(bad)


def test_up_down_delete_use_argv_and_report_last_error_line(monkeypatch):
    calls = []

    def fake(*args):
        calls.append(args)
        return proc(1, stderr="Error: Connection 'Home VPN' not found.\n")

    monkeypatch.setattr(vpn, "run_nmcli", fake)
    got = vpn.cmd_up("Home VPN")
    assert got["ok"] is False and "not found" in got["error"]
    assert calls[-1] == ("connection", "up", "Home VPN")
    assert vpn.cmd_down("Home VPN")["ok"] is False
    assert calls[-1] == ("connection", "down", "Home VPN")
    assert vpn.cmd_delete("Home VPN")["ok"] is False
    assert calls[-1] == ("connection", "delete", "Home VPN")
    monkeypatch.setattr(vpn, "run_nmcli", lambda *a: proc())
    assert vpn.cmd_down("Home VPN") == {"ok": True, "error": ""}


def test_autoconnect_takes_only_yes_or_no(monkeypatch):
    calls = []
    monkeypatch.setattr(vpn, "run_nmcli", lambda *a: (calls.append(a), proc())[1])
    assert vpn.cmd_autoconnect("Home VPN", "true")["ok"] is True
    assert calls[-1] == (
        "connection",
        "modify",
        "Home VPN",
        "connection.autoconnect",
        "yes",
    )
    assert vpn.cmd_autoconnect("Home VPN", "false")["ok"] is True
    assert calls[-1][-1] == "no"
    with pytest.raises(vpn.VpnError):
        vpn.cmd_autoconnect("Home VPN", "maybe")


def test_import_copies_profile_with_safe_name_and_reloads(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))
    calls = []
    monkeypatch.setattr(vpn, "nmcli_bin", lambda: "nmcli")
    monkeypatch.setattr(vpn, "run_nmcli", lambda *a: (calls.append(a), proc())[1])
    src = tmp_path / "My VPN (1).ovpn"
    src.write_text("client\ndev tun\n")
    got = vpn.cmd_import(str(src))
    assert got["ok"] is True
    assert got["name"] == "My-VPN-1"
    dest = vpn.vpn_dir() / "My-VPN-1.ovpn"
    assert dest.read_text() == "client\ndev tun\n"
    assert dest.stat().st_mode & 0o777 == 0o600
    assert calls == [("connection", "reload")]


def test_import_rejects_bad_paths_and_never_overwrites(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))
    monkeypatch.setattr(vpn, "nmcli_bin", lambda: "nmcli")
    monkeypatch.setattr(vpn, "run_nmcli", lambda *a: proc())
    bad = tmp_path / "notes.txt"
    bad.write_text("hello")
    with pytest.raises(vpn.VpnError):
        vpn.cmd_import(str(bad))
    with pytest.raises(vpn.VpnError):
        vpn.cmd_import("relative.ovpn")
    with pytest.raises(vpn.VpnError):
        vpn.cmd_import(str(tmp_path / "missing.conf"))
    with pytest.raises(vpn.VpnError):
        vpn.cmd_import(str(tmp_path))

    prof = tmp_path / "office.conf"
    prof.write_text("[main]\n")
    assert vpn.cmd_import(str(prof))["name"] == "office"
    second = vpn.cmd_import(str(prof))
    assert second["name"] == "office-2"
    assert (vpn.vpn_dir() / "office.conf").read_text() == "[main]\n"
    assert (vpn.vpn_dir() / "office-2.conf").read_text() == "[main]\n"


def test_stats_reads_counters_uptime_and_peer(monkeypatch):
    calls = []

    def fake(*args):
        calls.append(args)
        if "device" in args:
            return proc(stdout="GENERAL.CON-UPTIME:1:02:03\nIP4.GATEWAY:10.8.0.1\n")
        return proc(
            stdout="Home VPN:vpn:activated:tun0\nWired:ethernet:activated:eth0\n"
        )

    monkeypatch.setattr(vpn, "nmcli_bin", lambda: "nmcli")
    monkeypatch.setattr(vpn, "run_nmcli", fake)
    monkeypatch.setattr(
        vpn, "_counter", lambda dev, field: 1234 if field == "rx_bytes" else 99
    )
    got = vpn.cmd_stats("Home VPN")
    assert got["ok"] is True and got["connected"] is True
    assert got["state"] == "activated" and got["device"] == "tun0"
    assert got["rxBytes"] == 1234 and got["txBytes"] == 99
    assert got["uptime"] == 3723 and got["peer"] == "10.8.0.1"
    assert calls[-1][-1] == "tun0"


def test_stats_inactive_and_unsafe_device_do_not_read_sysfs(monkeypatch):
    def no_counter(dev, field):
        raise AssertionError("sysfs read for an inactive/unsafe device")

    monkeypatch.setattr(vpn, "nmcli_bin", lambda: "nmcli")
    monkeypatch.setattr(vpn, "_counter", no_counter)
    monkeypatch.setattr(
        vpn, "run_nmcli", lambda *a: proc(stdout="Wired:ethernet:activated:eth0\n")
    )
    got = vpn.cmd_stats("Home VPN")
    assert got["connected"] is False and got["rxBytes"] == 0 and got["uptime"] == 0
    monkeypatch.setattr(
        vpn, "run_nmcli", lambda *a: proc(stdout="Home VPN:vpn:activated:../../etc\n")
    )
    got = vpn.cmd_stats("Home VPN")
    assert got["connected"] is True and got["rxBytes"] == 0


def test_stats_failure_is_json(monkeypatch):
    monkeypatch.setattr(
        vpn,
        "run_nmcli",
        lambda *a: (_ for _ in ()).throw(vpn.VpnError("nmcli is not installed")),
    )
    got = vpn.cmd_stats("Home VPN")
    assert got["ok"] is False and "nmcli" in got["error"]


def test_main_always_prints_json():
    script = str(ROOT / "bridge" / "vpn.py")
    env = dict(os.environ, PATH="/nonexistent", SHANI_VPN_NMCLI="")
    good = subprocess.run(
        [sys.executable, script, "list"], capture_output=True, text=True, env=env
    )
    assert good.returncode == 0
    assert json.loads(good.stdout)["available"] is False
    bad = subprocess.run(
        [sys.executable, script, "frobnicate"], capture_output=True, text=True, env=env
    )
    assert bad.returncode == 2 and json.loads(bad.stdout)["ok"] is False
    usage = subprocess.run(
        [sys.executable, script, "up"], capture_output=True, text=True, env=env
    )
    assert usage.returncode == 2 and "usage" in json.loads(usage.stdout)["error"]


def test_service_uses_bridge_with_busy_guard():
    for token in (
        'Quickshell.env("SHANI_VPN_TOOL")',
        '"/usr/lib/shani-shell/vpn.py"',
        "function invoke(cmd, args, subject)",
        "if (root.busy) return false;",
        '["python3", root.tool, cmd]',
        "function refreshStats(name)",
        "function importFile(path)",
        "function setAutoconnect(name, on)",
        "function remove(name)",
        "d.available !== false",
        "JSON.parse",
        "function onVpnsChanged() { root.refresh(); }",
        "SecretAgent",
    ):
        assert token in SERVICE, token


def test_panel_import_delete_stats_and_states():
    for token in (
        'FilePicker.open({ mode: "open"',
        'filters: ["ovpn", "conf"]',
        "Vpn.importFile(paths[0])",
        "standardButtons: Dialog.Cancel | Dialog.Ok",
        "Vpn.remove(panel.pendingDelete)",
        'Vpn.toggle(c.name, c.state !== "activated")',
        "Vpn.setAutoconnect(name, on)",
        "Vpn.refreshStats(active[panel.statsIndex].name)",
        "function humanBytes(n)",
        "function duration(s)",
        'Tr.t("Peer %1").arg(s.peer)',
        "enabled: !Vpn.busy",
        'objectName: "vpn-stats"',
        'Tr.t("VPN is unavailable")',
        'Tr.t("No VPN connections")',
        'visible: Vpn.error !== ""',
        "Accessible.name:",
    ):
        assert token in PANEL, token
