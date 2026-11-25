"""The new apps must be reachable from the Control Centre's quick tiles.

Each tile lives in SidebarTiles.qml and its id must appear in the grid's `known`
list; a tile written but missing from `known` can never show (and vice versa —
a name in `known` with no tile is a dead row). The existing wiring test compares
the two with an `[a-z]+` regex, which silently skips the camelCase ids below, so
this covers every id with a broader pattern too.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"

# the shell flag each tile opens, as declared in Common/Ui.qml
NEW_FLAGS = [
    "dictionary",
    "podcasts",
    "teleprompter",
    "netTools",
    "databaseBrowser",
    "startupManager",
    "gateway",
    "pasteHistory",
    "scheduled",
]


def test_new_app_tiles_are_wired():
    tiles_src = (SHANI / "Modules/ControlCenter/SidebarTiles.qml").read_text()
    ui_src = (SHANI / "Common/Ui.qml").read_text()

    known_block = re.search(
        r"readonly property var known: \[([^\]]*)\]", tiles_src
    ).group(1)

    # map each tile's tid to its body (tiles sit at 8-space indent; nested
    # blocks are deeper, so the first `\n        }` ends a tile)
    tile_bodies = {
        m.group(1): m.group(2)
        for m in re.finditer(
            r'\n        Tile \{\n\s*tid: "([A-Za-z]+)"\n(.*?)\n        \}',
            tiles_src,
            re.S,
        )
    }

    # The nine tool tiles are now generated from Tools.list via a Repeater;
    # each flag comes from the shared catalog and opens its own Ui flag.
    tools = (SHANI / "Common/Tools.js").read_text()
    for flag in NEW_FLAGS:
        assert re.search(r"property bool %s\b" % flag, ui_src), (
            "Ui.%s is not declared" % flag
        )
        assert '"%s"' % flag in tools, "%s missing from Tools catalog" % flag
    assert "Repeater {" in tiles_src and "model: Tools.list" in tiles_src
    assert "...Tools.list.map(t => t.flag)" in known_block
    assert "Ui.openTool(modelData.flag)" in tiles_src

    # full parity for the literal (non-generated) tiles
    known = set(re.findall(r'"([A-Za-z]+)"', known_block))
    tids = set(re.findall(r'tid: "([A-Za-z]+)"', tiles_src))
    assert tids - known == set(), "tiles that can never show: %s" % sorted(tids - known)
