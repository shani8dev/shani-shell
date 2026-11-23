"""Static asserts for five small fixes in the annotate / share / file-actions
surfaces: the toolbar returning after a save, the in-progress stroke being
cancelled by Erase, the colour keys being discoverable, a new file offer not
inheriting typed fit limits, and keypad Enter activating a share target.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def function_body(text, name):
    """The {...} body of `function name(...)` in a QML file."""
    start = text.index("function " + name + "(")
    brace = text.index("{", start)
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1 : i]
    raise AssertionError("unbalanced braces in " + name)


def test_save_restores_the_toolbar_after_capture():
    text = source("shani/Modules/Annotate/Annotate.qml")
    save = function_body(text, "save")
    assert "hintShown = false" in save
    assert "hintBack.restart()" in save, "no restore scheduled on save"
    assert "id: hintBack" in text and "onTriggered: win.hintShown = true" in text


def test_erase_cancels_an_in_progress_stroke():
    text = source("shani/Modules/Annotate/Annotate.qml")
    clear = function_body(text, "clear")
    assert "strokes = []" in clear
    assert "current = null" in clear, (
        "E leaves the half-drawn stroke to be committed on release"
    )


def test_hint_names_the_colour_keys():
    text = source("shani/Modules/Annotate/Annotate.qml")
    assert "1-5 colour" in text, "the 1-5 shortcut exists but is not shown in the hint"


def test_new_file_offer_clears_typed_fit_limits():
    text = source("shani/Modules/FileActions/FileActionsCard.qml")
    assert "target: FileActions" in text
    assert "function onFilesChanged()" in text
    for field in ("fMin", "fMax", "fW", "fH"):
        assert field + '.text = ""' in text, field + " keeps a stale value"


def test_share_accepts_keypad_enter():
    text = source("shani/Modules/Share/ShareSheet.qml")
    for handler in ("Keys.onReturnPressed", "Keys.onEnterPressed"):
        assert handler in text, handler + " is missing"
        line = next(l for l in text.splitlines() if handler in l)
        assert "Share.choose(win.sel)" in line
