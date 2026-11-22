"""Undo/redo in the text editor is wired from the document store to the UI."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = (ROOT / "shani/Services/TextDocs.qml").read_text()
PANEL = (ROOT / "shani/Modules/TextEditor/TextEditorPanel.qml").read_text()


def test_document_store_has_bounded_undo_history():
    assert "function undo()" in DOCS and "function redo()" in DOCS
    assert "d.history.push(d.text)" in DOCS
    assert "d.future.length = 0" in DOCS  # a new edit clears the redo stack
    assert "history.length > 300" in DOCS  # bounded, no unbounded growth
    assert "syncHistory()" in DOCS
    assert "canUndo" in DOCS and "canRedo" in DOCS


def test_panel_wires_buttons_and_shortcuts():
    assert "function undo() { win.showText(TextDocs.undo()); }" in PANEL
    assert "function redo() { win.showText(TextDocs.redo()); }" in PANEL
    assert "e.key === Qt.Key_Z" in PANEL
    assert "e.key === Qt.Key_Y" in PANEL
    assert 'icon: "edit-undo"' in PANEL and 'icon: "edit-redo"' in PANEL
    # writing restored text must not feed a new history entry
    assert "win.loading = true;" in PANEL
    assert "onTextChanged: { if (!win.loading) TextDocs.setText(text);" in PANEL
