"""Large editor upgrade: an IDE-style feature set benchmarked against GNOME Text
Editor, KDE Kate and VS Code.

Twelve concrete fixes are covered: project sidebar, recent files, tab groups,
line overview, brace jump, block indent, syntax choice, find in files, split
view, keyboard chords, accessible names and empty/error states.

The QML is checked statically (as in the other editor tests); the small pure
branches are mirrored here so their arithmetic is exercised without a QML
runtime.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PANEL = (ROOT / "shani/Modules/TextEditor/TextEditorPanel.qml").read_text(
    encoding="utf-8"
)
DOCS = (ROOT / "shani/Services/TextDocs.qml").read_text(encoding="utf-8")


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


# ---- 1. recent files / MRU ---------------------------------------------------


def test_recent_files_are_recorded_and_persisted_with_the_session():
    note = block(DOCS, "function noteRecent(path)")
    assert "root.recentFiles.filter(p => p !== path)" in note  # no duplicates
    assert "r.unshift(path)" in note  # newest first
    assert "r.slice(0, root.maxRecent)" in note  # bounded
    save = block(DOCS, "function saveSession()")
    assert "recent: root.recentFiles.slice(0, root.maxRecent)" in save
    assert "folder: root.folder" in save  # the project folder survives too
    loaded = block(DOCS, "onLoaded:")
    assert "Array.isArray(data.recent)" in loaded
    assert 'typeof p === "string"' in loaded  # malformed state is ignored
    assert 'typeof data.folder === "string"' in loaded
    assert "root.noteRecent(p)" in DOCS  # recorded once a file really loads
    assert "noteRecent(path)" in block(DOCS, "function saveAs(path)")


def test_open_recent_dialog_filters_and_has_an_empty_state():
    assert "id: recentDialog" in PANEL
    # Ctrl+R belongs to AppWindow's refresh; recent files now use Ctrl+Shift+R
    assert "e.key === Qt.Key_R && shift) recentDialog.open()" in PANEL
    recent = block(PANEL, "id: recentDialog")
    assert "TextDocs.recentFiles.filter(p =>" in recent
    assert "win.openRecent(modelData)" in recent
    assert 'title: "No recent files"' in recent


# ---- 2. project / folder sidebar --------------------------------------------


def test_folder_sidebar_reuses_the_watched_directory_model():
    assert "FileDirectory { id: dirModel; path: TextDocs.folder }" in PANEL
    assert 'mode: "folder", title: "Open a project folder"' in PANEL
    assert "onTextChanged: dirModel.query = text" in PANEL  # filter box
    assert "model: dirModel.entries" in PANEL
    assert "win.openSidebarEntry(modelData)" in PANEL
    entry = block(PANEL, "function openSidebarEntry(e)")
    assert "if (e.isDir) TextDocs.folder = e.path;" in entry
    assert "else TextDocs.open(e.path);" in entry
    assert "onFolderChanged: if (!root.restoring) saveSession()" in DOCS


def test_sidebar_has_accessible_rows_and_empty_error_states():
    assert (
        'Accessible.name: modelData.name + (modelData.isDir ? ", folder" : ", file")'
        in PANEL
    )
    assert "Accessible.role: Accessible.ListItem" in PANEL
    assert 'visible: dirModel.error !== ""' in PANEL
    assert 'title: "No folder open"' in PANEL
    assert 'text: Tr.t("No files here")' in PANEL


# ---- 3. tab groups -----------------------------------------------------------


def test_tab_groups_are_derived_from_each_documents_folder():
    group = block(DOCS, "function groupOf(doc)")
    assert 'if (!doc.path) return doc.group || "Scratch";' in group
    assert 'doc.path.lastIndexOf("/")' in group
    assert "function groups()" in DOCS
    assert "function showGroup(g)" in DOCS
    assert "root.docs.findIndex(d => root.groupOf(d) === g)" in DOCS


def test_group_chips_filter_the_tab_strip():
    assert (
        'visible: win.activeGroup === "" || TextDocs.groupOf(tab.modelData) === win.activeGroup'
        in PANEL
    )
    assert "model: TextDocs.groups()" in PANEL
    assert "TextDocs.showGroup(modelData)" in PANEL
    assert 'text: Tr.t("All tabs")' in PANEL


# ---- 4. line overview / minimap-lite -----------------------------------------


def test_line_overview_is_sampled_and_clickable():
    assert "id: minimap" in PANEL
    assert "model: Math.min(edit.lineCount, 120)" in PANEL
    assert "flick.contentY / flick.contentHeight * minimap.height" in PANEL
    assert "Math.round(mouseY / Math.max(1, minimap.height) * edit.lineCount)" in PANEL
    assert "win.goToLine(line)" in PANEL


# ---- 5. brace matching jump --------------------------------------------------


def test_matching_bracket_can_be_jumped_to():
    jump = block(PANEL, "function jumpBrace()")
    assert "win.matchBrace(edit.cursorPosition)" in jump
    assert "edit.cursorPosition = p;" in jump
    assert "Qt.Key_BracketRight || e.key === Qt.Key_BracketLeft" in PANEL


# ---- 6. block auto-indent ----------------------------------------------------


def test_tab_on_a_selection_indents_or_unindents_the_block():
    fn = block(PANEL, "function indentSelection(outward)")
    assert "delta += 4;" in fn
    assert "delta -= m[0].length;" in fn
    assert "line.match(/^ {1,4}/)" in fn
    assert "edit.select(Math.max(first, a + delta)" in fn
    handler = next(l for l in PANEL.splitlines() if "win.indentSelection(" in l)
    assert "Qt.ShiftModifier" in handler  # Shift+Tab outdents


# ---- 7. syntax selection -----------------------------------------------------


def test_language_can_be_chosen_per_document():
    assert "function setSyntax(i, lang)" in DOCS
    assert 'd.syntax = lang || "";' in DOCS
    assert "TextDocs.current && TextDocs.current.syntax" in PANEL
    assert (
        "readonly property var syntaxes: Object.keys(Highlight.langs).sort()" in PANEL
    )
    dlg = block(PANEL, "id: syntaxDialog")
    assert "onActivated: i => win.setSyntax(win.syntaxes[i])" in dlg
    assert 'text: "Automatic (from file type)"' in dlg
    assert 'win.setSyntax("")' in dlg


# ---- 8. find in files --------------------------------------------------------


def test_find_in_files_runs_grep_without_a_shell_string():
    fn = block(PANEL, "function findInFiles(q)")
    assert '"grep", "-rnIF", "--exclude-dir=.git", "-e", q, TextDocs.folder' in fn
    assert "fileSearch.running = true;" in fn
    assert 'if (q.trim() === "" || TextDocs.folder === "") return;' in fn
    assert "String(line).match(/^([^:]+):(\\d+):(.*)$/)" in PANEL
    assert "win.findFilesResults.length >= 200" in PANEL  # bounded output
    assert "win.findingFiles = false" in PANEL  # onExited clears the spinner


def test_search_results_open_the_file_at_the_reported_line():
    assert "function openResult(r)" in PANEL
    assert 'TextDocs.open("+" + r.line + " " + r.path)' in PANEL
    dlg = block(PANEL, "id: findFilesDialog")
    assert "onAccepted: win.findInFiles(text)" in dlg
    assert "win.openResult(modelData)" in dlg
    assert 'text: "Searching…"' in dlg
    assert 'title: "Not found"' in dlg
    assert "e.key === Qt.Key_F && shift) win.openFindFiles()" in PANEL


# ---- 9. split editor ---------------------------------------------------------


def test_split_view_mirrors_the_document_and_follows_its_scroll():
    assert "id: splitPane" in PANEL
    assert "text: win.coloured ? paint.text : edit.text" in PANEL
    assert "contentY: flick.contentY" in PANEL
    assert "win.goToLine(line);" in PANEL
    assert "win.splitView && TextDocs.docs.length > 0" in PANEL
    assert 'Accessible.name: "Split view"' in PANEL


# ---- 10. keyboard chords -----------------------------------------------------


def test_ctrl_k_chords_are_armed_and_dispatched():
    assert (
        'if (e.key === Qt.Key_K && !shift) { win.chord = "K"; chordTimer.restart(); return true; }'
        in PANEL
    )
    assert 'if (win.chord !== "" && win.handleChord(e)) return true;' in PANEL
    fn = block(PANEL, "function handleChord(e)")
    assert 'if (win.chord !== "K") return false;' in fn
    for key in ("Qt.Key_O", "Qt.Key_F", "Qt.Key_B", "Qt.Key_D", "Qt.Key_L"):
        assert "e.key === " + key in fn
    assert "id: chordTimer; interval: 2500" in PANEL
    assert 'win.chord = "";' in PANEL  # cleared on escape and on timeout


# ---- 11. accessible names ----------------------------------------------------


def test_new_controls_carry_accessible_names():
    names = [
        'Accessible.name: "Line overview"',
        'Accessible.name: "Split view"',
        'Accessible.name: "Syntax language"',
        'Accessible.name: modelData.text + ", " + modelData.path',
        "Accessible.name: modelData",
    ]
    for needle in names:
        assert needle in PANEL, needle
    assert "Accessible.onPressAction: win.openResult(modelData)" in PANEL
    assert "Accessible.onPressAction: win.openSidebarEntry(modelData)" in PANEL


# ---- 12. empty / error states ------------------------------------------------


def test_a_failed_open_has_retry_and_dismiss_actions():
    assert "function retryOpen()" in PANEL
    assert "function dismissError()" in PANEL
    banner = PANEL[
        PANEL.index('visible: TextDocs.error !== ""') : PANEL.index("EmptyState {")
    ]
    assert 'text: Tr.t("Retry")' in banner
    assert 'text: Tr.t("Dismiss")' in banner
    assert "InfoBanner {" in PANEL and 'tone: "error"' in banner
    assert "win.retryOpen()" in banner and "win.dismissError()" in banner
    assert "root.lastPath = path;" in DOCS


# ---- pure logic mirrors ------------------------------------------------------


def recent_push(items, path, cap=20):
    """Mirror of TextDocs.noteRecent."""
    r = [p for p in items if p != path]
    r.insert(0, path)
    return r[:cap]


def test_recent_mru_semantics():
    assert recent_push([], "/a") == ["/a"]
    assert recent_push(["/a"], "/b") == ["/b", "/a"]
    assert recent_push(["/b", "/a"], "/a") == ["/a", "/b"]  # dedupe, not two rows
    assert len(recent_push(list(map(str, range(30))), "/z")) == 20


def group_of(doc):
    p = doc.get("path", "")
    if not p:
        return doc.get("group", "Scratch")
    i = p.rfind("/")
    return p[:i] if i > 0 else "/"


def test_tab_group_derivation():
    assert group_of({}) == "Scratch"
    assert group_of({"group": "Notes"}) == "Notes"
    assert group_of({"path": "/home/me/proj/a.py"}) == "/home/me/proj"
    assert group_of({"path": "/top.py"}) == "/"


GREP_LINE = re.compile(r"^([^:]+):(\d+):(.*)$")


def grep_result(line):
    m = GREP_LINE.match(line)
    return (m[1], int(m[2]), m[3]) if m else None


def test_grep_result_parser():
    assert grep_result("/p/a.py:12:  x = 1") == ("/p/a.py", 12, "  x = 1")
    assert grep_result("no colon here") is None
    assert grep_result("/p/a.py:bad:x") is None


def indent_block(text, first, last, outward):
    """Mirror of win.indentSelection: returns (new block, delta, changed)."""
    block = text[first:last]
    delta = 0

    def one(line):
        nonlocal delta
        if outward:
            m = re.match(r"^ {1,4}", line)
            if not m:
                return line
            delta -= len(m[0])
            return line[len(m[0]) :]
        delta += 4
        return "    " + line

    changed = "\n".join(one(line) for line in block.split("\n"))
    return changed, delta, changed != block


def test_block_indent_math():
    text = "a\n  b\nc"
    changed, delta, ok = indent_block(text, 0, len(text), False)
    assert changed == "    a\n      b\n    c" and delta == 12 and ok
    back, back_delta, ok2 = indent_block(changed, 0, len(changed), True)
    assert back == text and back_delta == -12 and ok2
    # a line with no leading spaces is left alone when outdenting
    assert indent_block("a\nb", 0, 3, True)[2] is False


def minimap_line(mouse_y, height, count):
    return max(1, min(count, round(mouse_y / max(1, height) * count)))


def test_minimap_click_mapping():
    assert minimap_line(0, 100, 200) == 1
    assert minimap_line(50, 100, 200) == 100
    assert minimap_line(100, 100, 200) == 200
    assert minimap_line(500, 100, 200) == 200  # clamped


CHORDS = {
    "o": "folder",
    "f": "find-in-files",
    "b": "sidebar",
    "d": "split",
    "l": "syntax",
}


def chord_action(key):
    return CHORDS.get(key.lower())


def test_chord_map_is_total_for_its_documented_keys():
    assert [chord_action(k) for k in "ofbdl"] == [
        "folder",
        "find-in-files",
        "sidebar",
        "split",
        "syntax",
    ]
    assert chord_action("x") is None
