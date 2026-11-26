"""bridge/system_background.py against dev/fake-system-bg.py: system cron
files with the user field kept, priority state, IRQ counters and audit records.
Audit events are copied in the tool's own words, with no score or judgement.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_background.py"
FAKE = ROOT / "dev" / "fake-system-bg.py"


def setup(tmp_path, commands=("systemctl", "ausearch", "ananicy-cpp")):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    for name in commands:
        (bin_dir / name).symlink_to(FAKE)
    env = dict(os.environ)
    env.update(
        {
            "FAKE_SYSTEM_BG": str(tmp_path),
            "PATH": str(bin_dir) + ":" + os.environ["PATH"],
            "SHANI_CRONTAB_ROOT": str(tmp_path / "etc"),
            "SHANI_ANANICY": "ananicy-cpp",
            "SHANI_SYSTEM_SYSTEMCTL": "systemctl",
            "SHANI_INTERRUPTS": str(tmp_path / "interrupts"),
            "SHANI_AUSEARCH": "ausearch",
        }
    )
    return env


def call(env, verb):
    r = subprocess.run(
        [sys.executable, str(BRIDGE), verb], capture_output=True, text=True, env=env
    )
    return json.loads(r.stdout), r


def test_schedules_keep_the_username_field(tmp_path):
    env = setup(tmp_path)
    etc = tmp_path / "etc"
    (etc / "cron.d").mkdir(parents=True)
    (etc / "cron.daily").mkdir()
    (etc / "cron.hourly").mkdir()
    (etc / "crontab").write_text(
        "SHELL=/bin/sh\n# a comment\n0 3 * * * root /usr/bin/backup\n@daily root /usr/bin/report\n"
    )
    (etc / "cron.d" / "check").write_text("*/5 * * * * visitor /usr/bin/check\n")
    (etc / "cron.daily" / "clean").write_text("echo cleaning\n")
    (etc / "cron.hourly" / "tick").write_text("echo tick\n")
    got, _ = call(env, "schedules")
    by_file = {Path(f["file"]).name: f["lines"] for f in got["files"]}
    assert by_file["crontab"] == [
        "SHELL=/bin/sh",
        "0 3 * * * root /usr/bin/backup",
        "@daily root /usr/bin/report",
    ]
    assert by_file["check"] == ["*/5 * * * * visitor /usr/bin/check"]
    assert by_file["clean"] == ["echo cleaning"] and by_file["tick"] == ["echo tick"]
    assert got["error"] == ""


def test_priority_installed_and_active(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "systemctl-ananicy-cpp.service.out").write_text("active\n")
    got, _ = call(env, "priority")
    assert got["installed"] is True and got["active"] is True
    assert got["detail"] == "active" and got["error"] == ""
    (tmp_path / "systemctl-ananicy-cpp.service.out").write_text("inactive\n")
    stopped, _ = call(env, "priority")
    assert stopped["installed"] is True and stopped["active"] is False
    empty_dir = tmp_path / "empty"
    empty_dir.mkdir()
    env["PATH"] = str(empty_dir)
    missing, _ = call(env, "priority")
    assert missing["installed"] is False and missing["active"] is False
    assert missing["detail"] == "not installed"


def test_irq_cpu_count_balancing_and_sample(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "interrupts").write_text(
        "           CPU0       CPU1\n"
        "  0:         10        120   IO-APIC   2-edge      timer\n"
        "  1:          0         45   IO-APIC   1-edge      i8042\n"
        "  8:        300          0   IO-APIC   8-edge      rtc0\n"
        "  9:         22         18   PCI-MSI   512-edge      eth0\n"
    )
    got, _ = call(env, "irq")
    assert got["cpus"] == 2 and got["balanced"] is True
    assert len(got["lines"]) == 3 and "IO-APIC" in got["lines"][0]
    assert got["error"] == ""
    (tmp_path / "interrupts").write_text(
        "           CPU0       CPU1\n  0:         10          0   timer\n  8:        300          0   rtc0\n"
    )
    one_cpu, _ = call(env, "irq")
    assert one_cpu["balanced"] is False and one_cpu["cpus"] == 2
    (tmp_path / "interrupts").unlink()
    missing, _ = call(env, "irq")
    assert missing["error"] and missing["cpus"] == 0 and missing["lines"] == []


def test_audit_records_without_grading(tmp_path):
    env = setup(tmp_path)
    (tmp_path / "ausearch.out").write_text(
        "type=USER_LOGIN msg=audit(1710000000.100:42): pid=100 uid=0 auid=1000 msg='op=login id=\"alice\"'\n"
        "type=USER_ACCT msg=audit(1710000000.101:43): pid=100 uid=0 auid=1000 msg='op=adding user id=\"bob\"'\n"
        "a line that is not a record\n"
    )
    got, _ = call(env, "audit")
    assert got["events"] == [
        {
            "type": "USER_LOGIN",
            "time": "1710000000.100:42",
            "detail": "pid=100 uid=0 auid=1000 msg='op=login id=\"alice\"'",
        },
        {
            "type": "USER_ACCT",
            "time": "1710000000.101:43",
            "detail": "pid=100 uid=0 auid=1000 msg='op=adding user id=\"bob\"'",
        },
    ]
    text = json.dumps(got).lower()
    assert "score" not in text and "severity" not in text and "grade" not in text
    assert (tmp_path / "calls").read_text().startswith("ausearch -m ALL -ts today\n")
    empty_dir = tmp_path / "empty"
    empty_dir.mkdir()
    no_tool, _ = call(dict(env, PATH=str(empty_dir)), "audit")
    assert no_tool["events"] == [] and "ausearch" in no_tool["error"]
