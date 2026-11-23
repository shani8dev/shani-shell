"""Three launcher search-relevance regressions, one test each.

The ranking lives in QML (not runnable here) and its fuzzy helper is plain JS
(run through node, as in test_calc_js.py); the desktop entries come from
bin/shani. All three checks are small so a regression names the exact line.
"""

import importlib.machinery
import importlib.util
import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
LAUNCHER = ROOT / "shani/Modules/Launcher/Launcher.qml"
FUZZY = ROOT / "shani/Modules/Launcher/Fuzzy.js"
NODE = shutil.which("node") or shutil.which("nodejs")


def load_cli():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(ROOT / "bin/shani"))
    spec = importlib.util.spec_from_loader("shani_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


cli = load_cli()
launcher = LAUNCHER.read_text(encoding="utf-8")


def test_usage_breaks_ties_only_inside_a_relevance_class():
    # x.s is 100/80/60/50/40/30/25/20; usage must never move a result across
    # those classes, so it is added after multiplying the class score.
    assert re.search(
        r"s:\s*x\.s\s*\*\s*1000\s*\+\s*Math\.min\(15,\s*used\(x\.a\)\)", launcher
    )
    assert "x.s + Math.min(15, used(x.a))" not in launcher


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_acronyms_match_an_app_name():
    js = "\n".join(
        l
        for l in FUZZY.read_text(encoding="utf-8").splitlines()
        if not l.startswith(".pragma")
    )
    out = subprocess.run(
        [NODE, "-e", js + "\nconsole.log(JSON.stringify(initials('Media Player')));\n"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 0, out.stderr
    assert json.loads(out.stdout.strip()) == "mp"
    # the launcher uses that helper as a 50-point class, below an inside match
    assert re.search(
        r"Fuzzy\.initials\(a\.name\)\.startsWith\(q\)\s*\)\s*\n\s*return 50;", launcher
    )


def test_first_party_desktop_entries_carry_search_words():
    entry = cli.desktop_entry("media-player")
    assert "GenericName=Media Player" in entry
    keywords = [l for l in entry.splitlines() if l.startswith("Keywords=")]
    assert len(keywords) == 1 and keywords[0].endswith(";")
    assert "music" in keywords[0] and "video" in keywords[0]
    assert "GenericName=File Manager" in cli.desktop_entry("files")
