"""Text Editor gaps: typing, search options, bookmarks, goto, session, highlights."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PANEL = (ROOT / "shani/Modules/TextEditor/TextEditorPanel.qml").read_text()
DOCS = (ROOT / "shani/Services/TextDocs.qml").read_text()


def test_smart_indent_and_bracket_autoclose():
    assert "function handleAutoclose(e)" in PANEL
    assert 'closeOf(ch) { return ch === "(" ? ")"' in PANEL
    assert "const extra = /[\\{\\[\\(]\\s*$/.test(line)" in PANEL
    assert "win.handleAutoclose(e)" in PANEL


def test_find_has_case_whole_word_and_regex_options():
    for prop in ("caseSensitive", "wholeWord", "useRegex"):
        assert "property bool " + prop in PANEL
    assert "function searchRegex(q)" in PANEL
    assert "function findMatches(hay, q)" in PANEL
    assert 'text: "Aa"' in PANEL and 'text: ".*"' in PANEL
    assert "win.matchOffsets" in PANEL  # live highlights and search share one matcher


def test_bookmarks_ctrl_b_and_previous_next():
    assert "function toggleBookmark(line)" in DOCS
    assert "function nextBookmark(from, delta)" in DOCS
    assert "e.key === Qt.Key_B" in PANEL
    assert "TextDocs.bookmarks()" in PANEL  # gutter markers


def test_go_to_line_ui():
    assert "property bool gotoOpen" in PANEL
    assert "function submitGoto()" in PANEL
    assert "e.key === Qt.Key_G" in PANEL
    assert "id: gotoField" in PANEL


def test_session_restore_across_restarts():
    assert "sessionFile" in DOCS
    assert "function restoreSession()" in DOCS
    assert "function saveSession()" in DOCS
    assert "onExited: root.restoreSession()" in DOCS
    assert "Component.onCompleted: sessionDir.running = true" in DOCS


def test_current_line_and_matching_brace_highlight():
    assert "function matchBrace(pos)" in PANEL
    assert "property int bracePos: win.matchBrace" in PANEL
    assert "Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)" in PANEL


def test_textmate_theme_chooser_and_toggle():
    assert "id: themeDialog" in PANEL
    assert "model: TextMate.themes" in PANEL
    assert "Settings.data.textmateEnabled" in PANEL
    assert "TextMate.themePath = modelData.path" in PANEL
