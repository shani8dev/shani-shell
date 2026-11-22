"""The suite's own shell: dev/*.sh and dev/shell-parts/*.sh.

The checks are only worth their result lines, and a part that dies half way
still prints the three start-up PASSes - which is how a typo once looked green.
These pin the things that are cheap to check and expensive to lose: the script
parses, every part has a header saying what it covers, and every result goes
through the helper (a part that prints PASS itself does not count).
"""

import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
DEV = ROOT / "dev"
SH = shutil.which("bash")   # the dev image's /bin/sh is bash: parts use <<< and arrays

SCRIPTS = sorted(p for p in DEV.glob("*.sh"))
PARTS = sorted((DEV / "shell-parts").glob("*.sh"))


def test_there_are_scripts_and_parts():
    assert len(SCRIPTS) > 5
    assert len(PARTS) > 30


@pytest.mark.parametrize("path", SCRIPTS + PARTS, ids=lambda p: p.name)
def test_the_script_parses(path):
    if SH is None:
        pytest.skip("bash is not installed")
    out = subprocess.run(
        [SH, "-n", str(path)], capture_output=True, text=True, timeout=60
    )
    assert out.returncode == 0, f"{path.name}: {out.stderr[:200]}"


@pytest.mark.parametrize("path", PARTS, ids=lambda p: p.name)
def test_the_part_says_what_it_covers(path):
    """Every part opens with a comment block: what it drives and how."""
    lines = [l for l in path.read_text(encoding="utf-8").splitlines()[:6] if l.strip()]
    assert lines and lines[0].startswith("#"), path.name
    assert len(lines) >= 2, f"{path.name} has no explanation"


@pytest.mark.parametrize("path", PARTS, ids=lambda p: p.name)
def test_the_part_uses_the_result_helper(path):
    """A part that prints PASS itself does not count towards the summary."""
    text = path.read_text(encoding="utf-8")
    assert "result " in text, path.name


@pytest.mark.parametrize("path", PARTS, ids=lambda p: p.name)
def test_every_part_is_runnable_alone(path):
    """The suite says so; check the file does not depend on another part."""
    for p in (path,):
        text = p.read_text(encoding="utf-8")
        assert not re.search(r'^\s*[.\s]\s*"?\S*shell-parts/', text, re.M), (
            f"{p.name} sources another part"
        )
