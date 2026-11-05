"""The "What's new" rule (shani/Services/WhatsNew.js), run in node."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
JS = ROOT / "shani" / "Services" / "WhatsNew.js"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def call(fn, *args):
    prog = JS.read_text().replace(".pragma library", "") + "\nprocess.stdout.write(JSON.stringify(%s));" % fn
    return json.loads(subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout)


def parse(text):
    return call("parseVersion(%s)" % json.dumps(text))


def decide(cur, last):
    return call("shouldShow(%s, %s)" % (json.dumps(cur), json.dumps(last)))


def test_parse_version_takes_the_number_out_of_the_file():
    assert parse("1.4.2\n") == "1.4.2"
    assert parse("shani 2.0\n") == "2.0"
    assert parse("") == ""
    assert parse("  \n") == ""


def test_new_version_is_shown_once():
    assert decide("1.5.0", "1.4.2") == "show"


def test_same_version_is_never_told_again():
    assert decide("1.4.2", "1.4.2") == "none"


def test_first_install_records_silently():
    assert decide("1.4.2", "") == "record"


def test_no_version_file_is_nothing():
    assert decide("", "1.4.2") == "none"


def test_shipped_summary_exists_and_mentions_the_update():
    text = (ROOT / "data" / "whats-new.md").read_text()
    assert "What's new" in text and "FEATURES.md" in text
    assert len(text) > 500
