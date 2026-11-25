"""Static guards for unifying the app entry points (bar, quick panel, sidebar,
dock, window menu and launcher).

The surfaces need a running shell to render, so this checks their QML source, as
test_ux_tools_fixes.py does. One item per tool everywhere: the same spelling,
icon, order and reachable Ui flag, with an accessible name, tooltip and KeyFocus
on every entry.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

BAR = "shani/Modules/Bar/Bar.qml"
CHIP = "shani/Modules/Bar/Chip.qml"
QUICK = "shani/Modules/QuickPanel/QuickPanel.qml"
SIDEBAR = "shani/Modules/ControlCenter/SidebarTiles.qml"
TILE = "shani/Modules/ControlCenter/Tile.qml"
DOCK = "shani/Modules/Dock/Dock.qml"
WINDOWMENU = "shani/Modules/WindowMenu/WindowMenu.qml"
ACTIONS = "shani/Modules/Launcher/LauncherActions.qml"
LAUNCHER = "shani/Modules/Launcher/Launcher.qml"
MAGNIFIER = "shani/Modules/Magnifier/Magnifier.qml"

# one spelling, one icon, one order: the launcher's tool: group is the reference
CANONICAL = [
    ("Dictionary", "accessories-dictionary", "dictionary"),
    ("Podcasts", "audio-headphones", "podcasts"),
    ("Teleprompter", "view-list-text", "teleprompter"),
    ("Network Tools", "network-workgroup", "netTools"),
    ("Database browser", "database", "databaseBrowser"),
    ("Startup manager", "system-run", "startupManager"),
    ("Gateway", "network-server", "gateway"),
    ("Paste history", "edit-paste", "pasteHistory"),
    ("Scheduled tasks", "x-office-calendar", "scheduled"),
]
TIDS = {
    "Dictionary": "dictionary",
    "Podcasts": "podcasts",
    "Teleprompter": "teleprompter",
    "Network Tools": "netTools",
    "Database browser": "databaseBrowser",
    "Startup manager": "startupManager",
    "Gateway": "gateway",
    "Paste history": "pasteHistory",
    "Scheduled tasks": "scheduled",
}
# each tool window except the loupe resets its flag when it goes away
WINDOWS = {
    "dictionary": "shani/Modules/Dictionary.qml",
    "podcasts": "shani/Modules/MediaPlayer/PodcastWindow.qml",
    "teleprompter": "shani/Modules/Teleprompter.qml",
    "netTools": "shani/Modules/NetTools.qml",
    "databaseBrowser": "shani/Modules/DatabaseBrowser.qml",
    "startupManager": "shani/Modules/StartupManager.qml",
    "gateway": "shani/Modules/GatewayWindow.qml",
    "pasteHistory": "shani/Modules/PasteHistoryWindow.qml",
    "scheduled": "shani/Modules/ScheduledTasksWindow.qml",
}


def src(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def bracket_from(text, i):
    """The bracketed array starting at the first '[' after position i."""
    j = text.index("[", i)
    depth = 0
    for k in range(j, len(text)):
        if text[k] == "[":
            depth += 1
        elif text[k] == "]":
            depth -= 1
            if depth == 0:
                return text[j : k + 1]
    raise AssertionError("unbalanced brackets")


def tool_runs(text):
    """The local QML opens a surface uses; the JS catalog carries no closures."""
    m = re.search(r"readonly property var toolRuns: \(\{.*?\n    \}\)", text, re.S)
    assert m, "no toolRuns block"
    return m.group(0)


def label_icon_pairs(block, label_key="label"):
    out = []
    for line in block.splitlines():
        lm = re.search(r'\b%s:\s*(?:Tr\.t\()?"([^"]+)"\)?' % label_key, line)
        if lm:
            im = re.search(r'\bicon:\s*"([^"]+)"', line)
            out.append((lm.group(1), im.group(1) if im else None, line))
    return out


def sidebar_tiles(text):
    out = {}
    for b in re.split(r"\n\s*Tile \{", text)[1:]:
        tid = re.search(r'\btid:\s*"([^"]+)"', b)
        title = re.search(r'\btitle:\s*Tr\.t\("([^"]+)"\)', b)
        icon = re.search(r'\bicon:\s*"([^"]*)"', b)
        if tid and title:
            out[tid.group(1)] = (title.group(1), icon.group(1) if icon else None)
    return out


def sidebar_tile(text, tid):
    return next(
        b for b in re.split(r"\n\s*Tile \{", text)[1:] if 'tid: "%s"' % tid in b
    )


def chip_with(text, needle):
    i = text.index(needle)
    start = text.rfind("Chip {", 0, i)
    assert start >= 0, "no Chip around %s" % needle
    j = text.index("{", start)
    depth = 0
    for k in range(j, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return text[start : k + 1]
    raise AssertionError("unbalanced braces in Chip")


def tool_action_lines(text):
    return [l for l in text.splitlines() if re.search(r'words: "tool\b', l)]


# ---- fix 1: window menu's tools submenu agrees on each tool ----------------


def test_1_window_menu_tool_labels_and_icons_are_canonical():
    menu = src(WINDOWMENU)
    tools = menu
    assert "Tools.list.map(t => ({" in tools
    assert "label: Tr.t(t.label)" in tools and "icon: t.icon" in tools
    catalog = src("shani/Common/Tools.js")
    for label, icon, _ in CANONICAL:
        assert f'label: "{label}"' in catalog, label
        assert f'icon: "{icon}"' in catalog, icon


# ---- fix 2: quick panel's More apps row is the first four tools -------------


def test_2_quick_panel_first_four_match_the_canonical_order():
    q = src(QUICK)
    more = q[q.index("More apps") :]
    assert "Tools.list.slice(0, 4)" in more
    assert "label: Tr.t(t.label), icon: t.icon" in more


# ---- fix 3: the dock's tools menu follows the same order --------------------


def test_3_dock_tool_menu_order_matches_the_shared_order():
    d = src(DOCK)
    tools = d
    assert "Tools.list.map(t => ({ label: t.label, run: toolRuns[t.flag] }))" in tools


# ---- fix 4: launcher actions are the single reference list ------------------


def test_4_launcher_actions_are_the_canonical_reference():
    actions = src(ACTIONS)
    assert "...Tools.list.map" in actions
    assert "title: Tr.t(t.label)" in actions
    assert "words: t.words" in actions and "icon: t.icon" in actions
    catalog = src("shani/Common/Tools.js")
    for label, icon, _ in CANONICAL:
        assert f'label: "{label}"' in catalog, label
        assert f'icon: "{icon}"' in catalog, icon


# ---- fix 5: the bar's one chip opens that list ------------------------------


def test_5_bar_tools_chip_agrees_with_the_shared_order():
    bar = src(BAR)
    assert bar.count('Ui.toggleLauncher("tool")') == 1  # one chip, not nine
    chip = chip_with(bar, 'Ui.toggleLauncher("tool")')
    assert 'name: Tr.t("Tools")' in chip and "hint:" in chip
    hint = re.search(r'hint: Tr\.t\("([^"]*Dictionary[^"]*)"\)', bar).group(1)
    assert hint.lower().startswith(", ".join(l.lower() for l, _, _ in CANONICAL[:3]))


# ---- fix 6: all nine tools are reachable from every full surface ------------


def test_6_every_full_surface_reaches_all_nine_tools():
    regions = {
        WINDOWMENU: tool_runs(src(WINDOWMENU)),
        DOCK: tool_runs(src(DOCK)),
        ACTIONS: tool_runs(src(ACTIONS)),
    }
    for rel, region in regions.items():
        for _, _, flag in CANONICAL:
            assert "Ui.%s = true" % flag in region, (rel, flag)


# ---- fix 7: no mouse-only tool entry ---------------------------------------


def test_7_every_tool_entry_has_name_tooltip_and_keyfocus():
    q = src(QUICK)
    more = q[q.index("More apps") :]
    for needle in (
        "Accessible.name: modelData.label",
        "KeyFocus { name: modelData.label",
    ):
        assert needle in more, needle
    w = src(WINDOWMENU)
    for needle in (
        "Accessible.name: mi.modelData.label",
        "KeyFocus { onActivated: win.press(mi.modelData) }",
    ):
        assert needle in w, needle
    d = src(DOCK)
    for needle in (
        "Accessible.name: modelData.label",
        "KeyFocus { radius: Theme.px(8); onActivated: { parent.modelData.run();",
    ):
        assert needle in d, needle
    # tiles and the bar chip inherit the same triple from their components: a
    # tile's visible subtitle is its description, the icon-only chip has a Hint
    for needle in ("Accessible.name", "Accessible.description", "KeyFocus"):
        assert needle in src(TILE), needle
    for needle in ("Accessible.name", "KeyFocus", "Hint"):
        assert needle in src(CHIP), needle


# ---- fix 8: sidebar tiles keep the canonical label and icon -----------------


def test_8_sidebar_tool_tiles_keep_the_canonical_label_and_icon():
    s = src(SIDEBAR)
    assert "model: Tools.list" in s
    assert "tid: modelData.flag" in s
    assert "icon: modelData.icon" in s and "title: Tr.t(modelData.label)" in s
    assert "...Tools.list.map(t => t.flag)" in s
    catalog = src("shani/Common/Tools.js")
    for label, icon, flag in CANONICAL:
        assert f'label: "{label}"' in catalog, label
        assert f'icon: "{icon}"' in catalog, icon
        assert f'flag: "{flag}"' in catalog, flag


# ---- fix 9: one clipboard launcher tile, not Snippets + Clipboard -----------


def test_9_no_duplicate_clipboard_launcher_tile():
    s = src(SIDEBAR)
    assert 'tid: "snippets"' not in s  # the duplicate is gone
    assert '"snippets",' not in s.split("readonly property var known:")[1].split("]")[0]
    assert s.count('Ui.toggleLauncher("c ")') == 1  # one tile into clip mode
    assert 'Ui.toggleLauncher("c ")' in sidebar_tile(s, "clipboard")


# ---- fix 10: the sidebar loupe re-opens (it has no onGone) ------------------


def test_10_sidebar_magnifier_forces_a_fresh_open():
    mag = sidebar_tile(src(SIDEBAR), "magnifier")
    assert "no onGone" in mag
    assert "Ui.magnifier = false;" in mag
    assert "Qt.callLater(() => { Ui.magnifier = true; })" in mag


# ---- fix 11: the launcher action does the same ------------------------------


def test_11_launcher_magnifier_forces_a_fresh_open():
    a = src(ACTIONS)
    assert "no onGone" in a
    line = next(l for l in a.splitlines() if 'Tr.t("Magnifier")' in l)
    assert "Ui.magnifier = false;" in line
    assert "Qt.callLater(() => { Ui.magnifier = true; })" in line


# ---- fix 12: only flags without onGone need the re-open ---------------------


def test_12_only_flags_without_ongone_need_a_calllater_reopen():
    assert "onGone" not in src(MAGNIFIER)
    for flag, rel in WINDOWS.items():
        assert "onGone: Ui.%s = false" % flag in src(rel), rel
    # the nine tools' own flags have onGone, so no surface force-toggles them
    for rel in (SIDEBAR, ACTIONS, DOCK, WINDOWMENU):
        for _, _, flag in CANONICAL:
            assert not re.search(
                r"Ui\.%s = false; Ui\.%s = true" % (flag, flag), src(rel)
            ), (rel, flag)
    assert 'op === "tool"' in src(LAUNCHER)  # the cap rises for the whole group
