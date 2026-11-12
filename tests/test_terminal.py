"""The terminal across the desktop (Services/Terminal, shani-desktop-niri).

The live part (dev/shell-parts/terminal.sh) writes, switches and reads them in a
session; these keep the pieces in other repos pointing at each other.
"""
import importlib.machinery
import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESK = ROOT.parent / "shani-pkgbuilds/shani-desktop-niri"
TERMINAL = (ROOT / "shani/Services/Terminal.qml").read_text()


def cli():
    loader = importlib.machinery.SourceFileLoader("shani_cli_t", str(ROOT / "bin/shani"))
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("shani_cli_t", loader))
    loader.exec_module(mod)
    return mod


def test_mod_return_opens_the_chosen_terminal():
    for cfg in (ROOT / "dev/niri/session.kdl", DESK / "etc/niri/config.kdl"):
        if cfg.exists():
            assert 'Mod+Return hotkey-overlay-title="Terminal" { spawn "xdg-terminal-exec"; }' in cfg.read_text(), cfg


def test_footclient_first_and_its_server_enabled():
    if not DESK.exists():
        return
    entries = [l for l in (DESK / "etc/xdg/niri-xdg-terminals.list").read_text().splitlines() if l and not l.startswith("#")]
    assert entries[:2] == ["footclient.desktop", "foot.desktop"]
    install = (DESK / "shani-desktop-niri.install").read_text()
    assert "systemctl --global enable foot-server.socket" in install
    assert "systemctl --global disable foot-server.socket" in install


def test_foot_sends_output_to_chronoa_through_the_cli():
    if not DESK.exists():
        return
    ini = (DESK / "usr/share/shani-desktop-niri/foot.ini").read_text()
    assert "pipe-command-output=[shani chronoa explain -]" in ini
    assert "pipe-selected=[shani chronoa explain -]" in ini
    mod = cli()
    assert mod.IPC_NAMES[("chronoa", "explain")] == "chronoaExplain"
    assert "function chronoaExplain(text: string)" in (ROOT / "shani/shell.qml").read_text()


def test_default_terminal_is_footclient_and_known():
    settings = (ROOT / "shani/Common/Settings.qml").read_text()
    assert 'property string terminal: "footclient"' in settings
    assert 'cmd: "footclient"' in TERMINAL and 'desktop: "footclient.desktop"' in TERMINAL


def test_writer_never_takes_a_persons_own_file():
    # the shell's mark on the first line, or exit 3 and leave it
    assert 'head -n1 "$f" | grep -qF "$mark"; then exit 3' in TERMINAL
    assert TERMINAL.count("root.mark") >= 3


def test_signals_match_foots_meaning():
    # measured on foot 1.28: SIGUSR1 -> [colors-dark], SIGUSR2 -> [colors-light]
    assert re.search(r'Theme\.dark \? "USR1" : "USR2"', TERMINAL)
