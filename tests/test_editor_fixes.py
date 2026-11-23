"""Pass-21 document-workflow fixes: regex replace captures, Ctrl+F seeding, bookmark persistence."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PANEL = (ROOT / "shani/Modules/TextEditor/TextEditorPanel.qml").read_text()
DOCS = (ROOT / "shani/Services/TextDocs.qml").read_text()


def test_regex_replace_expands_capture_groups():
    """replaceAll passes the replacement string straight to String.replace so $1/$2 expand."""
    fn = PANEL.split("function replaceAll()", 1)[1].split("\n    }", 1)[0]
    assert "edit.text.replace(re, replaceField.text)" in fn
    assert "() => replaceField.text" not in fn  # old literal-inserting callback is gone


def test_ctrl_f_seeds_find_field_from_selection():
    """Ctrl+F copies the current selection into the find field before focusing it."""
    line = next(l for l in PANEL.splitlines() if "e.key === Qt.Key_F" in l)
    assert "findField.text = edit.selectedText" in line
    assert "forceActiveFocus" in line


def test_bookmarks_persist_in_session():
    """Session JSON carries a path->bookmarks map and restores it into each loaded doc."""
    save = DOCS.split("function saveSession()", 1)[1].split("\n    }", 1)[0]
    assert "bookmarks[d.path] = d.bookmarks.slice()" in save
    assert "bookmarks: bookmarks" in save
    # backward-compatible read: a missing/invalid bookmarks field becomes {}
    assert "data.bookmarks" in DOCS
    assert 'root.pendingBookmarks = b && typeof b === "object"' in DOCS
    # restored onto the doc as it loads (opens are async)
    assert "function takeBookmarks(path)" in DOCS
    assert "bookmarks: root.takeBookmarks(" in DOCS
