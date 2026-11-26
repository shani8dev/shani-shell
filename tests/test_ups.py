"""bridge/ups.py: the seven-key upsmon.conf policy, read and written for real.

The bridge is a subprocess, so its JSON-out contract is checked as the shell sees
it. dev/fake-upsmon.py stands in for shani-cassini-save by symlink under its real
basename: it takes the content on stdin, checks the digest, refuses cancelled
auth and logs argv only. No secret reaches argv, the call log or JSON output.
"""

import hashlib
import json
import os
import stat
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "ups.py"
FAKE = ROOT / "dev" / "fake-upsmon.py"
MONITOR_SECRET = "Mon1torS3cr3tDoNotEcho"

DEFAULTS = {
    "MINSUPPLIES": "1",
    "SHUTDOWNCMD": '"/sbin/shutdown -h +0"',
    "POWERDOWNFLAG": "/etc/killpower",
    "DEADTIME": "15",
    "FINALDELAY": "0",
    "POLLFREQ": "5",
    "POLLFREQALERT": "5",
}
CONF = (
    "# the shutdown policy\n"
    f"MONITOR ups1@localhost 1 monitor {MONITOR_SECRET} master\n"
    + "".join(f"{key} {value}\n" for key, value in DEFAULTS.items())
    + "UNMANAGED keep-me\n"
)


def setup(tmp_path, conf_text=CONF, service="active", refuse=False):
    link = tmp_path / "shani-cassini-save"
    if not link.exists():
        link.symlink_to(FAKE)
    ctl = tmp_path / "systemctl"
    ctl.write_text('#!/bin/sh\necho "$FAKE_UPS_SERVICE"\n')
    ctl.chmod(0o755)
    conf = tmp_path / "upsmon.conf"
    if conf_text is None:
        conf.unlink(missing_ok=True)
    else:
        conf.write_text(conf_text)
    env = dict(
        os.environ,
        SHANI_SYSTEM_PKEXEC=sys.executable,
        SHANI_CASSINI_SAVE=str(link),
        SHANI_UPSMON_CONF=str(conf),
        SHANI_SYSTEMCTL=str(ctl),
        FAKE_UPS_SERVICE=service,
        FAKE_UPMON=str(tmp_path / "fake"),
    )
    env.pop("FAKE_UPMON_REFUSE", None)
    if refuse:
        env["FAKE_UPMON_REFUSE"] = "1"
    return env, conf


def run(tmp_path, *args, body="", **extra):
    env, conf = setup(tmp_path)
    env.update(extra)
    result = subprocess.run(
        [sys.executable, str(BRIDGE), *args],
        input=body,
        capture_output=True,
        text=True,
        timeout=60,
        env=env,
    )
    return result, conf, env


def one(result):
    lines = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == 1, result.stdout
    return lines[0]


def calls(tmp_path):
    path = tmp_path / "fake" / "calls"
    return path.read_text() if path.exists() else ""


def values(**override):
    return dict(DEFAULTS, **override)


# ---- read path --------------------------------------------------------------


def test_policy_reads_the_seven_keys_service_and_monitor(tmp_path):
    result, _, _ = run(tmp_path, "policy")
    assert result.returncode == 0
    got = one(result)
    assert got["present"] is True
    assert got["file"] == str(tmp_path / "upsmon.conf")
    assert got["service"] == "active"
    assert got["monitored"] == "ups1"
    assert got["keys"] == DEFAULTS
    assert got["error"] == ""
    assert "UNMANAGED" not in result.stdout


@pytest.mark.parametrize(
    "service", [("active", "active"), ("inactive", "inactive"), ("weird", "unknown")]
)
def test_service_is_a_stable_code(tmp_path, service):
    result, _, _ = run(tmp_path, "policy", FAKE_UPS_SERVICE=service[0])
    assert one(result)["service"] == service[1]


def test_missing_config_is_honest(tmp_path):
    result, _, _ = run(
        tmp_path, "policy", SHANI_UPSMON_CONF=str(tmp_path / "absent.conf")
    )
    got = one(result)
    assert got["present"] is False and got["keys"] == {}
    assert "upsmon.conf" in got["error"]
    assert got["service"] == "active"


def test_no_argv_live_read_is_unchanged(tmp_path):
    upsc = tmp_path / "upsc"
    upsc.write_text(
        "#!/bin/sh\n"
        'if [ "$1" = "-l" ]; then echo ups1; exit 0; fi\n'
        "printf 'device.mfr: Example\\nbattery.charge: 80\\nups.status: OB\\n'\n"
    )
    upsc.chmod(0o755)
    result, _, _ = run(tmp_path, SHANI_UPSC=str(upsc))
    assert result.returncode == 0
    got = one(result)
    assert set(got) == {
        "present",
        "name",
        "model",
        "onBattery",
        "low",
        "charge",
        "minutes",
        "load",
    }
    assert got["present"] is True and got["name"] == "ups1"
    assert got["charge"] == 80 and got["onBattery"] is True


# ---- validation -------------------------------------------------------------


@pytest.mark.parametrize(
    "key,bad",
    [
        ("MINSUPPLIES", "0"),
        ("MINSUPPLIES", "9"),
        ("MINSUPPLIES", "-1"),
        ("SHUTDOWNCMD", "shutdown -h +0"),
        ("SHUTDOWNCMD", '"'),
        ("POWERDOWNFLAG", "etc/killpower"),
        ("DEADTIME", "0"),
        ("DEADTIME", "601"),
        ("FINALDELAY", "-1"),
        ("FINALDELAY", "601"),
        ("POLLFREQ", "0"),
        ("POLLFREQ", "601"),
        ("POLLFREQALERT", "0"),
        ("POLLFREQALERT", "601"),
    ],
)
def test_each_bound_refuses_before_any_command(tmp_path, key, bad):
    payload = values(**{key: bad})
    result, conf, _ = run(tmp_path, "policy-save", body=json.dumps(payload))
    got = one(result)
    assert got["ok"] is False and got["field"] == key and got["error"]
    assert calls(tmp_path) == ""
    assert conf.read_text() == CONF


def test_wrong_keys_and_non_text_values_are_refused(tmp_path):
    payload = values()
    payload["NOPE"] = "1"
    assert one(run(tmp_path, "policy-save", body=json.dumps(payload))[0])["ok"] is False
    payload = values(MINSUPPLIES=1)
    got = one(run(tmp_path, "policy-save", body=json.dumps(payload))[0])
    assert got["ok"] is False and got["field"] == "MINSUPPLIES"
    got = one(run(tmp_path, "policy-save", body=json.dumps(values(EXTRA=1)))[0])
    assert got["ok"] is False and got["field"] == ""
    assert calls(tmp_path) == ""


def test_duplicate_uncommented_key_is_refused(tmp_path):
    conf = CONF + "MINSUPPLIES 4\n"
    env, path = setup(tmp_path, conf_text=conf)
    result = subprocess.run(
        [sys.executable, str(BRIDGE), "policy-save"],
        input=json.dumps(values()),
        capture_output=True,
        text=True,
        env=env,
    )
    got = one(result)
    assert got["ok"] is False and got["field"] == "MINSUPPLIES"
    assert got["error"] == "duplicate"
    assert calls(tmp_path) == "" and path.read_text() == conf
    result = subprocess.run(
        [sys.executable, str(BRIDGE), "policy"],
        capture_output=True,
        text=True,
        env=env,
    )
    assert one(result)["keys"]["MINSUPPLIES"] == "4"  # last wins, as upsmon reads it


def test_unchanged_is_a_no_op_success(tmp_path):
    result, conf, _ = run(tmp_path, "policy-save", body=json.dumps(values()))
    got = one(result)
    assert got["ok"] is True and got["error"] == "unchanged"
    assert got["keys"] == DEFAULTS
    assert calls(tmp_path) == "" and conf.read_text() == CONF


# ---- write path -------------------------------------------------------------


def test_save_uses_a_digest_preserves_other_lines_and_hides_the_payload(tmp_path):
    payload = values(DEADTIME="30")
    expected = CONF.replace("DEADTIME 15", "DEADTIME 30")
    result, conf, _ = run(tmp_path, "policy-save", body=json.dumps(payload))
    got = one(result)
    assert result.returncode == 0 and got["ok"] is True and got["error"] == ""
    assert got["keys"]["DEADTIME"] == "30"
    assert got["keys"]["SHUTDOWNCMD"] == payload["SHUTDOWNCMD"]
    assert conf.read_bytes() == expected.encode()
    assert "# the shutdown policy" in conf.read_text()
    assert (
        f"MONITOR ups1@localhost 1 monitor {MONITOR_SECRET} master" in conf.read_text()
    )
    assert "UNMANAGED keep-me" in conf.read_text()
    assert stat.S_IMODE(conf.stat().st_mode) == 0o644
    digest = hashlib.sha256(expected.encode()).hexdigest()
    assert calls(tmp_path).strip() == (
        "shani-cassini-save --target nut_upsmon_conf --expect-sha256 " + digest
    )
    assert MONITOR_SECRET not in result.stdout
    assert MONITOR_SECRET not in calls(tmp_path)
    assert MONITOR_SECRET not in result.stderr


def test_cancelled_auth_returns_ok_false_and_writes_nothing(tmp_path):
    env, conf = setup(tmp_path, refuse=True)
    result = subprocess.run(
        [sys.executable, str(BRIDGE), "policy-save"],
        input=json.dumps(values(DEADTIME="30")),
        capture_output=True,
        text=True,
        env=env,
    )
    got = one(result)
    assert got["ok"] is False and got["error"]
    assert conf.read_text() == CONF
    assert MONITOR_SECRET not in result.stdout + result.stderr
    assert MONITOR_SECRET not in calls(tmp_path)


def test_save_to_a_missing_config_adds_all_seven_keys(tmp_path):
    env, conf = setup(tmp_path, conf_text=None)
    result = subprocess.run(
        [sys.executable, str(BRIDGE), "policy-save"],
        input=json.dumps(values(DEADTIME="20")),
        capture_output=True,
        text=True,
        env=env,
    )
    got = one(result)
    assert got["ok"] is True and got["keys"]["DEADTIME"] == "20"
    written = conf.read_text()
    assert all(
        f"{key} {value}\n" in written for key, value in values(DEADTIME="20").items()
    )


def test_empty_value_comments_the_directive_out(tmp_path):
    result, conf, _ = run(tmp_path, "policy-save", body=json.dumps(values(DEADTIME="")))
    got = one(result)
    assert got["ok"] is True and got["keys"]["DEADTIME"] == ""
    assert "\nDEADTIME 15\n" not in conf.read_text()
    assert "# DEADTIME 15" in conf.read_text()
    assert calls(tmp_path).strip()


# ---- argv contract ----------------------------------------------------------


@pytest.mark.parametrize(
    "args",
    [
        ("policy", "extra"),
        ("policy-save", "extra"),
        ("bogus",),
        ("policy", "policy"),
        ("--help",),
    ],
)
def test_every_verb_rejects_extra_argv(tmp_path, args):
    result, conf, _ = run(tmp_path, *args)
    assert result.returncode == 2
    assert one(result)["error"]
    assert calls(tmp_path) == "" and conf.read_text() == CONF


def test_fake_refuses_what_the_real_helper_refuses(tmp_path):
    link = tmp_path / "shani-cassini-save"
    if not link.exists():
        link.symlink_to(FAKE)
    env, _ = setup(tmp_path)
    for args in (
        ["--target", "hosts", "--expect-sha256", "a" * 64],
        ["--target", "nut_upsmon_conf", "--wat", "1"],
        ["--target", "nut_upsmon_conf"],
    ):
        result = subprocess.run(
            [sys.executable, str(link), *args],
            input=b"",
            capture_output=True,
            env=env,
        )
        assert result.returncode == 2, args
    result = subprocess.run(
        [
            sys.executable,
            str(link),
            "--target",
            "nut_upsmon_conf",
            "--expect-sha256",
            "a" * 64,
        ],
        input=b"MINSUPPLIES 1\n",
        capture_output=True,
        env=env,
    )
    assert result.returncode == 1
