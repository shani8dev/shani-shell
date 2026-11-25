"""`shani install node` / `shani update` (and their aliases), run for real: the
CLI over the same bridge as the Software window, with stand-in flatpak, snap,
nix-env, nix-channel, pkexec and shani-deploy recording what they were asked."""
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "bin" / "shani"
REC = '#!/bin/sh\necho "%s $*" >> "$T/calls"\n'
FAKES = {
    "flatpak": REC % "flatpak" + 'case "$1 $2" in "list --app") ;; "remote-ls --updates") ;; esac\n',
    "snap": REC % "snap" + 'case "$1" in list) printf "Name Version Rev Tracking Publisher Notes\\n";; esac\n',
    "nix-env": REC % "nix-env" + 'case "$1" in -q) echo "{}";; esac\n',
    "nix-channel": REC % "nix-channel" + 'case "$1" in --list) echo "nixpkgs https://x";; esac\n',
    "pkexec": REC % "pkexec" + 'exec "$@"\n',
    "shani-deploy": REC % "shani-deploy" + 'case "$1" in --status) echo \'{"update_available": true}\';; esac\n',
}


def shani(tmp_path, *args):
    for name, body in FAKES.items():
        f = tmp_path / name
        if not f.exists():
            f.write_text(body); f.chmod(0o755)
    (tmp_path / "home").mkdir(exist_ok=True)
    env = dict(os.environ, T=str(tmp_path), HOME=str(tmp_path / "home"), XDG_CACHE_HOME=str(tmp_path / "cache"),
               PATH=str(tmp_path) + ":/usr/bin:/bin", SHANI_APPSTORE_TOOL=str(ROOT / "bridge" / "appstore.py"),
               SHANI_FLATPAK=str(tmp_path / "flatpak"), SHANI_SNAP=str(tmp_path / "snap"),
               SHANI_NIX_ENV=str(tmp_path / "nix-env"), SHANI_NIX_CHANNEL=str(tmp_path / "nix-channel"),
               SHANI_APPSTREAM=str(ROOT / "tests" / "fixtures" / "appstream.xml"))
    r = subprocess.run([sys.executable, str(CLI), *args], capture_output=True, text=True, env=env, timeout=60)
    c = (tmp_path / "calls").read_text().splitlines() if (tmp_path / "calls").exists() else []
    return r, c


def test_install_node_is_a_nix_command_line_tool(tmp_path):
    r, calls = shani(tmp_path, "install", "node")
    assert r.returncode == 0, r.stderr
    assert "nix-env -iA nixpkgs.nodejs" in calls
    assert not any(c.startswith("flatpak install") for c in calls)


def test_install_an_app_by_its_flathub_name_is_a_flatpak(tmp_path):
    r, calls = shani(tmp_path, "add", "Notes")          # the fixture catalogue's app, by name
    assert r.returncode == 0, r.stderr
    assert any(c.startswith("flatpak install -y --noninteractive flathub org.example.Notes") for c in calls)


def test_update_is_the_apps_and_names_a_waiting_os_upgrade(tmp_path):
    r, calls = shani(tmp_path, "update")
    assert r.returncode == 0, r.stderr
    assert any(c.startswith("snap refresh") for c in calls)
    assert "pkexec shani-deploy" not in calls
    assert "shani upgrade" in r.stdout          # the fake deploy says one is out


def test_upgrade_is_shani_deploy_and_leaves_the_apps(tmp_path):
    r, calls = shani(tmp_path, "upgrade")
    assert r.returncode == 0, r.stderr
    assert "pkexec shani-deploy" in calls
    assert not any(c.startswith(("snap", "flatpak update")) for c in calls)


def test_update_all_does_both(tmp_path):
    r, calls = shani(tmp_path, "update", "--all")
    assert "pkexec shani-deploy" in calls and any(c.startswith("snap refresh") for c in calls)


def test_checks_change_nothing(tmp_path):
    for verb in ("update", "upgrade"):
        r, calls = shani(tmp_path, verb, "--check")
        assert r.returncode == 0, r.stderr
        assert "pkexec shani-deploy" not in calls
        assert not any(c.startswith(("snap refresh", "flatpak update")) for c in calls if "--list" not in c)
