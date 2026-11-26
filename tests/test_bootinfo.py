"""bridge/bootinfo.py: the boot slots, read from shani-deploy.

shani-deploy is not in the dev image, so the tests cover what can be checked
without it: the bridge answers, says so plainly when the tool is missing, and
turns the documented --status --json shape into rows a settings page can show.
"""

import importlib.util
import json
import os
import shutil
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


# --- stand-in driven tests --------------------------------------------------
# The stand-in rejects what the real tools reject; these run the bridge as a
# subprocess with SHANI_* overrides, so argv, JSON and SGR output are all real.

FAKE = ROOT / "dev/fake-boot-tools.py"
BRIDGE = ROOT / "bridge/bootinfo.py"
TOOLS = ("shani-deploy", "sbctl", "mokutil", "pkexec")


@pytest.fixture
def boot_tools(tmp_path, monkeypatch):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name in TOOLS:
        target = bin_dir / name
        shutil.copy(FAKE, target)
        target.chmod(0o755)
    folder = tmp_path / "fake"
    folder.mkdir()
    efi = tmp_path / "efi"
    (efi / "efivars").mkdir(parents=True)
    overrides = {
        "PATH": str(bin_dir) + os.pathsep + os.environ.get("PATH", ""),
        "FAKE_BOOT_TOOLS_DIR": str(folder),
        "SHANI_DEPLOY": str(bin_dir / "shani-deploy"),
        "SHANI_SYSTEM_PKEXEC": str(bin_dir / "pkexec"),
        "SHANI_SBCTL": str(bin_dir / "sbctl"),
        "SHANI_MOKUTIL": str(bin_dir / "mokutil"),
        "SHANI_EFI_DIR": str(efi),
    }
    for key, value in overrides.items():
        monkeypatch.setenv(key, value)
    return {"bin": bin_dir, "efi": efi, "calls": folder / "calls"}


def run_bridge(verb=None, extra=()):
    argv = [sys.executable, str(BRIDGE)]
    if verb:
        argv.append(verb)
    argv.extend(extra)
    return subprocess.run(argv, capture_output=True, text=True, timeout=60)


def answer(verb=None, extra=()):
    out = run_bridge(verb, extra)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


def calls(tools):
    path = tools["calls"]
    return path.read_text() if path.exists() else ""


def test_secureboot_sbctl_parsed_and_keys_counted(boot_tools):
    got = answer("secureboot")
    assert got["available"] is True
    assert got["sbctl_present"] is True
    assert got["installed"] is True
    assert got["secure_boot"] == "on"
    assert got["setup_mode"] is False
    assert got["enrolled"] is True
    assert got["enrolled_keys"] == 2
    assert got["microsoft_keys"] is True
    assert got["guid"] == "a1b2c3d4"
    assert got["vendors"] == ["Microsoft", "Custom Key"]
    assert got["error"] == ""
    log = calls(boot_tools)
    assert "sbctl status --json" in log
    assert "mokutil --list-enrolled" in log


def test_secureboot_missing_sbctl_uses_mokutil(boot_tools, monkeypatch):
    monkeypatch.setenv("SHANI_SBCTL", str(boot_tools["bin"] / "absent-sbctl"))
    got = answer("secureboot")
    assert got["sbctl_present"] is False
    assert got["installed"] is None
    assert got["enrolled"] is None
    assert got["secure_boot"] == "on"
    assert got["enrolled_keys"] == 2
    assert got["error"] == ""


def test_secureboot_efi_fallback(boot_tools, monkeypatch):
    monkeypatch.setenv("SHANI_SBCTL", str(boot_tools["bin"] / "absent-sbctl"))
    monkeypatch.setenv("SHANI_MOKUTIL", str(boot_tools["bin"] / "absent-mokutil"))
    efivars = boot_tools["efi"] / "efivars"
    (efivars / "SecureBoot-8be4df61").write_bytes(b"\x00\x00\x00\x00\x01\x00")
    (efivars / "SetupMode-8be4df61").write_bytes(b"\x00\x00\x00\x00\x00\x00")
    got = answer("secureboot")
    assert got["secure_boot"] == "on"
    assert got["setup_mode"] is False
    assert got["enrolled_keys"] is None  # no tool, so no invented zero
    assert got["available"] is True

    monkeypatch.setenv("SHANI_EFI_DIR", str(boot_tools["efi"] / "absent"))
    legacy = answer("secureboot")
    assert legacy["secure_boot"] == "legacy"


def test_secureboot_setup_mode_wins(boot_tools, monkeypatch):
    monkeypatch.setenv(
        "FAKE_BOOT_TOOLS_SBCTL",
        json.dumps(
            {
                "vendors": [],
                "guid": "",
                "installed": False,
                "secure_boot": False,
                "setup_mode": True,
            }
        ),
    )
    got = answer("secureboot")
    assert got["secure_boot"] == "setup"
    assert got["setup_mode"] is True
    assert got["enrolled"] is False


def test_secureboot_unread_key_count_is_none(boot_tools, monkeypatch):
    monkeypatch.setenv("FAKE_BOOT_TOOLS_KEYS", "fail")
    got = answer("secureboot")
    assert got["enrolled_keys"] is None


def test_verify_parses_sgr_rows_and_advice(boot_tools):
    got = answer("verify")
    assert got["available"] is True
    assert got["passed"] is True
    assert got["issues"] is None
    assert got["error"] == ""
    severities = {c["key"]: c["severity"] for c in got["checks"]}
    assert severities["UKI Booted"] == "ok"
    assert severities["Loader default"] == "ok"
    assert severities["Booted slot"] == "warn"
    assert severities["Reboot Status"] == "info"
    assert all(c["text"] and "\x1b" not in c["text"] for c in got["checks"])
    assert len(got["advice"]) == 1
    assert "yellow row" in got["advice"][0]
    assert got["unread"] == []
    assert "--verify-existing" in calls(boot_tools)


def test_verify_issues_and_unread(boot_tools, monkeypatch):
    monkeypatch.setenv("FAKE_BOOT_TOOLS_VERIFY", "issues")
    got = answer("verify")
    assert got["passed"] is False
    assert got["issues"] == 2
    assert {c["key"] for c in got["checks"]} >= {
        "UKI Candidate",
        "Loader default",
        "Rollback backups",
        "Booted slot",
    }
    bad = {c["key"]: c["severity"] for c in got["checks"]}
    assert bad["UKI Candidate"] == "bad"
    assert bad["Loader default"] == "bad"
    assert bad["Rollback backups"] == "ok"

    monkeypatch.setenv("FAKE_BOOT_TOOLS_VERIFY", "unread")
    other = answer("verify")
    assert "a line this build added" in other["unread"][0]


def test_verify_cancelled_and_no_answer(boot_tools, monkeypatch):
    monkeypatch.setenv("FAKE_BOOT_TOOLS_VERIFY", "cancelled")
    got = answer("verify")
    assert got["available"] is False
    assert got["error"] == "cancelled"
    assert got["checks"] == []
    assert got["passed"] is None

    for mode in ("noanswer", "empty"):
        monkeypatch.setenv("FAKE_BOOT_TOOLS_VERIFY", mode)
        none = answer("verify")
        assert none["available"] is False
        assert none["error"] == "no-answer"


def test_backups_json(boot_tools):
    got = answer("backups")
    assert got["available"] is True
    assert got["error"] == ""
    assert [slot["slot"] for slot in got["slots"]] == ["green", "blue"]
    assert got["slots"][0]["backups"][0]["name"] == "green-pre-update"
    assert "--list-backups --json" in calls(boot_tools)


def test_backups_cancelled(boot_tools, monkeypatch):
    monkeypatch.setenv("FAKE_BOOT_TOOLS_PKEXEC_RC", "126")
    got = answer("backups")
    assert got["available"] is False
    assert got["error"] == "cancelled"


def test_new_verbs_reject_extra_argv_and_unknown_verb(boot_tools):
    for verb in ("status", "secureboot", "verify", "backups"):
        out = run_bridge(verb, ("extra",))
        assert out.returncode == 2
        assert "error" in json.loads(out.stdout)
    out = run_bridge("nonsense")
    assert out.returncode == 2
    assert "error" in json.loads(out.stdout)


def test_status_check_command_is_accepted_by_stand_in(boot_tools):
    doc, error = bi.shanios_status(check=True)
    assert error == ""
    assert doc["version"] == "20261121"
    assert "shani-deploy --status --check --json" in calls(boot_tools)


def test_every_verb_answers_json(boot_tools):
    for verb in ("status", "secureboot", "verify", "backups"):
        assert isinstance(answer(verb), dict)


def test_stand_in_rejects_what_the_real_tools_reject(boot_tools):
    fake = boot_tools["bin"]

    def run(name, args):
        return subprocess.run(
            [str(fake / name)] + args, capture_output=True, text=True, timeout=20
        )

    for name, args in (
        ("shani-deploy", ["--status"]),
        ("shani-deploy", ["--verify-existing", "--json"]),
        ("shani-deploy", ["--yes"]),
        ("sbctl", ["status"]),
        ("sbctl", ["status", "--json", "--yes"]),
        ("mokutil", ["--sb-state", "--json"]),
        ("mokutil", ["--import"]),
        ("pkexec", ["sbctl", "status", "--json"]),
    ):
        out = run(name, args)
        assert out.returncode == 2, (name, args, out.stdout, out.stderr)
        assert "usage" in out.stderr.lower()
