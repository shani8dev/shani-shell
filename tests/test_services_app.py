"""bridge/services.py: the person's own units and cron, with real writes.

No root is involved, so the safety is in the arguments: a unit name that is not
a unit name must be refused before systemctl sees it, and a cron entry with a
newline must be refused before crontab sees it. Everything else is pinned by
stubbing systemctl/crontab so the tests run anywhere.
"""

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location(
    "services_bridge", ROOT / "bridge/services.py"
)
sv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sv)


def run(*args):
    out = subprocess.run(
        [sys.executable, str(ROOT / "bridge/services.py"), *args],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


# ---- unit names are a trust boundary ---------------------------------------


@pytest.mark.parametrize(
    "bad",
    [
        "../etc/passwd",
        "a b",
        "a;b",
        "$(id)",
        "a\nb",
        "-x",
        "/bin/sh",
        "a&&b",
    ],
)
def test_a_name_that_is_not_a_unit_is_refused(bad):
    got = sv.cmd_unit("start", bad)
    assert got["ok"] is False


@pytest.mark.parametrize("action", ["start", "stop", "restart", "enable", "disable"])
def test_a_known_action_passes_the_name_to_systemctl(monkeypatch, action):
    called = []

    def fake(*argv, timeout=10):
        called.append(argv)
        return "", "", 0

    monkeypatch.setattr(sv, "run", fake)
    got = sv.cmd_unit(action, "shani-demo.service")
    assert got["ok"] is True
    assert called == [("systemctl", "--user", action, "shani-demo.service")]


def test_an_unknown_action_is_refused():
    assert sv.cmd_unit("rm-rf", "a.service")["ok"] is False


def test_a_systemctl_failure_is_reported_not_raised(monkeypatch):
    monkeypatch.setattr(sv, "run", lambda *a, timeout=10: ("", "Unit not found.", 5))
    got = sv.cmd_unit("start", "a.service")
    assert got["ok"] is False and "not found" in got["error"]


# ---- cron: the C and D -----------------------------------------------------


def test_cron_add_writes_the_line(monkeypatch):
    lines = []

    def fake_crontab_lines():
        return list(lines)

    def fake_write(new):
        lines[:] = new
        return {"ok": True, "error": ""}

    monkeypatch.setattr(sv, "crontab_lines", fake_crontab_lines)
    monkeypatch.setattr(sv, "cron_write", fake_write)
    got = sv.cmd_cron_add("0 9 * * 1-5", "notify-send morning")
    assert got["ok"] is True
    assert lines == ["0 9 * * 1-5 notify-send morning"]


@pytest.mark.parametrize(
    "schedule,command",
    [
        ("", "x"),
        ("0 9 * * *", ""),
        ("0 9 * * *\n* * * * *", "x"),
        ("0 9 * * *", "x\ny"),
    ],
)
def test_a_bad_cron_entry_is_refused(schedule, command):
    got = sv.cmd_cron_add(schedule, command)
    assert got["ok"] is False


def test_a_duplicate_cron_entry_is_refused(monkeypatch):
    line = "0 9 * * * true"
    monkeypatch.setattr(sv, "crontab_lines", lambda: [line])
    got = sv.cmd_cron_add("0 9 * * *", "true")
    assert got["ok"] is False and "already" in got["error"]


def test_cron_remove_drops_only_that_line(monkeypatch):
    lines = ["0 9 * * * a", "0 10 * * * b", "0 11 * * * c"]
    monkeypatch.setattr(sv, "crontab_lines", lambda: list(lines))
    written = []
    monkeypatch.setattr(
        sv, "cron_write", lambda new: written.append(new) or {"ok": True, "error": ""}
    )
    got = sv.cmd_cron_remove(1)
    assert got["ok"] is True
    assert written == [["0 9 * * * a", "0 11 * * * c"]]


@pytest.mark.parametrize("index", ["-1", "9", "abc"])
def test_an_out_of_range_cron_index_is_refused(monkeypatch, index):
    monkeypatch.setattr(sv, "crontab_lines", lambda: ["0 9 * * * a"])
    assert sv.cmd_cron_remove(index)["ok"] is False


def test_cron_reads_the_persons_crontab_only(monkeypatch):
    monkeypatch.setattr(
        sv, "run", lambda *a, timeout=10: ("0 9 * * * a\n# comment\n", "", 0)
    )
    got = sv.cmd_cron()
    assert got == [{"index": 0, "line": "0 9 * * * a"}]


# ---- the command line ------------------------------------------------------


def test_the_cli_lists_services():
    assert isinstance(run("services"), list)


def test_the_cli_lists_timers():
    assert isinstance(run("timers"), list)


def test_the_cli_lists_cron():
    assert isinstance(run("cron"), list)


def test_an_unknown_command_is_refused():
    out = subprocess.run(
        [sys.executable, str(ROOT / "bridge/services.py"), "nonsense"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 2
    assert "usage" in out.stdout
