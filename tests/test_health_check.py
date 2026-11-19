"""Ananta's read-only health check, ported as a shell bridge.

The important edge cases are honesty ones: no failed services is a pass, and a
tool that cannot be read is reported, not quietly marked healthy.
"""

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "bridge" / "health-check.py"
spec = importlib.util.spec_from_file_location("health_check", SOURCE)
health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(health)


def stage(monkeypatch, answers):
    monkeypatch.setattr(health, "run", lambda cmd, timeout=8: answers.get(cmd[0]))
    monkeypatch.setattr(health.shutil, "which", lambda p: True)
    return {c["id"]: c for c in health.checks()}


def test_no_failed_services_is_a_pass(monkeypatch):
    got = stage(
        monkeypatch,
        {
            "df": "Avail\n3000000000\n",
            "systemctl": "",  # --failed printed nothing
            "findmnt": "rw,relatime",
        },
    )
    assert got["services"]["ok"] is True
    assert got["services"]["detail"] == "none failed"
    assert got["space"]["ok"] is True
    assert got["writable"]["ok"] is True


def test_unreadable_checks_are_not_a_pass(monkeypatch):
    got = stage(monkeypatch, {"df": None, "systemctl": None, "findmnt": None})
    for cid in ("space", "services", "writable"):
        assert got[cid]["ok"] is False
        assert got[cid]["detail"] == "could not be read"


def test_low_space_and_failed_services_are_reported(monkeypatch):
    got = stage(
        monkeypatch,
        {
            "df": "Avail\n1000000000\n",
            "systemctl": "a.service loaded failed failed A\nb.service loaded failed failed B",
            "findmnt": "ro,relatime",
        },
    )
    assert got["space"]["ok"] is False and "1.0 GB" in got["space"]["detail"]
    assert got["services"]["ok"] is False and "a.service" in got["services"]["detail"]
    assert got["writable"]["ok"] is False and got["writable"]["detail"] == "read-only"
