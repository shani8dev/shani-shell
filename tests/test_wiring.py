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
