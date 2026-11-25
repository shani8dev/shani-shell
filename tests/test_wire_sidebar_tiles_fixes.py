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

    for flag in NEW_FLAGS:
        assert re.search(r"property bool %s\b" % flag, ui_src), (
            "Ui.%s is not declared" % flag
        )
        assert '"%s"' % flag in known_block, "%s missing from `known`" % flag
        assert flag in tile_bodies, "no tile with tid %r" % flag
        body = tile_bodies[flag]
        assert "Ui.closeAll();" in body, "%s tile does not close the old surface" % flag
        assert "Ui.%s = true;" % flag in body, "%s tile does not open Ui.%s" % (
            flag,
            flag,
        )

    # full parity: the existing `[a-z]+` test cannot see camelCase ids, so
    # check every id here with a pattern that can
    known = set(re.findall(r'"([A-Za-z]+)"', known_block))
    tids = set(re.findall(r'tid: "([A-Za-z]+)"', tiles_src))
    assert tids - known == set(), "tiles that can never show: %s" % sorted(tids - known)
    assert known - tids == set(), "names with no tile: %s" % sorted(known - tids)
