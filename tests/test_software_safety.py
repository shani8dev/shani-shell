"""Software-window safety: confirmed bulk updates, held-back updates, catalogue age."""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "appstore.py"
QML = ROOT / "shani" / "Modules" / "Software" / "SoftwareWindow.qml"
FIXTURE = ROOT / "tests" / "fixtures" / "appstream.xml"

# two apps with updates, so "update-all" has something to exclude
FAKE = r"""#!/bin/sh
echo "$*" >> "$T/calls"
case "$1 $2" in
  "list --app") case "$3" in
      --columns=application) printf 'org.example.Notes\norg.example.Game\n' ;;
      *) printf 'org.example.Notes\tNotes\t1.2\tflathub\tuser\t12.0 MB\norg.example.Game\tGame\t2.0\tflathub\tuser\t20.0 MB\n' ;;
    esac ;;
  "remote-ls --updates") printf 'org.example.Notes\norg.example.Game\n' ;;
  "update -y") echo "Updating" ;;
esac
"""


def load(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path / "cache"))
    (tmp_path / "home").mkdir(exist_ok=True)
    name = "appstore_safety"
    loader = importlib.machinery.SourceFileLoader(name, str(BRIDGE))
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(mod)
    return mod


def cli(tmp_path, *args):
    fake = tmp_path / "flatpak"
    if not fake.exists():
        fake.write_text(FAKE)
        fake.chmod(0o755)
    env = dict(
        os.environ,
        SHANI_FLATPAK=str(fake),
        T=str(tmp_path),
        HOME=str(tmp_path / "home"),
        XDG_CACHE_HOME=str(tmp_path / "cache"),
        SHANI_APPSTREAM=str(FIXTURE),
    )
    (tmp_path / "home").mkdir(exist_ok=True)
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *args], capture_output=True, text=True, env=env
    )
    lines = [json.loads(line) for line in r.stdout.splitlines() if line.strip()]
    return lines[0] if len(lines) == 1 else lines


def test_update_all_is_confirmed_and_shows_its_scope():
    w = QML.read_text()
    # exactly one launch site, behind a two-tap confirm (the window's Remove pattern)
    assert w.count('runJob(["update-all"]') == 1
    assert "onConfirmed:" in w and "runJob(" in w
    assert 'Tr.t("Click again to update all")' in w and 'Tr.t("Update all")' in w
    assert 'Tr.t("Update %1 apps:", win.updates)' in w
    assert 'Tr.t("Total size: %1", win.updateSize())' in w
    assert "id: updateAllConfirm" in w and "interval: 4000" in w


def test_skip_version_is_persisted_and_hides_the_update(tmp_path):
    assert [a["update"] for a in cli(tmp_path, "installed")] == [True, True]

    assert cli(tmp_path, "skip", "org.example.Notes", "on") == ["org.example.Notes"]
    assert cli(tmp_path, "skipped") == ["org.example.Notes"]
    assert [a["update"] for a in cli(tmp_path, "installed")] == [
        True,
        False,
    ]  # Game, Notes

    cli(tmp_path, "update-all")
    calls = (tmp_path / "calls").read_text()
    assert "update -y --noninteractive org.example.Game" in calls
    assert "org.example.Notes" not in calls.split("update -y")[-1]

    # and it can be undone when a fixed version arrives
    cli(tmp_path, "skip", "org.example.Notes", "off")
    assert cli(tmp_path, "skipped") == []
    assert [a["update"] for a in cli(tmp_path, "installed")] == [True, True]
    assert "skippedIds" in QML.read_text() and "Skip this version" in QML.read_text()


def test_catalogue_age_is_exposed_and_shown(tmp_path, monkeypatch):
    cat = tmp_path / "appstream.xml"
    cat.write_text("<components/>")
    old = time.time() - 10 * 86400
    os.utime(cat, (old, old))
    monkeypatch.setenv("SHANI_APPSTREAM", str(cat))
    out = load(tmp_path, monkeypatch).catalogue()
    assert out["refreshed"] and out["ageDays"] >= 9

    w = QML.read_text()
    assert 'ask(["catalogue"]' in w
    assert 'Tr.t("Catalogue refreshed %1", win.catalogue.refreshed)' in w
    assert "Net.online" in w and "Offline" in w
