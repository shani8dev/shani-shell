"""osk-layout.py: layouts from the system's own xkb data, via libxkbcommon.

Run against the real xkeyboard-config and libxkbcommon on this machine (no
fakes): the point is that what the screen keyboard shows is what xkb defines.
"""
from __future__ import annotations

import ctypes.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parents[1] / "bridge" / "osk-layout.py"
pytestmark = pytest.mark.skipif(ctypes.util.find_library("xkbcommon") is None, reason="no libxkbcommon")


def run(arg: str):
    out = subprocess.run([sys.executable, str(TOOL), arg], capture_output=True, text=True, timeout=30)
    return out.returncode, out.stdout, out.stderr


def chars(spec: str) -> str:
    code, out, err = run(spec)
    assert code == 0, err
    return "".join(k["n"] + k["s"] for row in json.loads(out)["rows"] for k in row)


def test_the_catalogue_is_xkbs_whole_list():
    code, out, _ = run("--list")
    ids = {x["id"] for x in json.loads(out)}
    assert len(ids) > 500, len(ids)
    assert {"in+marathi", "in+tam", "in+bolnagri", "in+mal", "ru", "ara"} <= ids


@pytest.mark.parametrize("spec,expect", [
    ("in+marathi", "कखगटठडपबमर"),     # Devanagari (InScript)
    ("in+tam", "கசடதபமர"),          # Tamil
    ("ru", "йцукенфыва"),           # Cyrillic
    ("ara", "ضصثقفشسيب"),           # Arabic
])
def test_a_layout_yields_its_own_script(spec, expect):
    got = chars(spec)
    missing = [c for c in expect if c not in got]
    assert not missing, f"{spec}: {missing} not on the keyboard"


def test_an_unknown_layout_fails_cleanly():
    code, _, err = run("no-such-layout")
    assert code != 0 and "does not know" in err
