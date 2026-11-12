"""Common/Highlight.js in node: the colours are right, and nothing is lost.

The editor draws the coloured text under the text being typed, so the one
property that must never break is that stripping the tags gives the input
back, character for character."""
import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
pytestmark = pytest.mark.skipif(not shutil.which("node"), reason="node is not installed")
COLORS = {"comment": "C", "string": "S", "number": "N", "keyword": "K", "heading": "H", "added": "A", "removed": "R"}


def run(calls):
    src = (ROOT / "shani/Common/Highlight.js").read_text().replace(".pragma library", "")
    script = src + "\nconst calls = " + json.dumps(calls) + ";\nconsole.log(JSON.stringify(calls.map(c => c[0] === 'lang' ? langFor(c[1], c[2]) : html(c[1], c[2], " + json.dumps(COLORS) + "))));"
    return json.loads(subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True).stdout)


def plain(html):
    return re.sub(r"<[^>]+>", "", html).replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")


def spans(html):
    return [(color, plain(body)) for color, body in re.findall(r'<span style="color:(\w)">(.*?)</span>', html, re.S)]


SAMPLES = [
    ("def f(x):\n    # a comment with 'quotes' and def\n    return \"a # not a comment\" + str(42)\n", "python"),
    ("#!/bin/sh\nfor f in *.txt; do echo \"$f\" # list\ndone\n", "shell"),
    ("const a = `multi\nline ${x}`; // done\n/* block\n   comment */ let n = 0x1F;\n", "javascript"),
    ("<a href=\"x\">a & b</a><!-- gone -->\n", "html"),
    ("# Title\nsome *text*\n- item\n> quote\n", "markdown"),
    ("--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n same\n", "diff"),
    ("{\"key\": [1, 2.5, true, null], \"s\": \"a\\\"b\"}\n", "json"),
    ("unterminated \"string\nand 'another\n/* open comment", "c"),
    ("", "python"),
    ("tabs\tand <angle> & ampersand\n", "text"),
]


def test_every_character_survives():
    out = run([["html", text, lang] for text, lang in SAMPLES])
    for (text, lang), html in zip(SAMPLES, out):
        assert plain(html) == text, lang


def test_what_gets_which_colour():
    py, sh, js, html, md, diff = run([["html", t, l] for t, l in SAMPLES[:6]])
    assert ("K", "def") in spans(py) and ("K", "return") in spans(py)
    assert ("C", "# a comment with 'quotes' and def") in spans(py)          # nothing inside a comment is coloured again
    assert ("S", '"a # not a comment"') in spans(py) and ("N", "42") in spans(py)
    assert ("K", "for") in spans(sh) and ("C", "# list") in spans(sh) and ("S", '"$f"') in spans(sh)
    assert ("S", "`multi\nline ${x}`") in spans(js) and ("C", "/* block\n   comment */") in spans(js) and ("N", "0x1F") in spans(js)
    assert ("K", "<a") in spans(html) and ("C", "<!-- gone -->") in spans(html) and ("S", '"x"') in spans(html)
    assert ("H", "# Title") in spans(md) and ("C", "> quote") in spans(md)
    assert ("A", "+new") in spans(diff) and ("R", "-old") in spans(diff) and ("K", "@@ -1 +1 @@") in spans(diff)


def test_the_language_is_told_from_the_name_or_the_first_line():
    got = run([["lang", "/x/a.py", ""], ["lang", "/x/Makefile", ""], ["lang", "/x/PKGBUILD", ""], ["lang", "/x/run", "#!/usr/bin/env python3"],
               ["lang", "/x/run", "#!/bin/bash"], ["lang", "/x/notes.txt", ""], ["lang", "/x/shell.qml", ""], ["lang", "/x/config.kdl", ""], ["lang", "/x/a.service", ""]])
    assert got == ["python", "makefile", "shell", "python", "shell", "text", "qml", "kdl", "ini"]
