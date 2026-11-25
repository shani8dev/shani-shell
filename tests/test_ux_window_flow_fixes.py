"""Static checks for the UX-audit fixes in the target windows.

Each window needs a running shell to render, so these are source-level
assertions (as in test_wire_nettools_fixes.py). No new Ui.qml property was
added: the only tools used here are onGone, Qt.callLater and onVisibleChanged.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES = ROOT / "shani" / "Modules"


def source(rel):
    return (MODULES / rel).read_text(encoding="utf-8")


def function_body(text, name):
    """Return the text of `function name(...) { ... }` using brace matching."""
    m = re.search(r"function\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{", text)
    assert m, "function %s not found" % name
    start = m.end() - 1
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    raise AssertionError("unbalanced braces in %s" % name)


# ---- fix 1: a normal close must reset the flag so the window can reopen ----


def test_fix1_four_windows_reset_their_flag_on_gone():
    expected = {
        "Dictionary.qml": "dictionary",
        "MediaPlayer/PodcastWindow.qml": "podcasts",
        "DatabaseBrowser.qml": "databaseBrowser",
        "StartupManager.qml": "startupManager",
    }
    for rel, flag in expected.items():
        s = source(rel)
        assert "visible: Ui.%s" % flag in s, rel
        assert "onGone: Ui.%s = false" % flag in s, rel
    # the reference pattern this follows, already present in NetTools
    assert "onGone: Ui.netTools = false" in source("NetTools.qml")


# ---- fix 2: Dictionary must not destroy the clipboard on open ---------------


def test_fix2_dictionary_seed_keeps_the_clipboard():
    d = source("Dictionary.qml")
    # the seed lives in the root onVisibleChanged handler
    start = d.index("onVisibleChanged: {")
    seed = d[start : d.index("// Escape", start)]
    assert "win.query = seed" in seed
    assert 'win.query === "" && seed !== ""' in seed
    assert "clipboardText" not in seed.replace(
        'String(Quickshell.clipboardText || "")', ""
    )
    assert 'Quickshell.clipboardText = ""' not in d


# ---- fix 3: Teleprompter prefill must not clear the clipboard ----------------


def test_fix3_teleprompter_prefill_keeps_the_clipboard():
    t = source("Teleprompter.qml")
    body = function_body(t, "prefillFromClipboard")
    assert "win.paste();" in body
    assert 'Quickshell.clipboardText = ""' not in body
    assert "onVisibleChanged: if (visible) win.prefillFromClipboard()" in t


# ---- fix 4: the Translate action is honest about what it can deliver --------


def test_fix4_teleprompter_translate_action_only_copies():
    t = source("Teleprompter.qml")
    body = function_body(t, "copyFirstLineForTranslation")
    assert "Quickshell.clipboardText = first;" in body
    assert "Ui.translate" not in body
    assert "Ui.translate = true" not in t
    assert 'text: Tr.t("Copy first line for translation")' in t
    assert "onClicked: win.copyFirstLineForTranslation()" in t
    # documented limit: TranslateWindow does not read a clipboard handoff
    assert "shortcut:" in t and "TranslateWindow does not read a clipboard handoff" in t


# ---- fix 5: NetTools arms after construction and keeps the clipboard --------


def test_fix5_nettools_handoff_is_armed_and_clipboard_safe():
    n = source("NetTools.qml")
    body = function_body(n, "takeHandoff")
    assert 'const marker = "shani-nettools:"' in body
    assert "raw.indexOf(marker) !== 0" in body
    assert "win.validHost(host)" in body
    assert 'Quickshell.clipboardText = ""' not in body
    # no consumption at launch: arm after construction, consume on false -> true
    assert "property bool handoffArmed: false" in n
    assert "Component.onCompleted: win.handoffArmed = true" in n
    assert "Component.onCompleted: win.takeHandoff()" not in n
    assert (
        "onVisibleChanged: { if (visible && win.handoffArmed) win.takeHandoff(); }" in n
    )


# ---- fix 6: Gateway needs an explicit marker, a real file, and every open ---


def test_fix6_gateway_handoff_is_explicit_validated_and_repeated():
    g = source("GatewayWindow.qml")
    body = function_body(g, "prefillFromClipboard")
    assert 'const marker = "shani-gateway:"' in body
    assert "t.indexOf(marker) === 0" in body
    assert 't.charAt(0) === "/"' not in body
    # existence is confirmed before pendingFile is set
    assert 'test -f "$1"' in body
    assert "handoffCheck.checkedPath = path;" in body
    assert "property string pendingFile:" in g
    # a bare user@host (email) must not claim the search field
    handle = function_body(g, "looksLikeHandleOrUrl")
    assert "[^\\s@/]+@[^\\s@/]{4,}" not in handle
    assert "win.peers.some(" in handle
    # every open, not a one-shot prefilled flag
    assert "prefilled" not in g
    assert "onVisibleChanged: if (visible) win.prefillFromClipboard()" in g


# ---- fix 7: no same-frame Ui false -> true in the owned windows -------------


def test_fix7_no_same_frame_ui_toggle_in_owned_windows():
    owned = [
        "Dictionary.qml",
        "MediaPlayer/PodcastWindow.qml",
        "DatabaseBrowser.qml",
        "StartupManager.qml",
        "Teleprompter.qml",
        "NetTools.qml",
        "GatewayWindow.qml",
    ]
    same_frame = re.compile(r"Ui\.(\w+)\s*=\s*false\s*;\s*Ui\.\1\s*=\s*true")
    for rel in owned:
        s = source(rel)
        assert not same_frame.search(s), "%s toggles a Ui flag in one frame" % rel
