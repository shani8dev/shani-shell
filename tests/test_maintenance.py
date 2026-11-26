"""bridge/system_maintenance.py against dev/fake-system-root.py: the three root
actions get exactly the right argv, reset refuses anything but two booleans on
stdin, and the saved report's contents never reach the page."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge" / "system_maintenance.py"
FAKE = ROOT / "dev" / "fake-system-root.py"


def setup(tmp_path):
    for name in ("pkexec", "shani-deploy", "shani-health", "shani-reset"):
        link = tmp_path / name
        if not link.exists():
            link.symlink_to(FAKE)
    return dict(
        os.environ,
        FAKE_SYSTEM_ROOT=str(tmp_path),
        PATH="%s:%s" % (tmp_path, os.environ["PATH"]),
        SHANI_PKEXEC="pkexec",
        SHANI_DEPLOY="shani-deploy",
        SHANI_HEALTH="shani-health",
        SHANI_RESET="shani-reset",
        SHANI_REPORT_DIR=str(tmp_path / "reports"),
    )


def run(tmp_path, *args, body=None, extra=None):
    env = setup(tmp_path)
    env.update(extra or {})
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *args],
        input=body,
        capture_output=True,
        text=True,
        env=env,
    )
    lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
    return (lines[0] if len(lines) == 1 else lines), r


def calls(tmp_path):
    return (tmp_path / "calls").read_text()


def test_clean_uses_the_exact_pkexec_argv(tmp_path):
    got, r = run(tmp_path, "clean")
    assert r.returncode == 0 and got["ok"] is True and got["error"] == ""
    assert "cleaned" in got["output"].lower()
    assert "pkexec shani-deploy --cleanup --optimize" in calls(tmp_path)
    assert "shani-deploy --cleanup --optimize" in calls(tmp_path)


def test_report_saves_a_bundle_but_never_prints_it(tmp_path):
    got, r = run(tmp_path, "report")
    folder = tmp_path / "reports"
    assert r.returncode == 0 and got["ok"] is True and got["error"] == ""
    assert got["path"] == str(folder / "health-bundle.txt")
    assert (folder / "health-bundle.txt").read_text().startswith("Bundle text")
    assert "Bundle text must never reach the page" not in r.stdout
    assert "pkexec shani-health --export-logs %s" % folder in calls(tmp_path)


@pytest.mark.parametrize(
    "home,keep,flags",
    [
        (False, False, ""),
        (True, False, " --home"),
        (False, True, " --keep-downloads"),
        (True, True, " --home --keep-downloads"),
    ],
)
def test_reset_flags_follow_the_two_booleans(tmp_path, home, keep, flags):
    body = json.dumps({"home": home, "keepDownloads": keep})
    got, r = run(tmp_path, "reset", body=body)
    assert r.returncode == 0 and got == {"ok": True, "error": ""}
    assert "pkexec shani-reset --yes%s" % flags in calls(tmp_path)


@pytest.mark.parametrize(
    "body",
    [
        "",
        "not json",
        "[]",
        "null",
        '{"home": true}',
        '{"home": true, "keepDownloads": false, "extra": 1}',
        '{"home": 1, "keepDownloads": false}',
        '{"home": "yes", "keepDownloads": false}',
        '{"home": true, "keepDownloads": "false"}',
        '{"HOME": true, "keepDownloads": false}',
    ],
)
def test_reset_refuses_anything_but_two_booleans(tmp_path, body):
    got, r = run(tmp_path, "reset", body=body)
    assert r.returncode == 0 and got["ok"] is False and got["error"]
    assert not (tmp_path / "calls").exists()


def test_tool_names_are_never_shell_lines(tmp_path):
    target = tmp_path / "PWNED"
    got, _ = run(
        tmp_path, "clean", extra={"SHANI_DEPLOY": "shani-deploy; touch %s" % target}
    )
    assert not target.exists() and got["ok"] is False and got["error"]
    assert "pkexec shani-deploy; touch %s --cleanup --optimize" % target in calls(
        tmp_path
    )


def test_no_verb_beyond_reset(tmp_path):
    _, r = run(tmp_path, "reset", "dwim")
    assert r.returncode == 2 and not r.stdout
