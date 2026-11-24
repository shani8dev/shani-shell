"""Wave 5 editor: smart indent, bracket/quote pairs, and Markdown preview.

The QML hooks are pinned statically (these files are never loaded by pytest);
the small bits of logic are mirrored here in Python so their edge cases are
checked without a QML runtime, as in test_editor_font_status.py.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QML = ROOT / "shani/Modules/TextEditor/TextEditorPanel.qml"
PANEL = QML.read_text(encoding="utf-8")


# ---- static hooks -----------------------------------------------------------


def test_prior_wave_features_survive():
    for hook in (
        "function insertDateTime()",
        'icon: "entry-calendar"',
        "Qt.formatDateTime(new Date()",
        'icon: "preferences-desktop-font"',
        "function setFontFamily(f)",
        "Qt.fontFamilies()",
        "text-editor-font.json",
        "function trySnippet()",
        "readonly property var snippets",
    ):
        assert hook in PANEL, hook


def test_typing_helpers_are_present_in_the_existing_handler():
    for hook in (
        "function closeOf(ch)",
        "function indentUnit(indent)",
        "function indentOnEnter(line, next)",
        "function handleAutoclose(e)",
        "win.handleAutoclose(e)",
        "Qt.Key_Return && !(e.modifiers & Qt.ControlModifier)",
        "edit.select(a + 1, b + 1)",
        '")]}".indexOf(c) >= 0',
    ):
        assert hook in PANEL, hook


def test_markdown_preview_is_wired_to_toolbar_keyboard_and_a11y():
    for hook in (
        "property bool markdownPreview: false",
        'Tr.t("Markdown preview")',
        "function toggleMarkdownPreview()",
        "e.key === Qt.Key_M && shift",
        "id: mdFlick",
        "visible: win.markdownPreview && TextDocs.docs.length > 0",
        "model: win.previewRows",
        "Accessible.role: Accessible.Document",
        "Keys.onPressed: e => {",
        "onLinkActivated: url => win.openMarkdownLink(url)",
        "visible: win.lineNumbers && !win.markdownPreview",
        "visible: TextDocs.docs.length > 0 && !win.markdownPreview",
    ):
        assert hook in PANEL, hook


def test_markdown_renderer_needs_no_dependency_and_uses_theme():
    assert "function markdownRows(text)" in PANEL
    assert "function markdownInline(s)" in PANEL
    assert "function mdRow(kind, html, extra)" in PANEL
    assert "function openMarkdownLink(url)" in PANEL
    assert "https?:\\/\\/" in PANEL  # only safe link schemes open
    assert "Theme.mono" in PANEL and "Theme.hover" in PANEL
    assert "import" not in [
        line.strip()
        for line in PANEL.splitlines()
        if "markdown" in line.lower() and line.strip().startswith("import")
    ]
    for kind in ("heading", "blank", "rule", "list", "quote", "code", "para"):
        assert '"' + kind + '"' in PANEL, kind


# ---- pure logic: smart indent -----------------------------------------------


def indent_unit(indent):
    return "\t" if "\t" in indent else "    "


def indent_on_enter(line, next_char):
    indent = re.match(r"^[ \t]*", line).group(0)
    extra = indent_unit(indent) if re.search(r"[{\[(]\s*$", line) else ""
    if extra and next_char and next_char in "}]":
        return "\n" + indent + extra + "\n" + indent
    return "\n" + indent + extra


def caret_after(pos, inserted):
    body_end = inserted.find("\n", 1)
    return pos + (body_end if body_end >= 0 else len(inserted))


def test_indent_continues_leading_whitespace():
    assert indent_on_enter("hello", "") == "\n"
    assert indent_on_enter("  hello", "") == "\n  "
    assert indent_on_enter("\thello", "") == "\n\t"
    assert indent_on_enter("", "") == "\n"


def test_indent_opens_a_deeper_level_and_keeps_the_files_unit():
    assert indent_on_enter("    if (x) {", "") == "\n        "
    assert indent_on_enter("    if (x) [", "") == "\n        "
    assert indent_on_enter("    call(", "") == "\n        "
    assert indent_on_enter("\tfunction () {", "") == "\n\t\t"
    assert indent_on_enter("\t{   ", "") == "\n\t\t"


def test_indent_leaves_an_empty_body_before_an_existing_closer():
    body = indent_on_enter("  if (x) {", "}")
    assert body == "\n      \n  "
    assert body.endswith("\n  ")
    # the caret lands just after the body, before the pre-existing closer
    assert caret_after(10, body) == 10 + body.find("\n", 1)
    plain = indent_on_enter("    hello", "x")
    assert caret_after(3, plain) == 3 + len(plain)


# ---- pure logic: bracket and quote pairs ------------------------------------


def close_of(ch):
    return {"(": ")", "[": "]", "{": "}"}.get(ch, ch)


def autoclose(text, pos, selection, ch):
    """Mirror of win.handleAutoclose's pair branches. Returns (text, cursor, sel)."""
    a, b = selection
    if len(ch) == 1 and ch in ")]}" and a == b and text[pos : pos + 1] == ch:
        return text, pos + 1, (a, b)
    if len(ch) == 1 and ch in "([{\"'":
        close = close_of(ch)
        if b > a:
            out = text[:b] + close + text[b:]
            out = out[:a] + ch + out[a:]
            return out, b + 1, (a + 1, b + 1)
        return text[:pos] + ch + close + text[pos:], pos + 1, (a, b)
    return text, pos, selection


def backspace_pair(text, pos):
    if 0 < pos < len(text):
        opener = text[pos - 1]
        if close_of(opener) == text[pos] and opener in "([{\"'":
            return text[: pos - 1] + text[pos + 1 :], True
    return text, False


def test_pairs_are_inserted_with_the_cursor_between_them():
    for ch, pair in (("(", "()"), ("[", "[]"), ("{", "{}"), ('"', '""'), ("'", "''")):
        text, cursor, _ = autoclose("ab", 2, (2, 2), ch)
        assert text == "ab" + pair
        assert cursor == 3


def test_typing_a_closer_steps_over_instead_of_stacking():
    for ch in (")", "]", "}"):
        text, cursor, _ = autoclose("(" + ch, 1, (1, 1), ch)
        assert text == "(" + ch
        assert cursor == 2


def test_typing_a_pair_wraps_a_selection():
    text, _, sel = autoclose("abcdef", 6, (1, 4), "(")
    assert text == "a(bcd)ef"
    assert sel == (2, 5)
    assert text[sel[0] : sel[1]] == "bcd"


def test_backspace_removes_a_pair_as_a_unit():
    assert backspace_pair("a()b", 2) == ("ab", True)
    assert backspace_pair('a""b', 2) == ("ab", True)
    assert backspace_pair("a(b", 2) == ("a(b", False)


# ---- pure logic: Markdown rows ----------------------------------------------


def md_row(kind, html, extra=None):
    row = {"kind": kind, "html": html, "level": 0, "depth": 0, "size": 1, "mono": False}
    row.update(extra or {})
    return row


def markdown_inline(s):
    out = (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", out)
    out = re.sub(r"(^|[^*])\*([^*]+)\*", r"\1<i>\2</i>", out)
    out = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', out)
    return out


def markdown_rows(text):
    rows, fenced = [], False
    sizes = [1.7, 1.45, 1.25, 1.12, 1.04, 1]
    for line in text.split("\n"):
        if re.match(r"^\s*```", line):
            fenced = not fenced
            rows.append(md_row("blank", ""))
            continue
        if fenced:
            rows.append(
                md_row("code", markdown_inline(line), {"mono": True, "size": 0.92})
            )
            continue
        if line.strip() == "":
            rows.append(md_row("blank", ""))
            continue
        heading = re.match(r"^(#{1,6})\s+(.*)$", line)
        if heading:
            level = len(heading.group(1))
            rows.append(
                md_row(
                    "heading",
                    markdown_inline(heading.group(2)),
                    {"level": level, "size": sizes[level - 1], "bold": True},
                )
            )
            continue
        if re.match(r"^\s*(-{3,}|\*{3,}|_{3,})\s*$", line):
            rows.append(md_row("rule", ""))
            continue
        bullet = re.match(r"^(\s*)[-+*]\s+(.*)$", line)
        if bullet:
            rows.append(
                md_row(
                    "list",
                    "• " + markdown_inline(bullet.group(2)),
                    {"depth": min(4, len(bullet.group(1)) // 2)},
                )
            )
            continue
        ordered = re.match(r"^(\s*)(\d+)[.)]\s+(.*)$", line)
        if ordered:
            rows.append(
                md_row(
                    "list",
                    ordered.group(2) + ". " + markdown_inline(ordered.group(3)),
                    {"depth": min(4, len(ordered.group(1)) // 2)},
                )
            )
            continue
        quote = re.match(r"^\s*>\s?(.*)$", line)
        if quote:
            rows.append(md_row("quote", markdown_inline(quote.group(1))))
            continue
        rows.append(md_row("para", markdown_inline(line)))
    return rows


SAMPLE = """# Title

Some **bold** and *ital* with `code`.

- one
  - two
1. first
> quoted
---
```
var x = 1;
```
[link](https://example.com)""".rstrip("\n")  # a trailing newline is a blank row


def test_inline_markdown_is_commonmark_subset_and_escapes_html():
    assert markdown_inline("**bold**") == "<b>bold</b>"
    assert markdown_inline("*ital*") == "<i>ital</i>"
    assert markdown_inline("`code`") == "<code>code</code>"
    assert markdown_inline("[x](https://a.test)") == '<a href="https://a.test">x</a>'
    assert markdown_inline('<script>&"') == "&lt;script&gt;&amp;&quot;"
    assert markdown_inline("a_b_c") == "a_b_c"  # no accidental underscore markup


def test_rows_cover_heading_para_lists_quote_rule_code_and_link():
    rows = markdown_rows(SAMPLE)
    kinds = [r["kind"] for r in rows]
    assert kinds == [
        "heading",
        "blank",
        "para",
        "blank",
        "list",
        "list",
        "list",
        "quote",
        "rule",
        "blank",
        "code",
        "blank",
        "para",
    ]
    assert rows[0]["level"] == 1 and rows[0]["size"] == 1.7
    assert "<b>bold</b>" in rows[2]["html"] and "<i>ital</i>" in rows[2]["html"]
    assert "<code>code</code>" in rows[2]["html"]
    assert rows[4]["html"] == "• one" and rows[4]["depth"] == 0
    assert rows[5]["html"] == "• two" and rows[5]["depth"] == 1
    assert rows[6]["html"] == "1. first"
    assert rows[7]["kind"] == "quote"
    assert rows[8]["kind"] == "rule"
    assert rows[10]["kind"] == "code" and rows[10]["mono"] is True
    assert rows[12]["html"] == '<a href="https://example.com">link</a>'


def test_heading_levels_and_fenced_code_are_bounded():
    rows = markdown_rows("###### deep\n####### not a heading\n```\na < b\n```\nafter")
    assert rows[0]["level"] == 6 and rows[0]["size"] == 1
    assert rows[1]["kind"] == "para"
    assert rows[3]["html"] == "a &lt; b" and rows[3]["mono"] is True
    assert rows[5]["kind"] == "para"


def safe_link(url):
    return re.match(r"^(https?://|mailto:)", url, re.I) is not None


def test_only_safe_link_schemes_are_opened():
    assert safe_link("https://example.com")
    assert safe_link("HTTP://example.com")
    assert safe_link("mailto:a@b.test")
    assert not safe_link("javascript:alert(1)")
    assert not safe_link("file:///etc/passwd")
