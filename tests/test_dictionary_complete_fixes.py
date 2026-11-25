"""Static checks for the Dictionary's own integration gaps.

There is no QML runtime here: each check reads the source of the surface it
guards. Four fixes, one test each — pins, near-miss hints, the Quick Look
handoff, and accessible names plus empty states.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DICT = (ROOT / "shani/Modules/Dictionary.qml").read_text()
QUICKLOOK = (ROOT / "shani/Modules/QuickLook/QuickLookSheet.qml").read_text()


def test_pin_word_action_and_persisted_pinned_chips():
    """A word's detail offers Pin/Unpin; pins survive a restart and recall on click."""
    assert "property var pinned: []" in DICT
    assert 'Quickshell.statePath("dictionary-pinned.json")' in DICT
    assert "onLoaded: { try { win.pinned = JSON.parse(text()); } catch (e) {} }" in DICT
    assert (
        "function savePinned() { pinnedFile.setText(JSON.stringify(win.pinned)); }"
        in DICT
    )
    assert "function togglePin() {" in DICT
    assert 'Tr.t("Pin word")' in DICT
    assert 'Tr.t("Unpin word")' in DICT
    assert "onClicked: win.togglePin()" in DICT
    # the chips row is separate from the (older) history row
    assert "model: win.pinned" in DICT
    assert "onClicked: win.recall(modelData)" in DICT


def test_did_you_mean_suggestions_when_no_direct_entry():
    """A near miss offers bundled words matched by prefix or substring."""
    assert "function suggestFor(word) {" in DICT
    assert "const stem = q.slice(0, Math.min(2, q.length));" in DICT
    assert "w.indexOf(stem) >= 0 || w.indexOf(q.charAt(0)) === 0" in DICT
    assert "readonly property var suggestions: win.noMatch" in DICT
    assert "win.entries.filter(e => win.suggestFor(e.word)).slice(0, 6)" in DICT
    assert "visible: win.noMatch && win.suggestions.length > 0" in DICT
    assert 'Tr.t("Did you mean")' in DICT
    assert "onClicked: win.recall(modelData.word)" in DICT


def test_quicklook_define_selection_hands_text_to_dictionary():
    """Selected text in a text preview goes over the clipboard to Dictionary."""
    assert "selectByMouse: true" in QUICKLOOK
    assert "function defineSelection() {" in QUICKLOOK
    assert 'const word = String(listing.selectedText || "").trim();' in QUICKLOOK
    assert 'if (word === "") return;' in QUICKLOOK
    assert "Quickshell.clipboardText = word;" in QUICKLOOK
    assert "Ui.dictionary = true;" in QUICKLOOK
    assert "QuickLook.close();" in QUICKLOOK
    assert 'Tr.t("Define selection")' in QUICKLOOK
    assert 'visible: QuickLook.kind === "text"' in QUICKLOOK
    assert 'enabled: listing.selectedText.trim() !== ""' in QUICKLOOK
    assert "onClicked: win.defineSelection()" in QUICKLOOK


def test_new_controls_have_at_names_and_empty_states():
    """Every new control is named, and both new/empty lists say why they are empty."""
    for named in (
        'Accessible.name: Tr.t("Did you mean")',
        'Accessible.name: Tr.t("Pinned words")',
        'Accessible.name: Tr.t("Pinned word ") + modelData',
        'Accessible.name: Tr.t("Did you mean ") + modelData.word',
    ):
        assert named in DICT
    assert DICT.count("Accessible.name: text") >= 2  # pin toggle + Quick Look button
    assert "Accessible.name: text" in QUICKLOOK
    # no pins yet, and no match yet, are both explained in words
    assert "visible: win.pinned.length === 0" in DICT
    assert 'Tr.t("No pinned words yet · pin one from its entry")' in DICT
    assert "visible: win.noMatch" in DICT
    assert 'Tr.t("No definitions for ") + win.q' in DICT
