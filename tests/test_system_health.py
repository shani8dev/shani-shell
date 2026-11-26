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
FAKE_AUDIT = ROOT / "dev" / "fake-audit.py"


def run(
    tmp_path,
    *args,
    tool="shani-health",
    tool_args="--verify --json",
    extra=None,
    pkexec=FAKE,
):
    links = {
        "shani-health": FAKE,
        "pkexec": pkexec,
        "ausearch": FAKE_AUDIT,
        "systemctl": FAKE_AUDIT,
    }
    for name, target in links.items():
        link = tmp_path / name
        if not link.exists():
            link.symlink_to(target)
    env = dict(
        os.environ,
        FAKE_SHANI_HEALTH=str(tmp_path),
        FAKE_AUDIT=str(tmp_path),
        PATH="%s:%s" % (tmp_path, os.environ["PATH"]),
        SHANI_SYSTEM_HEALTH=tool,
        SHANI_SYSTEM_HEALTH_ARGS=tool_args,
        SHANI_SYSTEM_PKEXEC="pkexec",
        SHANI_AUSEARCH="ausearch",
        SHANI_SYSTEM_SYSTEMCTL="systemctl",
        SHANI_AUDIT_LOG=str(tmp_path / "audit.log"),
    )
    env.update(extra or {})
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *args], capture_output=True, text=True, env=env
    )
    lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
    return (lines[0] if len(lines) == 1 else lines), r


def calls(tmp_path):
    return (tmp_path / "calls").read_text()


def audit_env(tmp_path, **values):
    """An audit log with content plus the given stand-in answers."""
    (tmp_path / "audit.log").write_text("audit events" * 20)
    return {"SHANI_AUDIT_LOG": str(tmp_path / "audit.log"), **values}


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


def test_storage_parses_capacity_maintenance_subvolumes_and_warnings(tmp_path):
    got, r = run(tmp_path, "storage")
    assert r.returncode == 0 and got["have"] is True and got["error"] == ""
    assert got["timestamp"] == "2026-11-26T12:00:00+00:00"
    assert set(got["summary"]) >= {
        "Free",
        "Total",
        "Used",
        "Snapshots",
        "Quotas",
        "Scrub",
        "Scrub tmr",
        "Maint tmrs",
        "bees",
        "Dev errors",
        "Dedup",
    }
    assert got["summary"]["Free"]["status"] == "ok"
    assert got["summary"]["Maint tmrs"]["status"] == "warning"
    assert got["summary"]["Used"]["used"] == "470 GB"
    assert got["summary"]["Used"]["uncompressed"] == "480 GB"
    assert [s["name"] for s in got["subvolumes"]] == ["@home", "@snapshots"]
    assert got["subvolumes"][0]["used"] == "12G"
    assert got["subvolumes"][0]["uncompressed"] == "20G"
    assert got["subvolumes"][1]["used"] == "960K"
    assert got["subvolumes"][1]["uncompressed"] == "16M"
    assert {w["key"] for w in got["warnings"]} == {
        "Maint tmrs",
        "Dev errors",
        "@snapshots",
    }
    assert all(set(w) == {"key", "status", "message"} for w in got["warnings"])
    assert "pkexec shani-health --storage-info --json" in calls(tmp_path)


def test_storage_without_json_is_honest(tmp_path):
    got, r = run(tmp_path, "storage", extra={"FAKE_SHANI_HEALTH_STORAGE_FAIL": "1"})
    assert r.returncode == 0 and got["have"] is False and got["error"]
    assert "FATAL" in got["error"]
    assert got["timestamp"] == "" and got["summary"] == {}
    assert got["subvolumes"] == [] and got["warnings"] == []


def test_storage_failing_check_with_exit_1_is_still_parsed(tmp_path):
    got, r = run(tmp_path, "storage", extra={"FAKE_SHANI_HEALTH_STORAGE_EXIT": "1"})
    assert r.returncode == 0 and got["have"] is True and got["error"] == ""
    assert got["summary"]["Dev errors"]["status"] == "critical"


def test_storage_without_pkexec_is_honest(tmp_path):
    got, r = run(tmp_path, "storage", extra={"SHANI_SYSTEM_PKEXEC": "no-such-pkexec"})
    assert r.returncode == 0 and got["have"] is False
    assert "not available" in got["error"] and got["warnings"] == []


def test_audit_parses_records_and_daemon_state(tmp_path):
    got, r = run(tmp_path, "audit", pkexec=FAKE_AUDIT, extra=audit_env(tmp_path))
    assert r.returncode == 0 and got["have"] is True and got["error"] == ""
    assert got["active"] == "active" and got["enabled"] == "enabled"
    assert got["log_present"] is True and got["log_size"] == 240
    assert len(got["records"]) == 3 and got["truncated"] is False
    assert all(set(x) == {"type", "time", "detail"} for x in got["records"])
    assert got["records"][0]["type"] == "USER_START"
    assert "/usr/bin/su" in got["records"][0]["detail"]
    assert got["records"][2]["detail"] == "raw audit line 3"
    assert got["verdict"] == "genuine"
    logged = calls(tmp_path)
    assert "ausearch --output=json -i -n 25 --start recent" in logged
    assert "systemctl is-active auditd" in logged
    assert "systemctl is-enabled auditd" in logged


def test_audit_reads_the_items_document_shape(tmp_path):
    got, _ = run(
        tmp_path,
        "audit",
        pkexec=FAKE_AUDIT,
        extra=audit_env(tmp_path, FAKE_AUDIT_DOC="items"),
    )
    assert got["have"] is True and len(got["records"]) == 3
    assert "/usr/bin/su" in got["records"][0]["detail"]


def test_audit_caps_records_and_flags_truncation(tmp_path):
    got, _ = run(
        tmp_path,
        "audit",
        pkexec=FAKE_AUDIT,
        extra=audit_env(tmp_path, FAKE_AUDIT_COUNT="30"),
    )
    assert len(got["records"]) == 25 and got["truncated"] is True


def test_audit_not_running_empty_result_is_not_genuine(tmp_path):
    got, _ = run(
        tmp_path,
        "audit",
        pkexec=FAKE_AUDIT,
        extra=audit_env(tmp_path, FAKE_AUDIT_EMPTY="1", FAKE_AUDIT_ACTIVE="inactive"),
    )
    assert got["have"] is True and got["records"] == []
    assert got["active"] == "inactive" and got["verdict"] == "not-running"


def test_audit_unknown_daemon_state_is_unresolved(tmp_path):
    for word in ("", "unknown"):
        got, _ = run(
            tmp_path,
            "audit",
            pkexec=FAKE_AUDIT,
            extra=audit_env(tmp_path, FAKE_AUDIT_EMPTY="1", FAKE_AUDIT_ACTIVE=word),
        )
        assert got["active"] == word and got["verdict"] == "unresolved"


def test_audit_log_missing_and_empty_verdicts(tmp_path):
    missing = audit_env(tmp_path, FAKE_AUDIT_EMPTY="1")
    missing["SHANI_AUDIT_LOG"] = str(tmp_path / "none.log")
    got, _ = run(tmp_path, "audit", pkexec=FAKE_AUDIT, extra=missing)
    assert got["log_present"] is False and got["log_size"] is None
    assert got["verdict"] == "no-log"
    (tmp_path / "zero.log").write_text("")
    empty = audit_env(tmp_path, FAKE_AUDIT_EMPTY="1")
    empty["SHANI_AUDIT_LOG"] = str(tmp_path / "zero.log")
    got, _ = run(tmp_path, "audit", pkexec=FAKE_AUDIT, extra=empty)
    assert got["log_present"] is True and got["log_size"] == 0
    assert got["verdict"] == "empty-log"


def test_audit_refusal_never_becomes_nothing_to_report(tmp_path):
    got, r = run(
        tmp_path,
        "audit",
        pkexec=FAKE_AUDIT,
        extra=audit_env(tmp_path, FAKE_AUDIT_REFUSE="1"),
    )
    assert r.returncode == 0 and got["have"] is False and got["records"] == []
    assert "permission denied" in got["error"]
    assert got["verdict"] == "unresolved"


def test_audit_malformed_answer_keeps_the_error(tmp_path):
    got, _ = run(
        tmp_path,
        "audit",
        pkexec=FAKE_AUDIT,
        extra=audit_env(tmp_path, FAKE_AUDIT_MALFORMED="1"),
    )
    assert got["have"] is False and got["records"] == [] and got["error"]
    assert got["verdict"] == "unresolved"


def test_every_verb_rejects_extra_argv(tmp_path):
    for verb in ("list", "storage", "audit"):
        _, r = run(tmp_path, verb, "extra", pkexec=FAKE_AUDIT)
        assert r.returncode == 2 and not r.stdout
    _, r = run(tmp_path, "bogus")
    assert r.returncode == 2 and not r.stdout
    assert '"error"' in r.stderr
