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
    ("AppWindow.qml", "win.startSystemMove()"): "dragging the header moves the window; niri's own keys move, maximise and close it",
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


def test_every_theme_token_used_is_declared():
    """`Theme.radiusLg` (another shell's name for it) is undefined, silently: a
    panel's corners, colours and - with it in a binding - whole rows quietly
    fall back or vanish. Six panels carried such names."""
    theme = (SHANI / "Common/Theme.qml").read_text()
    declared = set(re.findall(r"^\s*(?:readonly\s+)?property\s+[\w<>.]+\s+(\w+)", theme, re.M))
    declared |= set(re.findall(r"^\s*function\s+(\w+)", theme, re.M))
    used = {}
    for path, text in qml().items():
        for name in re.findall(r"\bTheme\.(\w+)", text):
            if name not in declared:
                used.setdefault(name, path.name)
    assert used == {}


def test_services_are_reached_the_way_they_are_imported():
    """A panel that imports `qs.Services as Services` and then says `Lock.locked`
    gets a ReferenceError; in `visible: Ui.notes && !Lock.locked` that made the
    whole surface invisible - Notes, Scanner, Passwords, Kundali, LocalSend (since taken out) and
    the video player never showed, and nothing failed."""
    services = {p.stem for p in (SHANI / "Services").glob("*.qml")}
    wrong = {}
    for path, text in qml().items():
        if "Modules" not in path.parts or re.search(r"^import qs\.Services\s*$", text, re.M):
            continue
        code = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', re.sub(r"//[^\n]*", "", text))
        bare = {m for m in re.findall(r"(?<![\w.])([A-Z]\w+)\.\w", code) if m in services}
        if bare:
            wrong[path.name] = sorted(bare)
    assert wrong == {}


def test_every_surface_read_on_first_open_is_there():
    """A `source:` loader names a file; a renamed or moved one is found only
    when a person opens that surface (nothing compiles it at load)."""
    shell = (SHANI / "shell.qml").read_text()
    named = re.findall(r'LazyLoader \{ active: [^;]+; source: "([^"]+)" \}', shell)
    assert len(named) >= 20, "the pattern no longer matches shell.qml"
    assert [n for n in named if not (SHANI / n).is_file()] == []
    # and each is opened, for real, by the suite (dev/shell-parts/apps.sh or the main run)
    opened = "".join((ROOT / f).read_text() for f in ("dev/shell-parts/apps.sh", "bin/shani", "dev/shell-test.sh"))
    for flag in re.findall(r'LazyLoader \{ active: Ui\.(\w+); source:', shell):
        assert re.search(r"\b%s\b" % flag, opened, re.I), f"nothing in the suite opens Ui.{flag}"


def test_a_surface_read_on_first_open_imports_its_own_folder():
    """A file a `source:` loader reads does not see the components beside it
    (measured: "MusicLibraryView is not a type" - the Media Player never
    opened). Using one from its own folder needs `import qs.Modules.<Folder>`."""
    shell = (SHANI / "shell.qml").read_text()
    wrong = []
    for src in re.findall(r'LazyLoader \{ active: [^;]+; source: "([^"]+)" \}', shell):
        f = SHANI / src
        siblings = {p.stem for p in f.parent.glob("*.qml") if p != f}
        used = {name for name in re.findall(r"^\s*([A-Z]\w+)\s*\{", f.read_text(), re.M) if name in siblings}
        module = "qs." + ".".join(f.parent.relative_to(SHANI).parts)
        # the folder's own import, and shell.qml's - without which Quickshell has no such module
        if used and (f"import {module}" not in f.read_text() or f"import {module}\n" not in shell):
            wrong.append(f"{src}: {sorted(used)}")
    assert wrong == []



def test_the_state_has_each_key_once():
    """`state` is one object literal: a key written twice keeps the second, and
    the first silently means nothing - "mediaPlaying" (any MPRIS player) was
    shadowed by the Media Player's own and the media-key checks read the wrong
    one; "notes" meant both "notes loaded" and "the Notes window is open"."""
    shell = (SHANI / "shell.qml").read_text()
    start = shell.index("function state(): string {")
    body = shell[start:shell.index("\n        }\n", start)]
    keys = re.findall(r"(?<![\w.])(\w+):\s", body)
    assert sorted({k for k in keys if keys.count(k) > 1}) == []
