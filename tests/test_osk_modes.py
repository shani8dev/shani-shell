"""Static guards and pure logic for the screen keyboard's own controls.

The QML runtime is not available in pytest here, so the source assertions pin
the wiring (which key calls which service function) and the logic tests mirror
Osk.qml's small, deliberately boring suggestion algorithm. No network, no real
dictionary: the words are the bounded list embedded in Osk.qml.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OSK = (ROOT / "shani/Services/Osk.qml").read_text(encoding="utf-8")
KEYBOARD = (ROOT / "shani/Modules/Osk/Keyboard.qml").read_text(encoding="utf-8")
WRITEPAD = (ROOT / "shani/Modules/Osk/WritePad.qml").read_text(encoding="utf-8")

MIN_PREFIX = 2
MAX_SUGGESTIONS = 5


def words_from_source() -> list[str]:
    """The dictionary is a chain of adjacent string literals in Osk.qml."""
    block = OSK[OSK.index("readonly property var suggestionWords:") :]
    block = block[: block.index('.split(" ")')]
    return " ".join(re.findall(r'"([a-z ]+)"', block)).split()


WORDS = words_from_source()


# ---- pure logic (mirrors Osk.suggestionsFor / the strip's visible condition) --


def suggest(words: list[str], typed: str, limit: int = MAX_SUGGESTIONS) -> list[str]:
    w = typed.lower()
    if len(w) < MIN_PREFIX:
        return []
    hits = [x for x in words if len(x) > len(w) and x.startswith(w)]
    hits.sort(key=lambda x: (len(x), x))
    return hits[:limit]


def strip_visible(word: str, enabled: bool, dismissed: str) -> bool:
    return enabled and dismissed != word and bool(suggest(WORDS, word))


def test_dictionary_is_bounded_and_clean():
    assert 0 < len(WORDS) <= 200, len(WORDS)
    assert len(WORDS) == len(set(WORDS)), "duplicate words waste suggestions"
    assert all(re.fullmatch(r"[a-z]+", w) for w in WORDS)
    assert "the" in WORDS and "keyboard" not in WORDS  # small common list, not a corpus


def test_matching_is_by_prefix_and_excludes_the_exact_word():
    assert suggest(WORDS, "und") == ["under"]
    assert "the" not in suggest(WORDS, "the")
    assert all(w.startswith("th") for w in suggest(WORDS, "th"))


def test_suggestions_are_shortest_first_then_alphabetical_and_capped():
    assert suggest(WORDS, "th") == ["the", "than", "that", "them", "then"]
    assert suggest(WORDS, "ab") == ["about", "above"]
    assert len(suggest(WORDS, "w")) == 0  # one letter: no noise


def test_case_and_punctuation_are_handled_at_the_word_boundary():
    assert suggest(WORDS, "TH") == suggest(WORDS, "th")
    assert suggest(WORDS, "") == []
    assert suggest(WORDS, "a") == []
    assert suggest(WORDS, "12") == []
    assert suggest(WORDS, "zzzzzzzzzz") == []


def test_dismissal_is_per_word_not_global():
    assert strip_visible("hel", True, "")
    assert not strip_visible("hel", True, "hel")
    assert strip_visible("hell", True, "hel")
    assert not strip_visible("hel", False, "")


def test_python_constants_match_the_source():
    assert f"w.length < {MIN_PREFIX}" in OSK
    assert f"maxSuggestions: {MAX_SUGGESTIONS}" in OSK
    assert "slice(0, root.maxSuggestions)" in OSK


# ---- static wiring ------------------------------------------------------------


def test_persistence_is_owned_by_osk_not_a_settings_page():
    assert "Settings.data.oskSize" not in OSK  # undeclared keys are rejected at runtime
    assert "Settings.data.oskOpacity" not in OSK
    assert "JsonAdapter" in OSK and "writeAdapter()" in OSK
    assert "property string size:" in OSK
    assert "property real panelOpacity:" in OSK
    assert "property bool suggestions:" in OSK
    assert "function savePrefs()" in OSK
    for fn in ("toggleSize", "cycleOpacity", "toggleSuggestions", "savePrefs"):
        assert f"function {fn}(" in OSK, fn


def test_the_options_menu_is_reachable_from_the_keyboard():
    assert 'Tr.t("Keyboard options")' in KEYBOARD
    assert "win.oskMenu" in KEYBOARD
    assert "Osk.toggleSize()" in KEYBOARD
    assert "Osk.cycleOpacity()" in KEYBOARD
    assert "Osk.toggleSuggestions()" in KEYBOARD
    assert (
        'Tr.t("Keyboard opacity: %1%", Math.round(Osk.panelOpacity * 100))' in KEYBOARD
    )


def test_size_and_opacity_change_the_keyboard_itself():
    assert "Osk.compact ? 232 : 300" in KEYBOARD
    assert "opacity: Osk.panelOpacity" in KEYBOARD
    assert "Behavior on opacity" in KEYBOARD
    assert "Theme.mot(140)" in KEYBOARD  # reduce motion turns the fade off
    assert "Theme.px(Osk.compact ? 6 : 10)" in KEYBOARD
    assert (
        "Osk.compact ? 1 : 2" in WRITEPAD
    )  # compact handwriting loses a row, not a key
    assert "Osk.remote ? 360" in KEYBOARD  # remote's draft line is unchanged


def test_the_suggestion_strip_sits_above_the_keys_and_is_dismissible():
    assert "id: suggestionBar" in KEYBOARD
    assert "Osk.currentWord()" in KEYBOARD
    assert "!(word !== \"\" && Osk.dismissedWord === word)" in KEYBOARD
    # any language now (the engine reads each one's dictionary); never in a password field
    assert "Osk.suggestions && Osk.page === \"letters\" && !Osk.secret" in KEYBOARD
    assert "Osk.applySuggestion(modelData)" in KEYBOARD
    assert "Osk.dismissSuggestions()" in KEYBOARD
    strip = KEYBOARD[KEYBOARD.index("id: suggestionBar") : KEYBOARD.index("// ---- emoji:")]
    assert "Repeater" in strip and "Key {" in strip
    # the same bar holds the tools when there is nothing to predict
    assert "visible: !suggestionBar.predicting" in strip


def test_replacing_a_word_deletes_it_in_both_modes():
    apply = OSK[OSK.index("function applySuggestion") :]
    apply = apply[: apply.index("// Layouts:")]
    assert 'args.push("-k", "BackSpace")' in apply
    assert 'args.push("--", word + " ")' in apply
    assert "draft.slice(0, draft.length - w.length)" in apply
    assert "Quickshell.execDetached(args)" in apply


def test_no_dynamic_evaluation_snuck_in():
    assert "eval(" not in OSK and "new Function(" not in OSK
    assert "eval(" not in KEYBOARD and "new Function(" not in KEYBOARD
