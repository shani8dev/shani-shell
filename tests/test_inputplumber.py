"""bridge/inputplumber.py: the shell's side of InputPlumber.

Everything here talks to the system bus, which the test image has none of, so
what is pinned is the command interpreter: the one JSON line the shell writes
on the bridge's stdin, and what it turns into. Getting this wrong is a
controller that is left in "always intercept" after the overlay closes - the
game never sees the pad again.
"""

import importlib.util
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location(
    "inputplumber_bridge", ROOT / "bridge/inputplumber.py"
)
ip = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ip)

from gi.repository import GLib  # noqa: E402


@pytest.fixture
def bus(monkeypatch):
    """Records what the command would have written to the bus."""
    written = []
    paths = [
        "/org/shadowblip/InputPlumber/CompositeDevice0",
        "/org/shadowblip/InputPlumber/CompositeDevice1",
    ]

    def set_prop(path, iface, name, value):
        written.append((path, name, value))
        return ""

    monkeypatch.setattr(ip, "set_prop", set_prop)
    monkeypatch.setattr(ip, "composite_paths", lambda: list(paths))
    monkeypatch.setattr(ip, "soon", lambda: None)
    return written


def unpack(variant):
    return variant.unpack()


# ---- intercept -------------------------------------------------------------


def test_intercept_applies_to_every_device(bus):
    ip.command(json.dumps({"op": "intercept", "path": "*", "mode": 2}))
    assert len(bus) == 2
    assert all(name == "InterceptMode" for _p, name, _v in bus)
    assert [unpack(v) for _p, _n, v in bus] == [2, 2]


def test_intercept_can_be_aimed_at_one_device(bus):
    ip.command(json.dumps({"op": "intercept", "path": "/a", "mode": 1}))
    assert [(p, unpack(v)) for p, _n, v in bus] == [("/a", 1)]


def test_intercept_without_a_path_means_every_device(bus):
    ip.command(json.dumps({"op": "intercept", "mode": 3}))
    assert len(bus) == 2


def test_a_missing_mode_is_none_not_a_crash(bus):
    ip.command(json.dumps({"op": "intercept", "path": "/a"}))
    assert unpack(bus[0][2]) == 0


def test_a_mode_that_is_a_string_is_coerced(bus):
    ip.command(json.dumps({"op": "intercept", "path": "/a", "mode": "2"}))
    assert unpack(bus[0][2]) == 2


# ---- the other two commands -------------------------------------------------


def test_targets_are_written_as_a_list_of_strings(bus):
    ip.command(
        json.dumps(
            {"op": "targets", "path": "/a", "targets": ["xbox-elite", "keyboard"]}
        )
    )
    assert bus[0][1] == "TargetDevices"
    assert unpack(bus[0][2]) == ["xbox-elite", "keyboard"]


def test_manage_all_writes_to_the_manager(bus):
    ip.command(json.dumps({"op": "manageAll", "on": True}))
    assert bus[0][1] == "ManageAllDevices"
    assert unpack(bus[0][2]) is True


def test_manage_all_off(bus):
    ip.command(json.dumps({"op": "manageAll", "on": False}))
    assert unpack(bus[0][2]) is False


# ---- what it must not do -----------------------------------------------------


def test_a_line_that_is_not_json_is_ignored(bus):
    ip.command("not json at all")
    assert bus == []


def test_an_unknown_operation_writes_nothing(bus):
    ip.command(json.dumps({"op": "nonsense"}))
    assert bus == []


def test_a_refusal_is_reported_on_stdout(bus, monkeypatch, capsys):
    monkeypatch.setattr(
        ip, "set_prop", lambda _p, _i, _n, _v: "not supported by this device"
    )
    ip.command(json.dumps({"op": "intercept", "path": "/a", "mode": 2}))
    out = [json.loads(x) for x in capsys.readouterr().out.splitlines() if x]
    assert out and out[-1]["type"] == "error"
    assert "not supported" in out[-1]["error"]


# ---- the command line --------------------------------------------------------


def test_without_watch_it_prints_how_to_use_it():
    import subprocess

    out = subprocess.run(
        [sys.executable, str(ROOT / "bridge/inputplumber.py")],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert out.returncode == 2
    assert "watch" in out.stderr
