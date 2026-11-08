"""Multi-note QuickNotes, the Characters panel and WorldClock's alarms
and stopwatch, checked statically (QML) and against the character table
(bridge/characters.py).

The static checks mirror tests/test_wiring.py: every Settings.alarms and
Ui.characters read is declared, the new surfaces are reachable (shell
LazyLoader + IPC + state), the laundry that must never regress — one
.md per note, autosave, [[links]], minute-aligned alarm checks,
notify-send rings — is present in the sources.
"""
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"
BRIDGE = ROOT / "bridge" / "characters.py"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def load_bridge():
    spec = importlib.util.spec_from_file_location("characters", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---- the character table -----------------------------------------------------

def test_table_covers_symbols_arrows_math_and_indic():
    m = load_bridge()
    entries = m.iter_entries()
    assert len(entries) > 5000
    names = {e["name"] for e in entries}
    for want in ["RIGHTWARDS ARROW", "PLUS-MINUS SIGN", "INFINITY",
                 "CHECK MARK", "SNOWMAN", "DEVANAGARI LETTER A",
                 "BENGALI LETTER A", "TAMIL LETTER A", "GREEK SMALL LETTER ALPHA"]:
        assert want in names, want


def test_search_ranks_starts_and_finds_scripts_by_keyword():
    m = load_bridge()
    top = m.search("arrow", 10)
    assert top, "no arrows"
    assert all("ARROW" in e["name"] for e in top[:5])
    dev = m.search("devanagari", 20)
    assert dev and all("DEVANAGARI" in e["name"] for e in dev[:10])
    rupee = m.search("rupee", 10)
    assert any("RUPEE" in e["name"] for e in rupee)
    assert any(e["ch"] == "✓" for e in m.search("check", 10))


def test_search_output_is_json_for_the_shell():
    r = subprocess.run([sys.executable, str(BRIDGE), "search", "star", "--limit", "5"],
                       capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    data = json.loads(r.stdout)
    assert data and all(set(e) >= {"ch", "name", "cp"} for e in data)
    assert any("STAR" in e["name"] for e in data)
    r = subprocess.run([sys.executable, str(BRIDGE), "search", "", "--limit", "5"],
                       capture_output=True, text=True, timeout=30)
    assert r.returncode == 0 and len(json.loads(r.stdout)) == 5


def test_search_handles_multi_word_and_junk():
    m = load_bridge()
    assert m.search("rightwards arrow", 5)
    assert m.search("  NO SUCH GLYPH  ", 5) == [] or m.search("zzzqqq", 5) == []


# ---- QuickNotes: one .md per note, autosave, [[links]] -----------------------

def test_quicknotes_is_a_folder_of_markdown_notes():
    t = read("shani/Services/QuickNotes.qml")
    assert '"/Notes"' in t
    assert "notes" in t and "current" in t
    for fn in ["function open(", "function create(", "function rename(", "function remove(", "function search(", "function links(", "function jumpTo("]:
        assert fn in t, fn
    # autosave, and the legacy single file still reads as a note
    assert "file.setText(root.text)" in t
    assert "interval: 600" in t
    assert "[[" in t


def test_sidebar_notes_reaches_the_service():
    t = read("shani/Modules/ControlCenter/SidebarNotes.qml")
    assert "QuickNotes.create(" in t and "QuickNotes.rename(" in t
    assert "QuickNotes.remove(" in t and "QuickNotes.search(" in t
    assert "QuickNotes.jumpTo(" in t and "QuickNotes.open(" in t
    assert "[[Like this]]" in t or "[[" in t


# ---- WorldClock: alarms + stopwatch ------------------------------------------

def test_worldclock_alarms_shrink_to_minute_checks_and_notify_send():
    t = read("shani/Services/WorldClock.qml")
    assert "msToNextMinute" in t and "alarmClock" in t
    assert "notify-send" in t and "-u" in t and "critical" in t
    for fn in ["function addAlarm(", "function removeAlarm(", "function checkAlarms("]:
        assert fn in t, fn
    assert "lastFired" in t          # rings once, not while the minute holds
    assert "Settings.data.alarms" in t


def test_worldclock_stopwatch_has_start_pause_reset_laps():
    t = read("shani/Services/WorldClock.qml")
    for fn in ["function swStart(", "function swPause(", "function swReset(", "function swLap(", "function swToggle("]:
        assert fn in t, fn
    assert "swRunning" in t and "swLaps" in t and "swDisplay" in t
    assert "interval: 47" in t


def test_sidebar_clock_reaches_worldclock():
    t = read("shani/Modules/ControlCenter/SidebarClock.qml")
    assert "WorldClock.addAlarm(" in t and "WorldClock.removeAlarm(" in t
    assert "WorldClock.swToggle(" in t and "WorldClock.swLap(" in t and "WorldClock.swReset(" in t
    assert "TimePicker" in t
    sidebar = read("shani/Modules/ControlCenter/Sidebar.qml")
    assert "SidebarClock" in sidebar


# ---- registration -------------------------------------------------------------

def test_characters_panel_is_registered():
    shell = read("shani/shell.qml")
    assert "CharactersPanel" in shell and "Characters" in shell
    assert "function toggleCharacters(" in shell
    ui = read("shani/Common/Ui.qml")
    assert "property bool characters" in ui
    assert "characters = false" in ui
    settings = read("shani/Common/Settings.qml")
    assert "property var alarms" in settings


def test_launcher_colon_searches_unicode_too():
    t = read("shani/Modules/Launcher/Launcher.qml")
    assert "Characters.search(" in t and "Characters.results" in t
    assert "Emoji & characters" in t


def test_characters_panel_copies_on_click_and_key():
    t = read("shani/Modules/Characters/CharactersPanel.qml")
    assert "Characters.copy(" in t
    assert "onPressAction: Characters.copy(" in t
    assert "KeyFocus" in t and "Keys.onEscapePressed" in t
    assert "characters" in t  # file location


def test_new_tiles_are_in_the_grid():
    t = read("shani/Modules/ControlCenter/SidebarTiles.qml")
    known = set(re.findall(r'"([a-z]+)"', re.search(r"readonly property var known: \[([^\]]*)\]", t).group(1)))
    tiles = set(re.findall(r'tid: "([a-z]+)"', t))
    assert "characters" in known and "characters" in tiles
    assert tiles - known == set() and known - tiles == set()
