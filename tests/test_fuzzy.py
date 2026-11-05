"""The launcher's typo-tolerant matching (shani/Modules/Launcher/Fuzzy.js), run in node."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

JS = Path(__file__).resolve().parent.parent / "shani" / "Modules" / "Launcher" / "Fuzzy.js"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def score(name, q):
    prog = JS.read_text().replace(".pragma library", "") + "\nprocess.stdout.write(JSON.stringify(score(words(%s), %s)));" % (json.dumps(name), json.dumps(q))
    return json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)


def test_a_swapped_pair_finds_firefox():
    assert score("Firefox Web Browser", "fierfox") > 0


def test_a_missing_letter_finds_settings():
    assert score("Settings", "settngs") > 0
    assert score("Shell settings", "settngs") > 0


def test_a_typo_while_still_typing():
    assert score("Firefox", "firef") == 0          # a plain prefix: the launcher's own match, not a typo
    assert score("Firefox", "firwf") > 0


def test_ranked_below_the_launchers_exact_prefix_and_inside_matches():
    # Launcher.qml: prefix 100, word prefix 80, inside 60, keywords 40, comment 20
    assert 0 < score("Settings", "settngs") <= 35
    assert 0 < score("Firefox", "firefoks") < score("Settings", "settngs")   # two typos below one


def test_too_far_or_too_short_is_not_a_match():
    assert score("Firefox", "fox") == 0            # short words: no typos forgiven
    assert score("Calculator", "terminal") == 0
    assert score("Files", "fikes") > 0
    assert score("Files", "mikes") == 0            # the first letter is kept
