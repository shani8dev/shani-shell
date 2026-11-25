"""Static checks that the OSK, handwriting pad and Dictionary exchange words.

No QML runtime here: each check reads the source of the surface it guards.
All three surfaces use the established handoff — put the word on the clipboard
and open the Dictionary with Ui.dictionary (the flag the shell's dictionaryOpen
IPC sets) — because Dictionary seeds its box from the clipboard on open. The
return path is the clipboard too, inserted by the OSK's existing Paste key.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KB = (ROOT / "shani/Modules/Osk/Keyboard.qml").read_text()
PAD = (ROOT / "shani/Modules/Osk/WritePad.qml").read_text()
DICT = (ROOT / "shani/Modules/Dictionary.qml").read_text()


def _section(source, start_marker, end_marker):
    start = source.index(start_marker)
    return source[start : source.index("\n    }", start)]


def test_osk_define_key_hands_the_current_word_to_the_dictionary():
    """Define copies the word under the caret and opens Dictionary via the flag."""
    action = _section(KB, "function defineWord()", "// ---- a controller on the keys")
    assert "const word = Osk.currentWord();" in action
    assert 'if (word === "") return;' in action
    assert "Quickshell.clipboardText = word;" in action
    assert (
        "Ui.dictionary = false;" in action
    )  # re-open so Dictionary re-reads the clipboard
    assert "Ui.dictionary = true;" in action
    key = _section(KB, "// look the word being typed up", "// one-handed:")
    assert 'icon: "accessories-dictionary"' in key
    assert 'accessibleName: Tr.t("Define")' in key
    assert "onTapped: win.defineWord()" in key


def test_writepad_look_up_hands_the_recognised_word_to_the_dictionary():
    """Look up uses the last recognised row, not the strokes still on the pad."""
    action = _section(PAD, "function lookUp()", "function finish()")
    assert (
        r'const word = String(Osk.lastWritten || "").trim().split("\n").pop().trim();'
        in action
    )
    assert 'if (word === "") return;' in action
    assert "Quickshell.clipboardText = word;" in action
    assert "Ui.dictionary = false;" in action
    assert "Ui.dictionary = true;" in action
    assert 'visible: String(Osk.lastWritten || "").trim() !== ""' in PAD
    assert 'tip: Tr.t("Look up")' in PAD
    assert "onClicked: pad.lookUp()" in PAD


def test_dictionary_reads_the_handoff_and_shows_the_entry():
    """Opening on the flag seeds the box from the clipboard once, then shows it."""
    assert "visible: Ui.dictionary" in DICT
    handler = _section(DICT, "onVisibleChanged: {", "Item {")
    assert 'const seed = String(Quickshell.clipboardText || "").trim();' in handler
    assert 'if (visible && win.query === "" && seed !== "")' in handler
    assert "win.query = seed" in handler
    # opening the app must not destroy the user's clipboard
    assert 'Quickshell.clipboardText = "";' not in handler
    assert 'text: win.entry ? win.entry.word : ""' in DICT


def test_dictionary_type_into_field_returns_the_word_via_clipboard():
    """No direct OSK signal exists, so the selected entry goes back on the clipboard."""
    action = _section(DICT, "function typeIntoField()", "// ---- near misses")
    assert "const word = win.entryWord;" in action
    assert 'if (word === "") return;' in action
    assert "Quickshell.clipboardText = word;" in action
    assert "Ui.dictionary = false;" in action  # field in front; OSK Paste inserts it
    assert 'text: Tr.t("Type into field")' in DICT
    assert "onClicked: win.typeIntoField()" in DICT
