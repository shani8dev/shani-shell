"""The "overview & launch" upgrade: one coherent set of fixes, over the
files the module owns (OverviewSearch, OverviewStats is untouched; the
Launcher). Static checks on the QML sources, the style of
test_overview_island_fixes.py: each test is one fix, and the behavior is
asserted on what the code says.

AIM of the upgrade (benchmarked against GNOME Overview, KDE Activities
and Spotlight): the overview comes from a command, history and recent
files browse in the field, more spaces groups with a live switcher,
keyboard nav in the launcher, colored filters, emoji/variation search
and a bigger window with scrolling reachable by the keys.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEARCH = (ROOT / "shani/Modules/Overview/OverviewSearch.qml").read_text(
    encoding="utf-8"
)
LAUNCHER = (ROOT / "shani/Modules/Launcher/Launcher.qml").read_text(encoding="utf-8")


def block(text, needle, end="\n    }"):
    """The brace-counted block that follows the first `needle` in text."""
    start = text.index(needle)
    i = text.index("{", start)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i : j + 1]
    raise AssertionError(f"unterminated block after {needle!r}")


# --------------------------------------------------------------------------
# 1. the overview comes from a command
# --------------------------------------------------------------------------
def test_the_overview_opens_from_a_command_with_a_clean_field():
    # niri opens the overview by command (`niri msg action open-overview`):
    # every open starts the field empty and focused, whatever reopened it
    assert "The overview comes from a command" in SEARCH
    vis = block(SEARCH, "onVisibleChanged")
    assert 'if (!visible) { handOver.stop(); typed = ""; }' in vis
    assert 'typed = "";' in vis.split("else", 1)[1]
    assert "if (win.visible) keys.forceActiveFocus()" in SEARCH


def test_the_overview_hands_over_to_the_launcher_with_the_filter():
    # the field's filter is the launcher's operator lane: "app:", "file:" or none
    fn = block(SEARCH, "function search(text)")
    assert 'win.filter === "all" ? "" : win.filter + ":"' in fn
    assert 'Ui.toggleLauncher(f + (text || ""))' in fn


# --------------------------------------------------------------------------
# 2. more spaces groups with a live switcher
# --------------------------------------------------------------------------
def test_more_spaces_groups_with_a_live_switcher():
    assert (
        "readonly property var spaceGroups: Niri.workspacesOn(Niri.focusedOutput)"
        in SEARCH
    )
    assert "Niri.focusWorkspace(modelData.ws)" in SEARCH
    assert "model: win.spaceGroups" in SEARCH


# --------------------------------------------------------------------------
# 3. colored filters (app:/file:/all)
# --------------------------------------------------------------------------
def test_colored_filters_in_the_overview_field():
    assert 'property string filter: "all"' in SEARCH
    for fid in ('"all"', '"app"', '"file"'):
        assert f"id: {fid}" in SEARCH
    # the colors the pills are drawn with
    for color in ("Theme.faint", "Theme.accent", "Theme.dim"):
        assert color in SEARCH
    # the pills sit in the field's row, with the selection state
    assert "model: win.filters" in SEARCH
    assert "selected: win.filter === modelData.id" in SEARCH


def test_launcher_colored_filters():
    assert 'property string filter: "all"' in LAUNCHER
    for fid in ('"all"', '"app"', '"file"'):
        assert f"id: {fid}" in LAUNCHER
    # the field's pills narrow the answer sections
    assert "model: win.filters" in LAUNCHER
    assert 'visible: !win.narrow || modelData.id !== "file"' in LAUNCHER
    assert (
        'return win.filter === "all" ? done : done.filter(s => s.group === win.filter);'
        in LAUNCHER
    )


# --------------------------------------------------------------------------
# 4. history and recent-files browse in the field
# --------------------------------------------------------------------------
def test_history_and_recent_files_browse_in_the_field():
    # the field shows recent searches and the recently-used files
    assert "readonly property var historyItems: LauncherEntries.searchHistory" in SEARCH
    assert "readonly property var recent: RecentFiles.files.slice(0, 10)" in SEARCH
    # a click fills the field; the field has no caret, so it appends
    assert "win.typed = modelData.title" in SEARCH


def test_launcher_history_and_recent_files_in_the_field():
    # the launcher already browses them: the two sections stay
    assert 'Tr.t("Recent searches")' in LAUNCHER
    assert 'Tr.t("Recent files")' in LAUNCHER
    assert "win.groupRecent(" in LAUNCHER


# --------------------------------------------------------------------------
# 5. keyboard nav in the launcher (Up/Down/PageUp/PageDown, Home/End)
# --------------------------------------------------------------------------
def test_launcher_keyboard_nav():
    keys = block(LAUNCHER, "Keys.onPressed: e => {")
    assert "Qt.Key_Home" in keys and "Qt.Key_End" in keys  # Home/End: first/last
    assert "Qt.Key_PageUp" in keys and "Qt.Key_PageDown" in keys  # a page of results
    assert "win.pageRows" in keys
    assert (
        "readonly property int pageRows: Math.max(1, Math.min(8, win.gridCols) * 6)"
        in LAUNCHER
    )


# --------------------------------------------------------------------------
# 6. emoji/variation search
# --------------------------------------------------------------------------
def test_emoji_variation_search():
    # variation selectors (VS15 U+FE0E / VS16 U+FE0F) are stripped for the search
    assert 'const norm = f.replace(/[\\uFE0E\\uFE0F]/g, "")' in LAUNCHER
    assert (
        "n.indexOf(norm) >= 0" in LAUNCHER
    )  # names match with or without the selector
    assert "g.indexOf(norm) >= 0" in LAUNCHER  # the glyph is searchable too


# --------------------------------------------------------------------------
# 7. bigger window and scrolling
# --------------------------------------------------------------------------
def test_bigger_window():
    assert "implicitWidth: Theme.px(780)" in SEARCH  # the overview's field, bigger
    assert (
        "Layout.maximumWidth: Theme.px(900)" in LAUNCHER
    )  # the launcher's field, wider
