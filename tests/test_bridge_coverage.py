"""Every bridge is a Python program with a docstring and a test.

A bridge that nothing covers is how Feeds and Mail shipped broken for months:
the window showed nothing and no test said so. This keeps the list honest - a new
bridge without a test fails here, and every bridge is at least parsed.
"""

import ast
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGES = sorted((ROOT / "bridge").glob("*.py"))
TESTS = sorted((ROOT / "tests").glob("test_*.py"))

# bridges that need a live session bus or hardware: the shell suite drives them
NEEDS_A_SESSION = {
    "chronoa-bridge",  # the D-Bus face of the shell
    "appmenu",  # AT-SPI
    "appmenu-registrar",  # owns a bus name
}


def stem(p):
    return p.stem.replace("-", "_")


def covered(name):
    """A test file that mentions the bridge by module name or by file name."""
    for t in TESTS:
        text = t.read_text(encoding="utf-8", errors="replace")
        if f"bridge/{name}.py" in text:
            return t
        if re.search(r"import\s+" + re.escape(stem(Path(name))) + r"\b", text):
            return t
        if f'"{name}.py"' in text:
            return t
    return None


def test_there_are_bridges():
    assert len(BRIDGES) > 50


@pytest.mark.parametrize("path", BRIDGES, ids=lambda p: p.name)
def test_the_bridge_parses(path):
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))


@pytest.mark.parametrize("path", BRIDGES, ids=lambda p: p.name)
def test_the_bridge_says_what_it_is_for(path):
    """Every bridge's first string is its docstring, and it tells the next
    person what the program does and what it needs."""
    tree = ast.parse(path.read_text(encoding="utf-8"))
    doc = ast.get_docstring(tree)
    assert doc and len(doc.strip()) > 40, path.name


@pytest.mark.parametrize("path", BRIDGES, ids=lambda p: p.name)
def test_the_bridge_has_a_test_or_says_why_not(path):
    if path.stem in NEEDS_A_SESSION:
        pytest.skip(f"{path.stem} is driven by the shell suite")
    assert covered(path.stem), f"bridge/{path.stem}.py has no test"


def test_the_needs_a_session_list_is_still_those():
    """If a bridge here has gained a test, take it off the list."""
    for name in NEEDS_A_SESSION:
        assert (ROOT / "bridge" / f"{name}.py").exists(), name
