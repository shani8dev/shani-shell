"""Static checks for the Gateway / Paste history cross-wiring.

The surfaces are QML windows, so each wiring is checked at source level (the
style of test_gateway_paste_vpn_fixes.py). One test per reachable path.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


SHARE = lambda: read("shani/Services/Share.qml")
GW = lambda: read("shani/Modules/GatewayWindow.qml")
PH = lambda: read("shani/Modules/PasteHistoryWindow.qml")
LAUNCH = lambda: read("shani/Modules/Launcher/Launcher.qml")


def function_body(src, name):
    """The body of `function name(...)`, by balanced braces."""
    start = src.index(f"function {name}(")
    brace = src.index("{", start)
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[brace : i + 1]
    raise AssertionError(f"unbalanced function {name}")


def test_share_sends_the_shared_file_to_gateway():
    s = SHARE()
    assert 'Tr.t("Send to gateway peer")' in s
    assert "function sendToGatewayPeer(paths)" in s
    assert 'Quickshell.clipboardText = "shani-gateway:" + fs[0];' in s
    assert "Ui.gateway = true;" in s
    assert "run: () => root.sendToGatewayPeer()" in s


def test_share_copies_a_share_link():
    s = SHARE()
    assert 'Tr.t("Copy as share link")' in s
    assert "function shareLink()" in s
    assert '"https://gateway.local/share/" + encodeURIComponent(p)' in s
    assert "Quickshell.clipboardText = link;" in s


def test_files_file_action_reaches_the_gateway_peer_target():
    # Files reaches Share through its existing "Share…" action; the sheet's
    # "Send to gateway peer" target takes a path argument for that handoff.
    files_actions = read("shani/Services/FileActions.qml")
    assert 'add("share", Tr.t("Share…"), "emblem-shared", "")' in files_actions
    assert 'if (id === "share") { Share.open(fs[0]); return; }' in files_actions
    s = SHARE()
    assert 'Tr.t("Send to gateway peer")' in s
    assert 'paths ? (typeof paths === "string" ? [paths]' in s


def test_launcher_clipboard_mode_opens_paste_history():
    src = LAUNCH()
    start = src.index('if (q === "c" || q.startsWith("c ")) {')
    end = src.index('const math = q.startsWith("=")', start)
    branch = src[start:end]
    assert 'title: Tr.t("Clipboard history"), group: "clip"' in branch
    assert 'title: Tr.t("Paste history")' in branch
    assert "Ui.pasteHistory = true;" in branch
    assert "Ui.closeAll(); Ui.pasteHistory = true;" in branch


def test_paste_history_sends_a_snippet_to_share():
    p = PH()
    assert 'tip: Tr.t("Send this snippet")' in p
    assert "onClicked: win.sendSnippet(row.modelData)" in p
    assert "function sendSnippet(e)" in p
    assert "Share.open(p);" in p
    assert "Quickshell.clipboardText = e.text;" in p
    assert "function saveSnippet(e)" in p


def test_paste_history_opens_text_snippets_in_the_editor():
    p = PH()
    assert 'tip: Tr.t("Open in Editor")' in p
    assert "visible: !row.modelData.image" in p
    assert "function openInEditor(e)" in p
    assert "Ui.textEditorOpenPath = p;" in p
    assert "Ui.textEditor = true;" in p
    assert "snippetFile.setText(e.text);" in p
    assert "FileView { id: snippetFile; printErrors: false }" in p


def test_gateway_prefills_from_clipboard_without_inventing_an_error():
    g = GW()
    assert "function prefillFromClipboard()" in g
    assert "function looksLikeHandleOrUrl(text)" in g
    assert "win.prefillFromClipboard()" in g
    assert "win.search = m ? decodeURIComponent(m[1]) : t;" in g
    assert "win.pendingFile = handoffCheck.checkedPath;" in g  # verified path only
    # A prefill is a note about the clipboard, never a peer failure.
    assert "peerError" not in function_body(g, "prefillFromClipboard")
    assert 'visible: win.peerError !== ""' in g
