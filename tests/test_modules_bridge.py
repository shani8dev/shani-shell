"""Read-only checks for bridge/modules.py (the live list is machine-specific)."""

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "shani_modules_bridge", ROOT / "bridge/modules.py"
)
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def test_the_bridge_has_a_test_or_says_why_not():
    # bridge/modules.py is covered by this file; keep coverage discovery honest.
    assert SPEC.origin.endswith("bridge/modules.py")


def test_module_names_are_validated_before_touching_sysfs():
    assert mod.cmd_params(type("A", (), {"name": "../etc"})())["error"] == "bad name"
    assert mod.cmd_params(type("A", (), {"name": ""})())["error"] == "bad name"


def test_the_module_list_is_sorted_and_counted():
    result = mod.cmd_list(None)
    assert result["count"] == len(result["modules"])
    assert [m["name"] for m in result["modules"]] == sorted(
        m["name"] for m in result["modules"]
    )
