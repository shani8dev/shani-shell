"""Static checks for the Teleprompter cross-wiring: reach it from the editor,
notes and translator, and send its first line back to Translate.

There is no QML runtime here, so each check reads the source of the window it
guards. The clipboard is the channel between windows (no new service/bridge).
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TE = (ROOT / "shani/Modules/TextEditor/TextEditorPanel.qml").read_text()
NOTES = (ROOT / "shani/Modules/Notes/NotesPanel.qml").read_text()
TR = (ROOT / "shani/Modules/Translate/TranslateWindow.qml").read_text()
TP = (ROOT / "shani/Modules/Teleprompter.qml").read_text()


def _fn(src, name):
    """Body of a QML function, up to its closing brace at the same indent."""
    return src.split("function " + name, 1)[1].split("\n    }", 1)[0]


def test_text_editor_present_copies_document_and_opens_teleprompter():
    """Ctrl+Shift+P (and the toolbar button) hand the document to the prompter."""
    present = _fn(TE, "present()")
    assert "Quickshell.clipboardText = edit.text;" in present
    assert "Ui.teleprompter = true;" in present
    assert "e.key === Qt.Key_P && shift" in TE
    assert 'tip: "Present (Ctrl+Shift+P)"' in TE


def test_notes_present_note_copies_open_note_and_opens_teleprompter():
    """The detail header's Present note action uses the same clipboard channel."""
    present = _fn(NOTES, "presentNote()")
    assert "Quickshell.clipboardText = Services.QuickNotes.text;" in present
    assert "Ui.teleprompter = true;" in present
    assert 'text: Tr.t("Present note")' in NOTES


def test_translate_prompter_copies_result_and_opens_teleprompter():
    """The Prompter button sends only a finished translation, not an error."""
    line = next(l for l in TR.splitlines() if 'Tr.t("Prompter")' in l)
    assert "Quickshell.clipboardText = win.result" in line
    assert "Ui.teleprompter = true" in line
    assert 'win.result !== "" && win.error === ""' in line


def test_teleprompter_prefills_from_clipboard_on_open():
    """On open it takes the clipboard text but never destroys the user's clipboard."""
    assert "onVisibleChanged: if (visible) win.prefillFromClipboard()" in TP
    prefill = _fn(TP, "prefillFromClipboard()")
    assert "win.paste()" in prefill
    assert 'Quickshell.clipboardText = ""' not in prefill
    # paste() is the existing reader; it stays the single place that sets text
    assert "Quickshell.clipboardText ||" in _fn(TP, "paste()")


def test_teleprompter_copy_first_line_is_honest():
    """Translate doesn't consume a clipboard handoff, so the action only copies."""
    send = _fn(TP, "copyFirstLineForTranslation()")
    assert 'split("\\n")[0]' in send
    assert "Quickshell.clipboardText = first;" in send
    assert "Ui.translate = true" not in send
    assert "Copy first line for translation" in TP
