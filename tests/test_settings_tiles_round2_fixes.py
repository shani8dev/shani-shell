"""Static guards for the round-2 Settings/sidebar tile unification.

The shell is QML, so each fix is pinned at source level. The canonical tool
catalog is shani/Common/Tools.js; every surface that offers those tools must
read its label, icon and flag from there, and only one destination may own a
given flag or Settings category.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


TILES = "shani/Modules/ControlCenter/SidebarTiles.qml"
TILE_COMPONENT = "shani/Modules/ControlCenter/Tile.qml"
PAGE = "shani/Modules/Settings/SettingsPage.qml"
INDEX = "shani/Modules/Settings/SettingsIndex.js"
ABOUT = "shani/Modules/Settings/SettingsAbout.qml"
HEADER = "shani/Modules/ControlCenter/SidebarHeader.qml"
TOOLS = "shani/Common/Tools.js"

# flag -> (canonical label, canonical icon, pinned subtitle on the sidebar tile)
TOOL_CATALOG = {
    "dictionary": (
        "Dictionary",
        "accessories-dictionary",
        "Words and meanings, offline",
    ),
    "podcasts": ("Podcasts", "audio-headphones", "Episodes and subscriptions"),
    "teleprompter": ("Teleprompter", "view-list-text", "Scroll your script"),
    "netTools": ("Network Tools", "network-workgroup", "Ping, DNS and scan"),
    "databaseBrowser": ("Database browser", "database", "Open an SQLite file"),
    "startupManager": ("Startup apps", "system-run", "Manage autostart entries"),
    "nearby": ("Nearby Share", "network-wireless", "Send to devices nearby"),
    "pasteHistory": ("Paste history", "edit-paste", "Clipboard slots"),
    "scheduled": ("Automations", "x-office-calendar", "Tasks at their time"),
}


def tool_rows():
    rows = re.findall(
        r'\{\s*label:\s*"([^"]+)",\s*icon:\s*"([^"]+)",\s*flag:\s*"([^"]+)"',
        source(TOOLS),
    )
    return {flag: (label, icon) for label, icon, flag in rows}


def tile_names_block():
    text = source(PAGE)
    match = re.search(r"readonly property var tileNames: \{(.*?)\n    \}", text, re.S)
    assert match, "SettingsPage.qml: tileNames no longer parses"
    return match.group(1)


def sidebar_tids():
    tiles = source(TILES)
    known = re.search(r"readonly property var known: \[([^\]]*)\]", tiles).group(1)
    literal = set(re.findall(r'"([A-Za-z]+)"', known))
    return literal | set(tool_rows())


# ---- fix 1: one catalog for every tool surface -----------------------------


def test_tools_catalog_declares_the_nine_tools():
    assert tool_rows() == {
        flag: (label, icon) for flag, (label, icon, _) in TOOL_CATALOG.items()
    }


def test_sidebar_generates_tool_tiles_from_catalog():
    tiles = source(TILES)
    assert 'import "../../Common/Tools.js" as Tools' in tiles
    assert "model: Tools.list" in tiles
    delegate = tiles.split("model: Tools.list", 1)[1].split("\n        }", 1)[0]
    assert "tid: modelData.flag" in delegate
    assert "icon: modelData.icon" in delegate
    assert "title: Tr.t(modelData.label)" in delegate
    assert "Ui.openTool(modelData.flag)" in delegate
    # no hand-written copy of a catalog tile left behind
    for flag in tool_rows():
        assert f'tid: "{flag}"' not in tiles, f"{flag}: duplicate literal tile"
    assert "...Tools.list.map(t => t.flag)" in re.search(
        r"readonly property var known: \[([^\]]*)\]", tiles
    ).group(1)


def test_sidebar_tool_subtitles_are_preserved():
    tiles = source(TILES)
    block = re.search(
        r"readonly property var toolSubtitles: \(\{(.*?)\}\)", tiles, re.S
    ).group(1)
    subtitles = dict(re.findall(r'(\w+):\s*Tr\.t\("([^"]+)"\)', block))
    for flag, (_, _, subtitle) in TOOL_CATALOG.items():
        assert subtitles.get(flag) == subtitle, f"{flag}: subtitle drift"
    assert set(subtitles) == set(tool_rows())


def test_settings_index_tool_rows_come_from_catalog():
    idx = source(INDEX)
    assert '.import "../../Common/Tools.js" as Tools' in idx
    assert "...Tools.list.filter(t => !t.settings).map(t => {" in idx
    mapping = idx.split("...Tools.list.filter(t => !t.settings).map(t => {", 1)[1].split("}),", 1)[0]
    assert "label: t.label" in mapping
    assert "link: t.op" in mapping
    assert 'words: t.words.replace(/^tool /, "")' in mapping
    for flag in tool_rows():
        if flag in ("startupManager", "scheduled"):    # Settings pages: literal rows instead
            continue
        assert f"{flag}: {{ key:" in idx, f"{flag}: missing toolMeta"
    assert 'key: "startupApps", label: "Startup apps", cat: "apps"' in idx
    assert 'key: "automations", label: "Automations", cat: "automations"' in idx
    # the old hand-written app *entry rows* are gone (toolMeta still owns the
    # settings keys, so check rows, not the whole file)
    rows = [ln for ln in idx.splitlines() if re.match(r"\s*\{\s*key:", ln)]
    for key in ("appDictionary", "appPodcasts", "appNetTools", "appPasteHistory"):
        assert not any(f'key: "{key}"' in ln for ln in rows), (
            f"{key}: stale hardcoded tool row"
        )


def test_settings_tile_names_use_catalog_and_cover_every_tile():
    page = source(PAGE)
    assert 'import "../../Common/Tools.js" as Tools' in page
    block = tile_names_block()
    assert "Tools.list.forEach" in block
    assert "n[t.flag] = t.label" in block
    literal = set(re.findall(r"([A-Za-z]+):\s*\"", block))
    names = literal | set(tool_rows())
    # stale tile removed in the catalog migration must stay gone
    assert "snippets" not in names and "snippets" not in page
    assert names == sidebar_tids(), (
        "tile lists drift: "
        f"missing={sorted(sidebar_tids() - names)}, "
        f"orphan={sorted(names - sidebar_tids())}"
    )
    for flag, (label, _) in tool_rows().items():
        assert f'{flag}: "{label}"' in block or "n[t.flag] = t.label" in block


# ---- fix 2: no duplicate destination ---------------------------------------


def test_no_duplicate_tool_tile_or_settings_row():
    tiles = source(TILES)
    for flag in tool_rows():
        assert len(re.findall(rf'tid:\s*"{flag}"', tiles)) == 0, flag
    idx = source(INDEX)
    keys = re.findall(r'\{\s*key:\s*"([^"]+)"', idx)
    assert len(keys) == len(set(keys)), "SettingsIndex has duplicate keys"
    links = re.findall(r'link:\s*"([^"]+)"', idx)
    assert len(links) == len(set(links)), "SettingsIndex has duplicate deep links"
    # two literal rows opening "updates" with different names is the duplicate
    updates_rows = [
        ln
        for ln in idx.splitlines()
        if re.match(r"\s*\{\s*key:", ln) and 'cat: "updates"' in ln
    ]
    assert len(updates_rows) == 2  # Updates + the System restore panel
    assert sum('label: "Updates"' in ln for ln in updates_rows) == 1


def test_settings_about_has_no_second_updates_tile():
    about = source(ABOUT)
    assert 'label: Tr.t("Updates"), cat: "updates"' in about
    assert 'label: Tr.t("Firmware"), cat: "updates"' not in about
    assert len(re.findall(r'cat:\s*"updates"', about)) == 1


# ---- fix 3: tiles keep accessibility, tooltip and keyboard activation ------


def test_tile_component_supplies_accessibility_and_keyboard():
    tile = source(TILE_COMPONENT)
    assert "Accessible.role:" in tile
    assert "Accessible.name:" in tile
    assert "Accessible.description:" in tile  # the tile's tooltip text
    assert "Accessible.onPressAction:" in tile
    assert "Accessible.onToggleAction:" in tile
    assert "KeyFocus {" in tile
    assert "onActivated: root.activate()" in tile
    # the generated tool tiles must not shadow the shared component's contract
    delegate = source(TILES).split("model: Tools.list", 1)[1].split("\n        }", 1)[0]
    for prop in ("Accessible.name", "KeyFocus", "Accessible.onPressAction"):
        assert prop not in delegate, f"tool tile redefines {prop}"


# ---- fix 4: one canonical label for the Updates destination ----------------


def test_updates_destination_has_one_canonical_label():
    assert 'key: "updates", label: "Updates", cat: "updates"' in source(INDEX)
    assert 'label: Tr.t("Updates"), cat: "updates"' in source(ABOUT)
    assert 'Tr.t("Updates")' in source(HEADER)
    page = source(PAGE)
    assert 'text: Tr.t("Updates")' in page
    assert 'Tr.t("Update check")' not in page
    assert 'Ui.settingsCat = "updates"' in page
    assert "Updates & going back" not in source(ABOUT)
    assert "Open Updates" not in source(HEADER)
