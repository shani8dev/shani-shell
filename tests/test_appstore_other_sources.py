"""bridge/appstore.py's other ways in, as shani-docs' software pages do them:
command-line tools from Nix (the nixpkgs channel added the first time, then
nix-env -iA) and the Snap Store (find, list, install with --classic when a snap
needs it, refresh) - run for real against stand-in nix-env, nix-channel, snap."""
import json
import os
import subprocess
import sys
from pathlib import Path

BRIDGE = Path(__file__).resolve().parent.parent / "bridge" / "appstore.py"

SNAP = r'''#!/bin/sh
echo "snap $*" >> "$T/calls"
case "$1" in
find) printf 'Name      Version  Publisher        Notes    Summary\nobsidian  1.7.7    obsidianmd       classic  Markdown notes\nspotify   1.2      spotify✓         -        Music for everyone\n' ;;
list) printf 'Name      Version  Rev  Tracking  Publisher   Notes\ncore22    2024     1    latest    canonical✓  base\nsnapd     2.6      2    latest    canonical✓  snapd\nspotify   1.2      9    latest    spotify✓    -\n' ;;
refresh) if [ "$2" = "--list" ]; then printf 'Name     Version  Rev  Size  Publisher  Notes\nspotify  1.3      10   1MB   spotify✓   -\n'; else echo "spotify 1.3 refreshed"; fi ;;
install) echo "obsidian installed" ;;
esac
'''
NIXENV = r'''#!/bin/sh
echo "nix-env $*" >> "$T/calls"
case "$1" in
-q) if [ -f "$T/have" ]; then echo '{"x":{"pname":"ripgrep"}}'; else echo '{}'; fi ;;
-iA) touch "$T/have"; echo "installing 'ripgrep-14.1.0'" ;;
esac
'''
NIXCHAN = r'''#!/bin/sh
echo "nix-channel $*" >> "$T/calls"
case "$1" in --list) [ -f "$T/chan" ] && echo "nixpkgs https://nixos.org/channels/nixpkgs-unstable" ;; --add) touch "$T/chan" ;; esac
exit 0
'''


def run(tmp_path, *args):
    for name, body in (("snap", SNAP), ("nix-env", NIXENV), ("nix-channel", NIXCHAN)):
        f = tmp_path / name
        if not f.exists():
            f.write_text(body); f.chmod(0o755)
    (tmp_path / "home").mkdir(exist_ok=True)
    env = dict(os.environ, T=str(tmp_path), HOME=str(tmp_path / "home"), XDG_CACHE_HOME=str(tmp_path / "cache"),
               SHANI_SNAP=str(tmp_path / "snap"), SHANI_NIX_ENV=str(tmp_path / "nix-env"),
               SHANI_NIX_CHANNEL=str(tmp_path / "nix-channel"),
               PATH=str(tmp_path) + ":/usr/bin:/bin")
    r = subprocess.run([sys.executable, str(BRIDGE), *args], capture_output=True, text=True, env=env, timeout=60)
    lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
    return lines, r.returncode


def calls(tmp_path):
    return (tmp_path / "calls").read_text().splitlines()


def test_snap_search_reads_the_store_table(tmp_path):
    [r], rc = run(tmp_path, "snap-search", "notes")
    assert rc == 0
    assert r[0] == {"name": "obsidian", "version": "1.7.7", "publisher": "obsidianmd", "summary": "Markdown notes", "classic": True}
    assert r[1]["publisher"] == "spotify" and r[1]["classic"] is False   # the verified mark is not part of the name


def test_installed_snaps_skip_what_snapd_runs_on_and_show_updates(tmp_path):
    [r], _ = run(tmp_path, "snap-installed")
    assert [s["name"] for s in r] == ["spotify"]
    assert r[0]["update"] is True


def test_a_classic_snap_installs_with_classic(tmp_path):
    out, rc = run(tmp_path, "snap-install", "obsidian", "classic")
    assert rc == 0 and out[-1] == {"ok": True}
    assert "snap install obsidian --classic" in calls(tmp_path)


def test_a_bad_snap_name_is_refused(tmp_path):
    out, rc = run(tmp_path, "snap-remove", "x; rm -rf ~")
    assert rc != 0 and not (tmp_path / "calls").exists()


def test_nix_first_install_adds_the_channel_then_installs(tmp_path):
    [tools], _ = run(tmp_path, "nix-tools")
    rg = next(t for t in tools if t["attr"] == "ripgrep")
    assert rg["nix"] is False
    assert "docker" not in [t["attr"] for t in tools]        # a system service: the Containers app's job
    out, rc = run(tmp_path, "nix-install", "ripgrep")
    assert rc == 0 and out[-1] == {"ok": True}
    c = calls(tmp_path)
    assert c.index("nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs") < c.index("nix-env -iA nixpkgs.ripgrep")
    assert "nix-channel --update" in c
    [tools], _ = run(tmp_path, "nix-tools")
    assert next(t for t in tools if t["attr"] == "ripgrep")["nix"] is True
    # the channel is added once
    run(tmp_path, "nix-install", "ripgrep")
    assert calls(tmp_path).count("nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs") == 1


def test_nix_refuses_a_name_that_is_not_a_package(tmp_path):
    out, rc = run(tmp_path, "nix-install", "ripgrep; reboot")
    assert rc != 0 and out[-1]["error"]
