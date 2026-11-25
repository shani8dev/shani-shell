"""Static checks that words found in Lens, the editor and Translate reach the Dictionary.

There is no QML runtime here: each check reads the source of the surface it
guards. All three surfaces use the same handoff — put the word on the clipboard,
open the Dictionary with the Ui.dictionary flag — because Dictionary already
seeds its search box from the clipboard when it opens.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LENS = (ROOT / "shani/Modules/Lens/LensPanel.qml").read_text()
EDITOR = (ROOT / "shani/Modules/TextEditor/TextEditorPanel.qml").read_text()
TRANSLATE = (ROOT / "shani/Modules/Translate/TranslateWindow.qml").read_text()
DICT = (ROOT / "shani/Modules/Dictionary.qml").read_text()


def _section(source, start_marker, end_marker):
    start = source.index(start_marker)
    return source[start : source.index(end_marker, start)]


def test_lens_define_action_hands_the_selection_to_the_dictionary():
    """Define copies the read text, opens Dictionary, and closes the Lens card."""
    action = _section(LENS, "function defineSelection()", "MouseArea { objectName")
    assert 'const word = String(Lens.text || "").trim();' in action
    assert 'if (word === "") return;' in action
    assert "Quickshell.clipboardText = word;" in action
    assert "Ui.dictionary = true;" in action
    assert "Lens.close();" in action
    assert 'Button { text: Tr.t("Define")' in LENS
    assert "onClicked: win.defineSelection()" in LENS


def test_editor_look_up_word_action_uses_the_current_selection():
    """The toolbar action is enabled only with a selection and opens Dictionary."""
    action = _section(EDITOR, "function lookUpWord()", "function submitGoto()")
    assert "const word = edit.selectedText.trim();" in action
    assert "Quickshell.clipboardText = word;" in action
    assert "Ui.dictionary = true;" in action
    assert 'tip: Tr.t("Look up word")' in EDITOR
    assert "enabled: win.canDefine" in EDITOR
    assert 'win.canDefine = edit.selectedText.trim() !== "";' in EDITOR


def test_translate_has_a_dictionary_button_next_to_the_source_field():
    """The source text, not the translation, is the word handed over."""
    action = _section(TRANSLATE, "function lookUp()", "function checkEndpoint()")
    assert "const word = input.text.trim();" in action
    assert "Quickshell.clipboardText = word;" in action
    assert "Ui.dictionary = true;" in action
    button = 'Button { text: Tr.t("Dictionary"); flat: true; enabled: input.text.trim() !== ""; onClicked: win.lookUp() }'
    assert button in TRANSLATE
    # next to the source pane: before, not after, the result pane
    assert TRANSLATE.index(button) < TRANSLATE.index("id: outText")


def test_dictionary_seeds_from_clipboard_once_then_clears_it():
    """The clipboard is a one-shot handoff; the window still opens on Ui.dictionary."""
    assert "visible: Ui.dictionary" in DICT
    handler = _section(DICT, "onVisibleChanged: {", "Item {")
    assert 'const seed = String(Quickshell.clipboardText || "").trim();' in handler
    assert 'if (visible && win.query === "" && seed !== "")' in handler
    assert "win.query = seed;" in handler
    assert 'Quickshell.clipboardText = "";' not in handler
