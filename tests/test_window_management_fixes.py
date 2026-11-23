"""New window-management fixes: stale previews, conflicting rules, bad sizes.

QML functions here are plain JS, so they are lifted out of the source and run in
node (the same pattern as tests/test_window_rules.py). Preview checks are static
because the capture itself needs grim + a compositor.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
WP = (ROOT / "shani/Services/WindowPreview.qml").read_text()
RULES = (ROOT / "shani/Services/WindowRules.qml").read_text()
node = shutil.which("node")

node_only = pytest.mark.skipif(node is None, reason="node is not installed")


def lift(name, params, src):
    m = re.search(
        r"function %s\(%s\) \{(.*?)\n    \}" % (re.escape(name), re.escape(params)),
        src,
        re.S,
    )
    assert m, "%s not found" % name
    return "function %s(%s) {%s\n}\n" % (name, params, m.group(1))


def run_js(src, expr):
    out = subprocess.run(
        [node, "-e", src + "\nprocess.stdout.write(" + expr + ");"],
        capture_output=True,
        text=True,
        check=True,
    )
    return out.stdout


# --- stale preview thumbnails -------------------------------------------------
def test_preview_ignores_capture_from_another_hover():
    m = re.search(r"onStreamFinished: \{(.*?)\n            \}", WP, re.S)
    assert m, "capture onStreamFinished not found"
    body = m.group(1)
    assert "out === cap.pendingFile" in body
    guard = body.index("out === cap.pendingFile")
    assert body.index("root.path = out") > guard  # guard must run before assignment
    assert body.index("root.title = cap.pendingTitle") > guard


def test_preview_clear_invalidates_in_flight_capture():
    clear = WP[WP.index("function clear()") :]
    assert 'cap.pendingFile = ""' in clear


# --- conflicting rules --------------------------------------------------------
@node_only
def test_duplicate_matches_keep_only_the_newest_rule():
    src = lift("uniqueRules", "rules", RULES)
    rules = [
        {"app": "foot", "mode": "floating"},
        {"app": "firefox", "mode": "fullscreen"},
        {"app": "foot", "mode": "tiled"},
    ]
    out = json.loads(run_js(src, "JSON.stringify(uniqueRules(%s))" % json.dumps(rules)))
    assert len(out) == 2
    assert out[0]["app"] == "foot" and out[0]["mode"] == "tiled"
    assert out[1]["app"] == "firefox"


@node_only
def test_rules_for_different_titles_both_survive():
    src = lift("uniqueRules", "rules", RULES)
    rules = [
        {"app": "firefox", "title": "Chats", "mode": "tiled"},
        {"app": "firefox", "title": "Video", "mode": "floating"},
    ]
    out = json.loads(run_js(src, "JSON.stringify(uniqueRules(%s))" % json.dumps(rules)))
    assert len(out) == 2


def test_writer_deduplicates_before_emitting():
    kdl = RULES[
        RULES.index("readonly property string kdl") : RULES.index("onKdlChanged")
    ]
    assert "uniqueRules(" in kdl


# --- a bad size must not invalidate the whole rules file ----------------------
@node_only
def test_nonfinite_size_is_dropped():
    src = lift("kdlRule", "std, r", RULES)
    out = run_js(src, "kdlRule('foot', {width: 'Infinity', height: 800})")
    assert "Infinity" not in out
    assert "default-column-width" not in out
    assert "default-window-height { fixed 800; }" in out
