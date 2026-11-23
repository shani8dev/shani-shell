"""bridge/bootinfo.py: the boot slots, read from shani-deploy.

shani-deploy is not in the dev image, so the tests cover what can be checked
without it: the bridge answers, says so plainly when the tool is missing, and
turns the documented --status --json shape into rows a settings page can show.
"""

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("bootinfo", ROOT / "bridge/bootinfo.py")
bi = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bi)

STATUS = {
    "version": "20261121",
    "profile": "niri",
    "channel": "stable",
    "booted_slot": "green",
    "current_slot": "green",
    "previous_slot": "blue",
    "candidate_boot": False,
    "update_available": None,
    "boot_failure": "",
    "auto_rollback_done": False,
}


def test_without_shani_deploy_it_says_so(monkeypatch):
    monkeypatch.setattr(bi.shutil, "which", lambda name: None)
    got = bi.cmd_status()
    assert got["available"] is False
    assert "shani-deploy" in got["note"]


def test_a_good_status_becomes_rows(monkeypatch):
    monkeypatch.setattr(bi.shutil, "which", lambda name: "/usr/bin/shani-deploy")
    monkeypatch.setattr(bi, "_read", lambda p: "")
    monkeypatch.setattr(
        bi,
        "subprocess",
        type(
            "S",
            (),
            {
                "run": staticmethod(
                    lambda *a, **k: type(
                        "R", (), {"stdout": json.dumps(STATUS), "returncode": 0}
                    )()
                )
            },
        ),
    )
    got = bi.cmd_status()
    assert got["available"] is True
    rows = {r["detail"]: r for r in got["rows"]}
    assert rows["booted_slot"]["value"] == "green"
    assert rows["booted_slot"]["status"] == "ok"
    assert rows["version"]["value"] == "20261121"


def test_an_empty_field_is_left_out(monkeypatch):
    monkeypatch.setattr(bi.shutil, "which", lambda name: "/usr/bin/shani-deploy")
    monkeypatch.setattr(bi, "_read", lambda p: "")
    monkeypatch.setattr(
        bi,
        "subprocess",
        type(
            "S",
            (),
            {
                "run": staticmethod(
                    lambda *a, **k: type(
                        "R", (), {"stdout": json.dumps(STATUS), "returncode": 0}
                    )()
                )
            },
        ),
    )
    details = [r["detail"] for r in bi.cmd_status()["rows"]]
    assert "boot_failure" not in details  # empty means no failure
    assert "update_available" not in details  # None means unknown, not "no"


def test_a_boot_failure_is_marked(monkeypatch):
    monkeypatch.setattr(bi.shutil, "which", lambda name: "/usr/bin/shani-deploy")
    monkeypatch.setattr(bi, "_read", lambda p: "")
    bad = dict(STATUS, boot_failure="green", auto_rollback_done=True)
    monkeypatch.setattr(
        bi,
        "subprocess",
        type(
            "S",
            (),
            {
                "run": staticmethod(
                    lambda *a, **k: type(
                        "R", (), {"stdout": json.dumps(bad), "returncode": 0}
                    )()
                )
            },
        ),
    )
    rows = {r["detail"]: r for r in bi.cmd_status()["rows"]}
    assert rows["boot_failure"]["status"] == "fail"
    assert rows["auto_rollback_done"]["status"] == "warn"


def test_a_bad_answer_is_not_a_crash(monkeypatch):
    monkeypatch.setattr(bi.shutil, "which", lambda name: "/usr/bin/shani-deploy")
    monkeypatch.setattr(
        bi,
        "subprocess",
        type(
            "S",
            (),
            {
                "run": staticmethod(
                    lambda *a, **k: type(
                        "R", (), {"stdout": "not json at all", "returncode": 1}
                    )()
                )
            },
        ),
    )
    got = bi.cmd_status()
    assert got["available"] is False
    assert "JSON" in got["note"]


def test_the_command_line_answers_json():
    out = subprocess.run(
        [sys.executable, str(ROOT / "bridge/bootinfo.py"), "status"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert out.returncode == 0
    assert isinstance(json.loads(out.stdout), dict)
