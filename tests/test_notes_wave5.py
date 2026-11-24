"""Wave 5 Notes pass: safe Markdown reading view.

Trash/restore, dated versions and the Edit/Preview toggle were already wired in
QuickNotes.qml + NotesPanel.qml; the remaining gap was the preview itself, which
rendered generated HTML with Text.RichText. The reading view now parses the
Markdown subset in QML and paints it with PlainText Text items. Wiring is
checked statically; the shipped parser functions are lifted out of the QML and
run under Node, so the safety properties are exercised, not just grepped.
"""

import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PANEL = (ROOT / "shani/Modules/Notes/NotesPanel.qml").read_text(encoding="utf-8")
MARKDOWN = (ROOT / "shani/Modules/Notes/NotesMarkdown.qml").read_text(encoding="utf-8")
SERVICE = (ROOT / "shani/Services/QuickNotes.qml").read_text(encoding="utf-8")

node = shutil.which("node")
node_mark = pytest.mark.skipif(node is None, reason="node is needed for the QML JS")


def js_func(src, name):
    """One `function name(...) { ... }` from a QML file, braces balanced."""
    m = re.search(r"^    function " + re.escape(name) + r"\(", src, re.M)
    assert m, name
    start = src.index("{", m.end() - 1)
    depth = 0
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[m.start() : i + 1]
    raise AssertionError("unbalanced function " + name)


def node_eval(expr, funcs, prelude=""):
    js = prelude + "\n".join(js_func(MARKDOWN, f) for f in funcs)
    js += "\nconsole.log(JSON.stringify(" + expr + "));\n"
    r = subprocess.run(["node", "-e", js], capture_output=True, text=True, timeout=15)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def section(src, start, end):
    i = src.index(start)
    return src[i : src.index(end, i)]


# ---- the shipped wiring -----------------------------------------------------


def test_reading_view_uses_the_plain_text_parser():
    prev = section(PANEL, "// Reading view:", "// Wiki links")
    assert "NotesMarkdown {" in prev
    assert "markdown: Services.QuickNotes.text" in prev
    assert "textFormat: Text.RichText" not in prev
    assert "markdownHtml(" not in prev
    assert "onWikiLink: name => Services.QuickNotes.jumpTo(name)" in prev
    assert 'onWebLink: url => Quickshell.execDetached(["xdg-open", url])' in prev
    assert "Accessible.role: Accessible.Document" in prev
    assert 'Tr.t("Preview of %1")' in prev
    assert (
        'Shortcut { sequence: "Ctrl+E"; onActivated: win.previewMode = !win.previewMode }'
        in PANEL
    )


def test_parser_draws_every_block_with_plain_text_and_theme_tokens():
    assert "textFormat: Text.PlainText" in MARKDOWN
    assert "Text.RichText" not in MARKDOWN and "<b>" not in MARKDOWN
    for token in (
        "Theme.text",
        "Theme.dim",
        "Theme.accent",
        "Theme.border",
        "Theme.surface1",
        "Theme.font",
        "Theme.mono",
        "Theme.radiusSmall",
    ):
        assert token in MARKDOWN, token
    for name in ("pushWords", "parseInline", "parseMarkdown", "activate"):
        assert "function " + name + "(" in MARKDOWN, name
    assert "signal wikiLink(string name)" in MARKDOWN
    assert "signal webLink(string url)" in MARKDOWN
    assert 'run.target.indexOf("wiki:") === 0' in MARKDOWN
    assert "/^https?:\\/\\//.test(run.target)" in MARKDOWN
    assert "KeyFocus {" in MARKDOWN and "Accessible.Link" in MARKDOWN
    # no evaluation of note text as code
    assert "eval(" not in MARKDOWN


def test_editing_autosave_trash_and_history_stay_wired():
    assert 'visible: Services.QuickNotes.current !== "" && !win.previewMode' in PANEL
    assert (
        "if (text !== Services.QuickNotes.text) Services.QuickNotes.text = text;"
        in PANEL
    )
    assert "Services.QuickNotes.remove(Services.QuickNotes.current" in PANEL
    assert "Services.QuickNotes.restore(modelData)" in PANEL
    assert "Services.QuickNotes.emptyTrash()" in PANEL
    assert "Services.QuickNotes.history(" in PANEL
    assert "Services.QuickNotes.restoreVersion(" in PANEL
    assert "Services.QuickNotes.previewVersion(" in PANEL
    assert "function stepVersion(delta)" in PANEL
    assert "root.snapshot();" in SERVICE


# ---- the actual JS parser, run under node -----------------------------------

PARSER = ["pushWords", "parseInline", "parseMarkdown"]


@node_mark
def test_headings_bold_italic_code_and_inline_links():
    blocks = node_eval(
        "parseMarkdown('# Head\\n\\n**bold** and *it* with `x*y` and [[Target]] and [site](https://e.test)')",
        PARSER,
    )
    assert blocks[0] == {"kind": "heading", "level": 1, "runs": [{"text": "Head"}]}
    runs = blocks[1]["runs"]
    assert {"text": "bold", "bold": True} in runs
    assert {"text": "it", "italic": True} in runs
    assert {"text": "x*y", "code": True} in runs
    assert {"text": "[[Target]]", "target": "wiki:Target"} in runs
    assert {"text": "site", "target": "https://e.test"} in runs


@node_mark
def test_lists_quotes_rules_and_fenced_code():
    blocks = node_eval(
        "parseMarkdown('- [ ] task\\n- [x] done\\n- plain\\n\\n> quote\\n\\n---\\n\\n```\\n<code>\\n```')",
        PARSER,
    )
    assert [b["kind"] for b in blocks] == [
        "list",
        "list",
        "list",
        "quote",
        "rule",
        "code",
    ]
    assert blocks[0]["runs"][0]["text"] == "☐ "
    assert blocks[1]["runs"][0]["text"] == "☑ "
    assert blocks[2]["runs"][0]["text"] == "• "
    assert blocks[3]["runs"][1]["text"] == "quote"
    assert blocks[5]["text"] == "<code>"
    # an unclosed fence keeps the rest of the note as code, never as markup
    assert node_eval("parseMarkdown('```\\n<b>x</b>')", PARSER)[0]["text"] == "<b>x</b>"


@node_mark
def test_html_and_unknown_link_schemes_stay_plain_data():
    md = "<script>alert(1)</script>\n\n**<b>bold</b>**\n\n[x](javascript:alert(1)) [y](file:///etc/passwd)"
    blocks = node_eval("parseMarkdown(" + json.dumps(md) + ")", PARSER)
    flat = json.dumps(blocks)
    assert "<script>" in flat and "<b>bold</b>" in flat  # as data, not markup
    assert "<a " not in flat and "<i>" not in flat and "<ul>" not in flat
    targets = [
        r.get("target") for b in blocks for r in b.get("runs", []) if "target" in r
    ]
    assert targets == []
    # the unsafe link is inert: its text is shown, no target is generated
    assert any(
        "".join(r["text"] for r in b.get("runs", [])).startswith(
            "x(javascript:alert(1))"
        )
        for b in blocks
    )


@node_mark
def test_activation_only_follows_the_two_declared_schemes():
    prelude = (
        "const seen = [];\n"
        "const doc = { wikiLink: n => seen.push('wiki:' + n), webLink: u => seen.push(u) };\n"
    )
    run = node_eval(
        "(activate({ text: '[[T]]', target: 'wiki:T' }), activate({ target: 'https://e.test' }), activate({ target: 'ftp://e.test' }), seen)",
        [],
        prelude + js_func(MARKDOWN, "activate"),
    )
    assert run == ["wiki:T", "https://e.test"]


# ---- dated versions are newest-first and stepping stays in range -----------


def test_history_command_lists_newest_dated_copy_first(tmp_path):
    m = re.search(r'function history\(id\) \{.*?ls -1t[^"\']*', SERVICE, re.S)
    assert m
    script = re.search(r"'([^']+)'", SERVICE[m.start() : m.start() + 600]).group(1)
    hist = tmp_path / ".history"
    hist.mkdir()
    names = [
        "work__Idea-20261101-090000-000.md",
        "work__Idea-20261103-090000-000.md",
        "work__Idea-20261102-090000-000.md",
        "other-20261104-090000-000.md",
    ]
    for i, name in enumerate(names):
        p = hist / name
        p.write_text(name)
        os.utime(p, (time.time() + i * 60, time.time() + i * 60))
    r = subprocess.run(
        ["sh", "-c", script, "sh", str(tmp_path), "work__Idea"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert r.returncode == 0, r.stderr
    assert r.stdout.splitlines() == [
        str(hist / n) for n in (names[2], names[1], names[0])
    ]
    assert all("other-" not in line for line in r.stdout.splitlines())


@node_mark
def test_step_version_clamps_to_the_visible_history():
    paths = ["h/newest.md", "h/middle.md", "h/oldest.md"]
    prelude = (
        "const seen = [];\n"
        "const Services = { QuickNotes: { historyList: " + json.dumps(paths) + ","
        " previewVersion: p => seen.push(p) } };\n"
        "const win = { historyIndex: -1 };\n"
    )
    fn = js_func(PANEL, "stepVersion")
    js = prelude + fn + "\nconst steps = ["
    js += "stepVersion(1), win.historyIndex, stepVersion(1), win.historyIndex,"
    js += "stepVersion(1), win.historyIndex, stepVersion(1), win.historyIndex,"
    js += "stepVersion(-1), win.historyIndex, JSON.stringify(seen)];"
    js += "\nconsole.log(JSON.stringify(steps));\n"
    r = subprocess.run(["node", "-e", js], capture_output=True, text=True, timeout=15)
    assert r.returncode == 0, r.stderr
    steps = json.loads(r.stdout)
    assert steps[:8] == [True, 0, True, 1, True, 2, True, 2]  # clamped at the end
    assert steps[8:10] == [True, 1]
    assert json.loads(steps[10]) == paths[:3] + [paths[2], paths[1]]
