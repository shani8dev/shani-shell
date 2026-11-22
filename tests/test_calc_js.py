"""The launcher's calculator (Modules/Launcher/Calc.js), run through node.

The calculator is plain JS with `.pragma library`, so it can be run directly -
which is the only way to check the parts a UI cannot show: that a sum is
answered at all, that a name is never evaluated as code, and that a word is
not a sum. The launcher's own tests can only see the rendered title.
"""

import json
import shutil
import subprocess
import textwrap
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
CALC = ROOT / "shani/Modules/Launcher/Calc.js"
NODE = shutil.which("node") or shutil.which("nodejs")

pytestmark = pytest.mark.skipif(NODE is None, reason="node is not installed")


@pytest.fixture(scope="module")
def js():
    """The file with `.pragma library` dropped, as a plain script."""
    body = CALC.read_text(encoding="utf-8")
    return "\n".join(l for l in body.splitlines() if not l.startswith(".pragma"))


def call(js, expr, fn="calc"):
    """One expression through Calc.js, as JSON (a number or null)."""
    prog = (
        js
        + "\nconsole.log(JSON.stringify(typeof "
        + fn
        + " === 'function' ? "
        + fn
        + "("
        + json.dumps(expr)
        + ") : null));\n"
    )
    out = subprocess.run([NODE, "-e", prog], capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout.strip().splitlines()[-1])


# ---- the arithmetic a person types ----------------------------------------


@pytest.mark.parametrize(
    "expr,want",
    [
        ("2+2", 4),
        ("2+2*3", 8),  # precedence, not left to right
        ("(2+2)*3", 12),
        ("10/4", 2.5),
        ("7-9", -2),
        ("2*(3+4)^2", 98),  # the launcher's own example
        ("2^10", 1024),
        ("-5+3", -2),
        ("1e3", 1000),
        (".5+.25", 0.75),
        ("10%3", 1),
    ],
)
def test_the_sum_is_answered(js, expr, want):
    assert call(js, expr) == want


@pytest.mark.parametrize(
    "expr",
    [
        "2+",
        "2**",
        "((2+2)",
        "2 2",
        "",
        " ",
        "2..3",
        "abc",
        "1/0",
    ],
)
def test_what_is_not_a_sum_is_null(js, expr):
    assert call(js, expr) is None


# ---- names are functions, never code --------------------------------------


@pytest.mark.parametrize(
    "expr,want",
    [
        ("sqrt(16)", 4),
        ("abs(-3)", 3),
        ("round(2.6)", 3),
        ("floor(2.9)", 2),
        ("ceil(2.1)", 3),
        ("min(3, 7)", 3),
        ("max(3, 7)", 7),
        ("pow(2, 8)", 256),
        ("log(100)", 2),           # base 10
    ("ln(10)", 2.30258509299),    # natural, not log10 (which would be 1)
    ],
)
def test_the_documented_names_work(js, expr, want):
    assert call(js, expr) == want


@pytest.mark.parametrize(
    "expr",
    [
        "process.exit(1)",
        "globalThis.x=1",
        'import("fs")',
        'eval("1")',
        "constructor",
        "2; 3",
        "a.b",
        "[1,2]",
    ],
)
def test_a_name_that_is_not_on_the_list_is_refused(js, expr):
    """The calculator is a search box: nothing typed there is ever evaluated."""
    assert call(js, expr) is None


# ---- units and money -------------------------------------------------------


def test_a_length_conversion_is_recognised(js):
    assert call(js, "5 km in miles", fn="convert") is not None


def test_a_temperature_conversion_is_recognised(js):
    got = call(js, "100 c in f", fn="convert")
    assert got is not None and abs(got.get("value", 0) - 212) < 0.01


def test_something_that_is_not_a_conversion_is_not(js):
    assert call(js, "hello world", fn="convert") is None


def test_a_currency_phrase_is_recognised(js):
    assert call(js, "100 usd in inr", fn="isCurrency") is True


def test_a_plain_number_is_not_currency(js):
    assert call(js, "100", fn="isCurrency") is False
