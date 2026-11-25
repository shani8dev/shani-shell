"""Static asserts for the tool: entry-point / label / icon fixes.

The audits are read-only, so these tests guard the QML source itself: the
operator list, the nine-tool cap, one spelling+icon per tool, the two distinct
"startup" destinations, and the accessible name on the overview's tool chips.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

OPERATORS = "shani/Services/LauncherEntries.qml"
LAUNCHER = "shani/Modules/Launcher/Launcher.qml"
ACTIONS = "shani/Modules/Launcher/LauncherActions.qml"
SIDEBAR = "shani/Modules/ControlCenter/SidebarTiles.qml"
RING = "shani/Modules/Ring/Ring.qml"
SEARCH = "shani/Modules/Overview/OverviewSearch.qml"
HINTS = "shani/Modules/Hints/StartHints.qml"

# one spelling and one icon per tool, agreed across the launcher, the sidebar
# and the ring (the bar keeps a single generic "Tools" chip)
CANONICAL = {
    "Dictionary": "accessories-dictionary",
    "Podcasts": "audio-headphones",
    "Teleprompter": "view-list-text",
    "Network Tools": "network-workgroup",
    "Database browser": "database",
    "Startup apps": "system-run",
    "Nearby Share": "network-wireless",
    "Paste history": "edit-paste",
    "Automations": "x-office-calendar",
}
TIDS = {
    "Dictionary": "dictionary",
    "Podcasts": "podcasts",
    "Teleprompter": "teleprompter",
    "Network Tools": "netTools",
    "Database browser": "databaseBrowser",
    "Startup apps": "startupManager",
    "Nearby Share": "nearby",
    "Paste history": "pasteHistory",
    "Automations": "scheduled",
}


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def sidebar_tiles(text):
    out = {}
    for block in re.split(r"\n\s*Tile \{", text)[1:]:
        tid = re.search(r'\btid:\s*"([^"]+)"', block)
        title = re.search(r'\btitle:\s*Tr\.t\("([^"]+)"\)', block)
        icon = re.search(r'\bicon:\s*"([^"]*)"', block)
        if tid and title:
            out[tid.group(1)] = (title.group(1), icon.group(1) if icon else None)
    return out


def test_1_tool_operator_is_recognised_and_keeps_the_action_group():
    entries = source(OPERATORS)
    block = re.search(r"operators:\s*\[(.*?)\]", entries, re.S).group(1)
    assert re.search(r'\{\s*id:\s*"tool",\s*hint:\s*"tool:dictionary"\s*\}', block)
    assert "operators.some(o => o.id === id)" in entries  # parseQuery uses the list
    launcher = source(LAUNCHER)
    # finish() keeps only sections whose group is the operator: the action
    # group must therefore be named "tool" for tool: queries
    assert 'group: op === "tool" ? "tool" : "action"' in launcher
    assert 'tool: "tool:dictionary"' in launcher  # bare tool: offers an example
    assert (
        'q.trim().toLowerCase() === "tool") acts = acts.filter(a => /\\btool\\b/.test(a.words));'
        in launcher
    )


def test_2_tool_query_raises_the_action_cap_to_all_nine():
    launcher = source(LAUNCHER)
    m = re.search(r"acts\.slice\(0, ([^;]+)\);", launcher)
    assert m, "the action cap is missing"
    expr = m.group(1)
    assert 'op === "tool"' in expr and 'q.trim().toLowerCase() === "tool"' in expr
    assert "? 9 : 6" in expr


def test_3_nine_tool_labels_and_icons_agree_across_owned_files():
    # Tools.list is now the single source of truth; each surface derives from it.
    tools = source("shani/Common/Tools.js")
    for title, icon in CANONICAL.items():
        assert f'label: "{title}"' in tools, title
        assert f'icon: "{icon}"' in tools, (title, icon)
    # (an app's dock menu and a window's menu no longer repeat them)
    for rel in (ACTIONS, SIDEBAR,
                "shani/Modules/QuickPanel/QuickPanel.qml",
                "shani/Modules/Settings/SettingsIndex.js"):
        assert "Tools.list" in source(rel), rel
    assert 'query: "tool:network"' in source(SEARCH)

def test_4_launcher_startup_entry_is_not_the_startup_manager_tile():
    actions = source(ACTIONS)
    line = next(
        l
        for l in actions.splitlines()
        if 'launcher.openSettings("apps")' in l and "startup" in l.lower()
    )
    assert 'Tr.t("Default apps and sessions")' in line
    assert "Ui.startupManager" not in line
    # sidebar tool tiles are generated from Tools.list; the flag is in `known`
    assert '...Tools.list.map(t => t.flag)' in source(SIDEBAR)
    assert 'label: "Startup apps"' in source("shani/Common/Tools.js")


def test_5_overview_tool_chips_have_an_accessible_name():
    text = source(SEARCH)
    block = re.search(r"model: win\.toolChips(.*?)\n\s*\}\n", text, re.S).group(1)
    assert 'Accessible.name: Tr.t("Open %1 tool", modelData.title)' in block
