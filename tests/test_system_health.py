"""bridge/system_health.py against dev/fake-shani-health.py: the tool's own words
mapped to pass/warn/fail/info, both report shapes, no invented checks, and an
honest answer when the tool is missing or the JSON is unusable."""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_health.py"
FAKE = ROOT / "dev" / "fake-shani-health.py"


def run(tmp_path, *args, tool="shani-health", tool_args="--verify --json", extra=None):
    link = tmp_path / "shani-health"
    if not link.exists():
        link.symlink_to(FAKE)
    env = dict(
        os.environ,
        FAKE_SHANI_HEALTH=str(tmp_path),
        PATH="%s:%s" % (tmp_path, os.environ["PATH"]),
        SHANI_SYSTEM_HEALTH=tool,
        SHANI_SYSTEM_HEALTH_ARGS=tool_args,
    )
    env.update(extra or {})
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *args], capture_output=True, text=True, env=env
    )
    lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
    return (lines[0] if len(lines) == 1 else lines), r


def calls(tmp_path):
    return (tmp_path / "calls").read_text()


def test_list_maps_every_status_and_keeps_the_checks(tmp_path):
    got, r = run(tmp_path, "list")
    assert r.returncode == 0
    assert got["have"] is True and got["error"] == ""
    assert [(c["key"], c["status"]) for c in got["checks"]] == [
        ("updates", "pass"),
        ("space", "pass"),
        ("services", "warn"),
        ("permissions", "fail"),
        ("backup", "info"),
    ]
    assert got["checks"][2]["title"] == "Background services"
    assert got["checks"][2]["detail"] == "Two did not start"
    assert "shani-health --verify --json" in calls(tmp_path)


def test_a_bare_list_or_a_report_object_both_work(tmp_path):
    bare, _ = run(tmp_path, "list", extra={"FAKE_SHANI_HEALTH_SHAPE": "list"})
    wrapped, _ = run(tmp_path, "list", extra={"FAKE_SHANI_HEALTH_SHAPE": "report"})
    assert bare["checks"] == wrapped["checks"]
    assert len(bare["checks"]) == 5 and bare["have"] is True


def test_a_failing_check_keeps_its_rows_despite_exit_1(tmp_path):
    got, r = run(tmp_path, "list", extra={"FAKE_SHANI_HEALTH_EXIT": "1"})
    assert r.returncode == 0 and got["have"] is True and got["error"] == ""
    assert [c["status"] for c in got["checks"]].count("fail") == 1
    assert len(got["checks"]) == 5


def test_the_tools_own_field_names_are_read(tmp_path):
    got, _ = run(tmp_path, "list", extra={"FAKE_SHANI_HEALTH_SHAPE": "tool"})
    assert got["checks"] == [
        {
            "key": "System integrity",
            "title": "System integrity",
            "status": "fail",
            "detail": "One slot did not match",
        }
    ]


def test_empty_report_invents_nothing(tmp_path):
    got, r = run(tmp_path, "list", extra={"FAKE_SHANI_HEALTH_SHAPE": "empty"})
    assert r.returncode == 0 and got["have"] is True and got["checks"] == []


def test_missing_tool_and_bad_json_are_honest(tmp_path):
    missing, r = run(tmp_path, "list", tool="no-such-health-tool")
    assert r.returncode == 0 and missing["have"] is False
    assert missing["checks"] == [] and "not available" in missing["error"]
    broken, r = run(tmp_path, "list", extra={"FAKE_SHANI_HEALTH_BROKEN": "1"})
    assert r.returncode == 0 and broken["have"] is False
    assert broken["checks"] == [] and broken["error"]


def test_arguments_are_never_a_shell_line(tmp_path):
    target = tmp_path / "PWNED"
    got, _ = run(tmp_path, "list", tool_args="--verify --json; touch %s" % target)
    assert not target.exists()
    assert "--json;" in calls(tmp_path) and str(target) in calls(tmp_path)
    assert "pass" in [c["status"] for c in got["checks"]]


def test_a_tool_name_with_a_shell_word_is_just_a_name(tmp_path):
    target = tmp_path / "ALSO_PWNED"
    got, r = run(tmp_path, "list", tool="shani-health; touch %s" % target)
    assert not target.exists() and r.returncode == 0
    assert got["have"] is False and got["checks"] == []


def test_no_verb_beyond_list(tmp_path):
    _, r = run(tmp_path, "list", "extra")
    assert r.returncode == 2 and not r.stdout
