"""bridge/backup.py exercised for real against dev/fake-shani-backup.py.

The stand-in is the real shani-backup parser with its --json shapes and a
record of every call. Each test gets its own state and call log, so an answer
cannot leak from one check into another and the argv the bridge built is part
of the assertion, not an afterthought.
"""

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "backup.py"
FAKE = ROOT / "dev" / "fake-shani-backup.py"


@pytest.fixture
def b(tmp_path, monkeypatch):
    """A freshly loaded bridge, pointed at fresh state and call log."""
    seed = tmp_path / "state.json"
    calls = tmp_path / "calls.log"
    monkeypatch.setenv("SHANI_BACKUP_TOOL", f"{sys.executable} {FAKE}")
    monkeypatch.setenv("SHANI_BACKUP_PKEXEC", "")
    monkeypatch.setenv("SHANI_BACKUP_FAKE_STATE", str(seed))
    monkeypatch.setenv("SHANI_BACKUP_CALLS", str(calls))
    spec = importlib.util.spec_from_file_location("backup_under_test", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return SimpleNamespace(mod=mod, seed=seed, calls=calls)


def seed_with(b, **overrides):
    b.seed.write_text(json.dumps(overrides))
    return b


def logged(b):
    return b.calls.read_text().splitlines() if b.calls.exists() else []


def run_fake(*args):
    """The stand-in on its own, with throwaway state."""
    env = {
        **os.environ,
        "SHANI_BACKUP_FAKE_STATE": "/tmp/opencode-backup-standalone.json",
        "SHANI_BACKUP_CALLS": "/tmp/opencode-backup-standalone.log",
    }
    return subprocess.run(
        [sys.executable, str(FAKE), *args], capture_output=True, text=True, env=env
    )


def test_list_backups_returns_the_repository_and_calls_backups_json(b):
    assert b.mod.list_backups() == {
        "ok": True,
        "repository": "/run/media/root/USB",
        "reachable": True,
        "set_up": True,
        "schedule": {"on": True, "time": "21:15"},
        "backups": [
            {
                "id": "ab12cd34",
                "time": "2026-11-26T21:15:03+05:30",
                "paths": ["/root"],
                "size": 12345,
            }
        ],
        "restore_test": {
            "ok": True,
            "at": 1764167103,
            "snapshot": "ab12cd34",
            "file": "/root/notes.txt",
        },
    }
    assert logged(b) == ["backups --json"]


def test_backup_returns_the_final_dict_and_emits_progress(b):
    events = []
    assert b.mod.backup(emit=events.append) == {
        "ok": True,
        "snapshot": "ab12cd34",
        "restore_test": {"ok": True, "detail": "/root/notes.txt"},
        "error": "",
    }
    assert events == [
        {"progress": 12, "file": "/root/notes.txt"},
        {"progress": 58, "file": "/root/pictures/photo.jpg"},
        {"progress": 100, "file": "/root/notes.txt"},
    ]
    assert logged(b) == ["backup"]


def test_restore_passes_the_target_and_snapshot(b):
    assert b.mod.restore("/tmp/Restored/notes", "ab12cd34") == {
        "ok": True,
        "target": "/tmp/Restored/notes",
    }
    assert logged(b) == ["restore /tmp/Restored/notes --snapshot ab12cd34 --json"]


def test_snapshot_list_passes_the_path(b):
    path = "/home/.snapshots/root"
    assert b.mod.snapshot_list(path) == {
        "ok": True,
        "path": path,
        "snapshots": ["/home/.snapshots/root/daily-2026-11-26"],
        "count": 1,
        "elsewhere": 0,
        "note": None,
    }
    assert logged(b) == [f"snapshot list {path} --json"]


@pytest.mark.parametrize("readonly,extra", [(False, ""), (True, " --readonly")])
def test_snapshot_create_with_and_without_readonly(b, readonly, extra):
    assert b.mod.snapshot_create("/home", "/home/.snapshots/root/new", readonly) == {
        "ok": True,
        "source": "/home",
        "destination": "/home/.snapshots/root/new",
        "readonly": readonly,
    }
    assert logged(b) == [
        f"snapshot create /home /home/.snapshots/root/new{extra} --json"
    ]


def test_snapshot_delete_passes_the_snapshot(b):
    path = "/home/.snapshots/root/daily-2026-11-26"
    assert b.mod.snapshot_delete(path) == {"ok": True, "snapshot": path}
    assert logged(b) == [f"snapshot delete {path} --json"]


def test_home_list_returns_each_snapshot_name_and_path(b):
    assert b.mod.home_list() == {
        "ok": True,
        "user": "root",
        "snapshots": [
            {
                "name": "daily-2026-11-26",
                "path": "/home/.snapshots/root/daily-2026-11-26",
                "whole": False,
            },
            {
                "name": "manual-2026-11-25_10-00-00",
                "path": "/home/.snapshots/root/manual-2026-11-25_10-00-00",
                "whole": False,
            },
        ],
    }
    assert logged(b) == ["home list --json"]


def test_home_snapshot_returns_the_new_path(b):
    assert b.mod.home_snapshot() == {
        "ok": True,
        "path": "/home/.snapshots/root/manual-2026-11-26_10-00-00",
    }
    assert logged(b) == ["home snapshot --json"]


def test_home_remove_passes_the_name(b):
    assert b.mod.home_remove("daily-2026-11-26") == {"ok": True}
    assert logged(b) == ["home remove daily-2026-11-26 --json"]


@pytest.mark.parametrize(
    "mode,value,line,call",
    [
        ("on", "", "Daily backup on, at 21:15", "schedule --enable"),
        ("off", "", "Daily backup off", "schedule --disable"),
        ("at", "09:30", "Daily backup on, at 09:30", "schedule --at 09:30"),
    ],
)
def test_schedule_on_off_at(b, mode, value, line, call):
    assert b.mod.schedule(mode, value) == {"ok": True, "output": line}
    assert logged(b) == [call]


def test_seeded_error_reaches_the_bridge_as_the_backend_error(b):
    seed_with(b, error="backup drive is not connected")
    assert b.mod.list_backups()["ok"] is False
    assert b.mod.list_backups()["error"] == "backup drive is not connected"
    assert b.mod.home_list() == {
        "ok": False,
        "user": "root",
        "snapshots": [],
        "error": "backup drive is not connected",
    }
    assert b.mod.backup() == {
        "ok": False,
        "snapshot": "",
        "restore_test": None,
        "error": "backup drive is not connected",
    }
    assert logged(b) == [
        "backups --json",
        "backups --json",
        "home list --json",
        "backup",
    ]


def test_empty_state_is_an_empty_list_not_an_error(b):
    seed_with(b, backups=[], home_snapshots=[], snapshots=[])
    assert b.mod.list_backups()["backups"] == []
    assert b.mod.home_list()["snapshots"] == []
    listing = b.mod.snapshot_list("/home/.snapshots/root")
    assert listing["snapshots"] == [] and listing["count"] == 0
    assert logged(b) == [
        "backups --json",
        "home list --json",
        "snapshot list /home/.snapshots/root --json",
    ]


@pytest.mark.parametrize(
    "args",
    [
        ["backups", "--bogus"],
        ["frobnicate"],
        ["schedule", "--json"],
    ],
)
def test_the_fake_rejects_what_the_real_cli_rejects(args):
    r = run_fake(*args)
    assert r.returncode == 2
    assert "error:" in r.stderr


def test_main_bogus_exits_two_without_calling_the_command(b, capsys):
    assert b.mod.main(["bogus"]) == 2
    assert "usage: backup.py" in capsys.readouterr().err
    assert logged(b) == []


def test_main_rejects_a_bad_time_before_calling_the_command(b, capsys):
    # main takes sys.argv: an op word first. Without it the call is bad usage;
    # with it the bridge's own HH:MM check stops before spawning the command.
    assert b.mod.main(["schedule", "at", "99:99"]) == 2
    capsys.readouterr()
    assert b.mod.main(["backup.py", "schedule", "at", "99:99"]) == 1
    assert json.loads(capsys.readouterr().out) == {
        "ok": False,
        "error": "Time must be HH:MM",
    }
    assert logged(b) == []
