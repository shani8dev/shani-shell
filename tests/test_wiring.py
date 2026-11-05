"""The shell's wiring: what one place defines, the place that should reach it does.

Each of these broke once without any test noticing: a tile written but missing
from the grid's list (the keyboard backlight's, never shown on any laptop), a
key bound to an IPC function that is not there, a setting read but never
declared (undefined, silently), a Ui member used but never declared.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"
NIRI_CONFIGS = [ROOT / "dev/niri/session.kdl",
                ROOT.parent / "shani-pkgbuilds/shani-desktop-niri/etc/niri/config.kdl"]


def qml():
    return {p: p.read_text() for p in SHANI.rglob("*.qml")}


def test_every_tile_is_in_the_grid():
    t = (SHANI / "Modules/ControlCenter/SidebarTiles.qml").read_text()
    known = set(re.findall(r'"([a-z]+)"', re.search(r"readonly property var known: \[([^\]]*)\]", t).group(1)))
    tiles = set(re.findall(r'tid: "([a-z]+)"', t))
    assert tiles - known == set(), "tiles that can never show"
    assert known - tiles == set(), "names in the grid with no tile"


def test_every_bound_key_reaches_a_function():
    shell = (SHANI / "shell.qml").read_text()
    functions = set(re.findall(r"^\s+function (\w+)\(", shell, re.M))
    for f in NIRI_CONFIGS:
        if f.exists():
            missing = set(re.findall(r'"ipc" "call" "shani" "(\w+)"', f.read_text())) - functions
            assert missing == set(), f"{f.name} calls IPC the shell does not have"


def test_the_same_keys_are_bound_where_the_tests_run_and_where_people_do():
    found = [set(re.findall(r"^\s+(XF86\w+)", f.read_text(), re.M)) for f in NIRI_CONFIGS if f.exists()]
    if len(found) == 2:
        assert found[0] == found[1]


def test_every_setting_read_is_declared():
    declared = set(re.findall(r"property [\w<>]+ (\w+)", (SHANI / "Common/Settings.qml").read_text()))
    used = {k for s in qml().values() for k in re.findall(r"(?:Settings\.data|page\.d)\.(\w+)", s)}
    assert used - declared == set()


def test_every_ui_member_used_is_declared():
    ui = (SHANI / "Common/Ui.qml").read_text()
    declared = set(re.findall(r"(?:property [\w<>]+|function|signal) (\w+)", ui))
    used = {k for s in qml().values() for k in re.findall(r"\bUi\.(\w+)", s) if not k.startswith("on")}
    assert used - declared == set()


# ---- keyboard: every click in the main surfaces has a keyboard way too ----------------
# A MouseArea or TapHandler that does something on a click must sit beside a KeyFocus
# (Common/KeyFocus: Enter / Space / Menu do what the click does) or a Keys handler in
# the same item - or be listed here with the reason it needs none.
KEYBOARD_SURFACES = ["shani/Modules/ControlCenter", "shani/Modules/Dock", "shani/Modules/Notifications",
                     "shani/Modules/Settings", "shani/Modules/Lock", "shani/Modules/Bar", "shani/Modules/WindowMenu",
                     "shani/Modules/Background/Wallpaper.qml", "shani/Common", "greeter/shell.qml", "setup/shell.qml"]
KEYBOARD_EXEMPT = {
    ("Sidebar.qml", "onClicked: Ui.closeAll()"): "a click outside closes it; Escape does that",
    ("Dock.qml", "onClicked: win.menuFor = -1"): "a click elsewhere closes the menu; Escape does that",
    ("Tile.qml", "onClicked: root.detail()"): "the chevron: the tile's Menu key opens the detail",
    ("SettingsDisplays.qml", "id: drag"): "dragging screens into place; position is also offered as choices",
    ("Wallpaper.qml", "deskMenu.visible = false"): "a click on the desktop; the menu opens from Mod+F10 too",
    ("DesktopIcons.qml", ""): "not a main surface",
    ("WindowMenu.qml", "onClicked: Ui.windowMenu = false"): "a click outside closes it; Escape does that",
    ("TimePicker.qml", ""): "its hour and minute steppers are IconButtons",
    ("Dock.qml", "id: trashMenu"): "the trash tile's own KeyFocus (DockTile) sends the Menu key here",
    ("WorldMap.qml", "map.nearest"): "a click on the map; the same time zones are a list to pick from",
}


def _blocks(text):
    """(start, end, parent_start, parent_end) of every MouseArea / TapHandler block."""
    out, stack = [], []
    for m in re.finditer(r"[{}]", text):
        if m.group() == "{":
            stack.append(m.start())
        else:
            s = stack.pop()
            head = text[text.rfind("\n", 0, s) + 1:s]
            if re.search(r"\b(MouseArea|TapHandler)\s*$", head):
                out.append((s, m.end(), stack[-1] if stack else 0))
    return out


def test_every_click_has_a_keyboard_way():
    missing = []
    for spec in KEYBOARD_SURFACES:
        p = ROOT / spec
        for f in ([p] if p.is_file() else sorted(p.glob("*.qml"))):
            text = f.read_text()
            for s, e, ps in _blocks(text):
                body = text[s:e]
                if not re.search(r"\bon(Clicked|Tapped|DoubleClicked)\s*:", body):
                    continue
                # the parent item's own text: its KeyFocus or Keys handler, beside the area
                depth, i = 0, ps
                for i in range(ps, len(text)):
                    depth += {"{": 1, "}": -1}.get(text[i], 0)
                    if depth == 0:
                        break
                parent = text[ps:i]
                if "KeyFocus {" in parent or "KeyFocus{" in parent or "Keys.on" in parent:
                    continue
                if any(f.name == fn and snip in body for (fn, snip) in KEYBOARD_EXEMPT):
                    continue
                line = text.count("\n", 0, s) + 1
                missing.append(f"{f.relative_to(ROOT)}:{line}")
    assert missing == [], f"clickable with no keyboard way (add a KeyFocus, or exempt it with a reason): {missing}"
