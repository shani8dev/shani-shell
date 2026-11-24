"""Static guards for the five low-risk editor/viewer fixes picked up from the
competitive research pass (Kate/gedit and GNOME Papers/Evince).

Every test maps to one fix:
  1. Editor: reopen the last closed tab (Ctrl+Shift+T), keeping its edits.
  2. Editor: Ctrl+Tab / Ctrl+PageUp / Ctrl+PageDown cycle open tabs.
  3. Editor: Ctrl+H seeds Replace with the current selection (as Ctrl+F does).
  4. Viewer: Ctrl+O opens a PDF, and the empty/error state offers the same.
  5. Viewer: opening a new document clears stale search/page fields and hides
     the search bar when nothing is open.

Runtime QML behaviour is not exercised here, matching the other static guards.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EDITOR = (ROOT / "shani/Modules/TextEditor/TextEditorPanel.qml").read_text(
    encoding="utf-8"
)
READER = (ROOT / "shani/Modules/PdfReader/PdfReader.qml").read_text(encoding="utf-8")


def block(src, anchor):
    """From `anchor` up to the brace that closes the item it opens."""
    pos = src.index(anchor)
    start = src.index("{", pos)
    depth = 0
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[pos : i + 1]
    raise AssertionError("unclosed block at " + anchor)


def test_editor_reopens_last_closed_tab_from_a_saved_snapshot():
    # closeTab() keeps a reference to the doc object, and reopenTab() splices
    # it back at its old index - unsaved text, history and bookmarks survive.
    close = block(EDITOR, "function closeTab(i)")
    assert "win.lastClosed = { index: i, doc: TextDocs.docs[i] }" in close
    reopen = block(EDITOR, "function reopenTab()")
    assert "list.splice(at, 0, last.doc)" in reopen
    assert "TextDocs.show(at)" in reopen
    assert "e.key === Qt.Key_T && shift" in block(EDITOR, "function shortcut(e)")


def test_editor_has_modifier_tab_and_page_keys_for_tab_navigation():
    # Ctrl+Tab and Ctrl+PageUp/PageDown move between tabs. Plain Tab stays a
    # snippet trigger / focus key (its handler excludes the Ctrl modifier).
    shortcut = block(EDITOR, "function shortcut(e)")
    assert "e.key === Qt.Key_Tab && TextDocs.docs.length > 1" in shortcut
    assert "e.key === Qt.Key_PageDown || e.key === Qt.Key_PageUp" in shortcut
    assert "% TextDocs.docs.length" in shortcut


def test_editor_replace_seeds_the_field_from_the_selection():
    # Kate/gedit's Replace opens with the selected text, not an empty field.
    shortcut = block(EDITOR, "function shortcut(e)")
    key_h = next(line for line in shortcut.splitlines() if "Qt.Key_H" in line)
    assert "findField.text = edit.selectedText" in key_h


def test_reader_can_open_a_pdf_from_a_shortcut_and_the_empty_state():
    # The reader had no open action at all: no way to change document without
    # going through the desktop file. Ctrl+O and the empty/error card now
    # share one pick() helper picking a PDF path.
    assert "function pick()" in READER
    assert 'mode: "open", filters: ["pdf"]' in READER
    assert "e.key === Qt.Key_O && (e.modifiers & Qt.ControlModifier)" in READER
    empty = block(
        READER,
        'ColumnLayout {\n                            visible: !PdfViewer.loading && PdfViewer.current === ""',
    )
    assert "onClicked: win.pick()" in empty


def test_reader_clears_stale_search_and_hides_the_bar_with_no_document():
    # PdfViewer.open() resets searchText; the QML fields did not follow, so a
    # new document showed the old query and page number. The bar is also
    # hidden until a document is shown.
    changed = block(READER, "function onFileChanged()")
    assert 'if (searchField) searchField.text = ""' in changed
    assert 'if (jumpField) jumpField.text = ""' in changed
    # the search bar is the RowLayout enclosing that field; it must carry a
    # "visible: PdfViewer.shown" guard before the field's declaration
    assert "visible: PdfViewer.shown" in READER[: READER.index("id: searchField")]
