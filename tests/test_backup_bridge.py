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
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "backup.py"
FAKE = ROOT / "dev" / "fake-shani-backup.py"
FAKE_SYSTEMCTL = ROOT / "dev" / "fake-systemctl-user.py"
TIMER = "shani-backup-home.timer"


@pytest.fixture
def b(tmp_path, monkeypatch):
    """A freshly loaded bridge, pointed at fresh state and call log."""
    seed = tmp_path / "state.json"
    calls = tmp_path / "calls.log"
    compose = tmp_path / "compose"
    compose.mkdir()
    monkeypatch.setenv("SHANI_BACKUP_TOOL", f"{sys.executable} {FAKE}")
    monkeypatch.setenv("SHANI_BACKUP_PKEXEC", "")
    monkeypatch.setenv("SHANI_BACKUP_FAKE_STATE", str(seed))
    monkeypatch.setenv("SHANI_BACKUP_CALLS", str(calls))
    monkeypatch.setenv("FAKE_COMPOSE", str(compose))
    monkeypatch.setenv("SHANI_SYSTEMCTL_USER", f"{sys.executable} {FAKE_SYSTEMCTL}")
    spec = importlib.util.spec_from_file_location("backup_under_test", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return SimpleNamespace(mod=mod, seed=seed, calls=calls, compose=compose)


def seed_with(b, **overrides):
    b.seed.write_text(json.dumps(overrides))
    return b


def logged(b):
    return b.calls.read_text().splitlines() if b.calls.exists() else []


def systemctl_logged(b):
    path = b.compose / "calls"
    return path.read_text().splitlines() if path.exists() else []


def seed_timer(b, enabled=True, active=True, next_usec=1764167103000000):
    (b.compose / "units.json").write_text(
        json.dumps(
            {
                TIMER: {"enabled": enabled, "active": active, "next": next_usec},
            }
        )
    )
    return b


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
        "stale": False,
        "newest": "2026-11-26T21:15:03+05:30",
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


# ---- derived backup state: restore test and a stale newest backup -------------


def test_backup_status_uses_a_three_day_boundary(b):
    now = datetime(2026, 11, 26, 12, tzinfo=timezone.utc)
    old = (now - timedelta(days=3)).isoformat()
    recent = (now - timedelta(days=2, hours=23)).isoformat()
    assert b.mod.backup_status([{"time": old}], now=now) == {
        "stale": True,
        "newest": old,
    }
    assert b.mod.backup_status([{"time": recent}], now=now) == {
        "stale": False,
        "newest": recent,
    }
    assert b.mod.backup_status([], now=now) == {"stale": True, "newest": ""}


def test_list_backups_flags_an_old_newest_backup(b):
    old = "2026-11-01T10:00:00+00:00"
    seed_with(b, backups=[{"id": "old", "time": old, "paths": [], "size": 1}])
    result = b.mod.list_backups()
    assert result["stale"] is True
    assert result["newest"] == old
    assert result["restore_test"]["ok"] is True


def test_list_backups_can_carry_a_failed_restore_test(b):
    seed_with(
        b, restore_test={"ok": False, "at": 1, "snapshot": "ab12cd34", "file": ""}
    )
    assert b.mod.list_backups()["restore_test"] == {
        "ok": False,
        "at": 1,
        "snapshot": "ab12cd34",
        "file": "",
    }


# ---- the daily snapshot timer is a user unit, never pkexec --------------------

NEXT_USEC = 1764167103000000
NEXT_TEXT = datetime.fromtimestamp(NEXT_USEC / 1_000_000).strftime("%Y-%m-%d %H:%M")


def test_home_timer_state_reads_the_user_timer_with_exact_argv(b):
    seed_timer(b)
    assert b.mod.home_timer_state() == {
        "ok": True,
        "enabled": True,
        "active": True,
        "next": NEXT_TEXT,
    }
    assert systemctl_logged(b) == [f"systemctl-user --user show {TIMER}"]


def test_home_timer_enable_and_disable_use_enable_now_without_root(b):
    seed_timer(b, enabled=False, active=False, next_usec=0)
    assert b.mod.home_timer(True) == {"ok": True, "output": "enabled"}
    assert b.mod.home_timer_state() == {
        "ok": True,
        "enabled": True,
        "active": True,
        "next": "",
    }
    assert b.mod.home_timer(False) == {"ok": True, "output": "disabled"}
    assert b.mod.home_timer_state() == {
        "ok": True,
        "enabled": False,
        "active": False,
        "next": "",
    }
    assert systemctl_logged(b) == [
        f"systemctl-user --user enable --now {TIMER}",
        f"systemctl-user --user show {TIMER}",
        f"systemctl-user --user disable --now {TIMER}",
        f"systemctl-user --user show {TIMER}",
    ]


def test_the_systemctl_standin_rejects_verbs_systemctl_does_not_have(b):
    env = {**os.environ, "FAKE_COMPOSE": str(b.compose)}
    for args, expected in (
        (["--user", "frobnicate", TIMER], "unknown command"),
        (["--user", "show", "-p", "Unknown", TIMER], "unsupported show"),
        (["frobnicate", TIMER], "only --user"),
    ):
        r = subprocess.run(
            [sys.executable, str(FAKE_SYSTEMCTL), *args],
            capture_output=True,
            text=True,
            env=env,
            timeout=5,
        )
        assert r.returncode != 0
        assert expected in r.stderr


def test_main_rejects_an_unknown_timer_mode(b, capsys):
    assert b.mod.main(["backup.py", "home-timer", "maybe"]) == 2
    assert "usage: backup.py" in capsys.readouterr().err
    assert systemctl_logged(b) == []


# ---- disk space and finding a file in snapshots -------------------------------


def test_disk_usage_reports_bytes_and_a_low_free_warning(b):
    class V:
        f_frsize = 4096
        f_blocks = 1000
        f_bfree = 50
        f_bavail = 50

    seen = []

    def statvfs(path):
        seen.append(path)
        return V()

    result = b.mod.disk_usage("/home/.snapshots", statvfs=statvfs)
    assert result == {
        "ok": True,
        "total": 4096000,
        "free": 204800,
        "used": 3891200,
        "low": True,
    }
    assert seen == ["/home/.snapshots"]


def test_disk_usage_rejects_a_missing_path_and_a_bad_filesystem(b):
    assert b.mod.disk_usage("") == {"ok": False, "error": "Give a folder to check"}

    def broken(path):
        raise OSError("no such folder")

    assert b.mod.disk_usage("/nope", statvfs=broken) == {
        "ok": False,
        "error": "no such folder",
    }


def test_find_file_walks_snapshots_skips_hidden_dedupes_and_uses_home_list(b, tmp_path):
    snap = tmp_path / "daily"
    (snap / ".cache").mkdir(parents=True)
    (snap / "sub").mkdir()
    (snap / "notes.txt").write_text("a note")
    (snap / "sub" / "notes.txt").write_text("a note")
    (snap / ".cache" / "notes.txt").write_text("hidden")
    seed_with(b, home_snapshots=[{"name": "daily", "path": str(snap), "whole": False}])

    result = b.mod.find_in_snapshots("NOT")
    assert result["ok"] is True and result["truncated"] is False
    assert [row["name"] for row in result["results"]] == ["notes.txt"]
    assert result["results"][0]["path"] == str(snap / "notes.txt")
    assert result["results"][0]["size"] == 6
    assert logged(b) == ["home list --json"]


def test_find_file_caps_results_and_rejects_a_short_query(b, tmp_path):
    snap = tmp_path / "daily"
    snap.mkdir(parents=True)
    for i in range(61):
        path = snap / f"note-{i:02}.txt"
        path.write_text(str(i))
        os.utime(path, (1_700_000_000 + i, 1_700_000_000 + i))
    seed_with(b, home_snapshots=[{"name": "daily", "path": str(snap), "whole": False}])

    result = b.mod.find_in_snapshots("note")
    assert result["ok"] is True
    assert len(result["results"]) == b.mod.FIND_LIMIT
    assert result["truncated"] is True
    assert b.mod.find_in_snapshots("n") == {
        "ok": False,
        "error": "Type at least two letters",
        "results": [],
    }
    assert logged(b) == ["home list --json"]


def test_main_exposes_disk_and_find_ops_without_scattered_calls(b, tmp_path, capsys):
    snap = tmp_path / "daily"
    snap.mkdir(parents=True)
    (snap / "notes.txt").write_text("a note")
    seed_with(b, home_snapshots=[{"name": "daily", "path": str(snap), "whole": False}])

    assert b.mod.main(["backup.py", "disk-usage", str(snap)]) == 0
    assert json.loads(capsys.readouterr().out)["ok"] is True
    assert b.mod.main(["backup.py", "find-file", "notes"]) == 0
    found = json.loads(capsys.readouterr().out)
    assert found["results"][0]["name"] == "notes.txt"
    assert b.mod.main(["backup.py", "find-file", "n"]) == 1
    assert json.loads(capsys.readouterr().out)["ok"] is False
    assert logged(b) == ["home list --json"]
