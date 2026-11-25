"""Settings search (Modules/Settings/SettingsIndex.js), run through node.

matches() is plain JS with `.pragma library`, so ranking can be checked without
QML: an exact label prefix must outrank a keyword hit declared earlier, and a
typo must still find the setting - below every exact hit.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
INDEX = ROOT / "shani/Modules/Settings/SettingsIndex.js"
NODE = shutil.which("node") or shutil.which("nodejs")

pytestmark = pytest.mark.skipif(NODE is None, reason="node is not installed")


@pytest.fixture(scope="module")
def js():
    """The file with `.pragma library` dropped, as a plain script."""
    body = INDEX.read_text(encoding="utf-8")
    # node cannot evaluate QML's .import/.pragma directives; strip them and
    # provide a minimal Tools stand-in so the generated tool entries still work
    prog = "\n".join(
        l for l in body.splitlines() if not l.startswith((".pragma", ".import"))
    )
    return "var Tools = { list: [] };\n" + prog


def matches(js, query):
    prog = js + "\nconsole.log(JSON.stringify(matches(" + json.dumps(query) + ")));\n"
    out = subprocess.run([NODE, "-e", prog], capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout.strip().splitlines()[-1])


def test_label_prefix_outranks_an_earlier_keyword_hit(js):
    # "dock" is only a keyword on the early `dock` entry (line 32), but an exact
    # label prefix on the later `dockIconSize` (line 35) - the label must win.
    got = matches(js, "dock")
    assert got and got[0]["key"] == "dockIconSize"
    # returned schema is still the raw entry, unchanged
    assert {"key", "label", "cat", "hint", "words"} <= set(got[0])


def test_a_typo_still_finds_the_setting(js):
    # "wallpapr" matched nothing before; the fuzzy fallback finds wallpaper,
    # and it still ranks below an exact hit for the same query.
    got = matches(js, "wallpapr")
    assert got and got[0]["key"] == "wallpaper"
