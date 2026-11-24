"""The desktop widget catalogue is data, not a new data source.

SettingsPage and MoreWidgets read WidgetRegistry instead of hard-coding what
each widget is; the registry must stay a metadata-only singleton. QML is not
executable here, so isAvailable is checked as pure logic over the same decision
table, with the service facts supplied as state.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "shani/Services/WidgetRegistry.qml"
SETTINGS = ROOT / "shani/Modules/Settings/SettingsPage.qml"
MORE = ROOT / "shani/Modules/Background/MoreWidgets.qml"
DESKTOP = ROOT / "shani/Modules/Background/DesktopWidgets.qml"

ENTRY = re.compile(
    r'\{\s*id:\s*"(?P<id>[^"]+)",\s*'
    r'label:\s*"(?P<label>[^"]+)",\s*'
    r'desc:\s*"(?P<desc>[^"]+)",\s*'
    r"size:\s*\{\s*w:\s*(?P<w>\d+),\s*h:\s*(?P<h>\d+)\s*\},\s*"
    r'service:\s*"(?P<service>[^"]+)",\s*'
    r'need:\s*"(?P<need>[^"]+)",\s*'
    r'note:\s*"(?P<note>[^"]*)"\s*\}'
)

# the eight toggles in Settings, as their cards name them in the two surfaces
EXPECTED = {
    "clock": "Clock",
    "media": "Now playing",
    "weather": "Weather",
    "stats": "System monitor",
    "agenda": "Agenda",
    "battery": "Battery",
    "note": "Note",
    "clocks": "World clocks",
}


def catalog():
    return {m.group("id"): m.groupdict() for m in ENTRY.finditer(REGISTRY.read_text())}


def widget_ids():
    """Ids the widget surfaces actually place on the desktop."""
    more = set(re.findall(r'^\s*key:\s*"([^"]+)"', MORE.read_text(), re.M))
    desktop = set(re.findall(r'indexOf\("([^"]+)"\)\s*>=\s*0', DESKTOP.read_text()))
    return more | desktop


def test_catalog_labels_match_the_widgets_that_are_placed():
    entries = catalog()
    assert set(entries) == set(EXPECTED) == widget_ids()
    assert {k: v["label"] for k, v in entries.items()} == EXPECTED
    for entry in entries.values():
        assert entry["desc"], entry
        assert int(entry["w"]) > 0 and int(entry["h"]) > 0, entry
        assert entry["service"], entry


def test_settings_and_more_widgets_read_the_registry():
    settings = SETTINGS.read_text()
    more = MORE.read_text()
    assert "model: WidgetRegistry.catalog" in settings
    assert "text: Tr.t(WidgetRegistry.labelFor(modelData.id))" in settings
    assert "WidgetRegistry.descFor(modelData.id)" in settings
    assert "WidgetRegistry.noteFor(modelData.id)" in settings
    assert "indexOf(modelData.id)" in settings  # the toggle is unchanged
    assert "WidgetRegistry.descFor(key)" in more
    assert "WidgetRegistry.labelFor(cw.key)" in more
    # the search keywords and the drag/lock behaviour are untouched
    assert 'words: "wallpaper style colours' in settings
    assert "drag.target: scr.widgetsLocked ? null : glass" in more


def test_registry_is_metadata_only():
    source = REGISTRY.read_text()
    assert "pragma Singleton" in source
    for banned in (
        "Process {",
        "Timer {",
        "FileView {",
        "running:",
        "interval:",
        "Quickshell.exec",
        "WlrLayershell",
        "PanelWindow",
    ):
        assert banned not in source, banned
    for helper in ("labelFor(id)", "descFor(id)", "isAvailable(id)"):
        assert f"function {helper}" in source


def test_is_available_uses_only_existing_services():
    source = REGISTRY.read_text()
    assert "if (!e) return false;" in source  # an unknown id is never available
    cases = dict(re.findall(r'case "(\w+)":\s*return (.+?);', source))
    assert cases == {
        "net": "Net.online && Weather.enabled",
        "calendar": "Agenda.available",
        "battery": "Power.hasBattery",
        "cities": "WorldClock.clocks.length > 0",
        "player": "Media.current !== null",
    }


def is_available(entry, state):
    """Pure mirror of the registry's switch, over supplied service facts."""
    need = entry["need"]
    if need == "net":
        return state["net"] and state["city"]
    if need == "player":
        return state["player"]
    if need == "calendar":
        return state["calendar"]
    if need == "battery":
        return state["battery"]
    if need == "cities":
        return state["cities"] > 0
    return True


def test_is_available_pure_logic():
    entries = catalog()
    offline = dict(
        net=False, city=True, player=True, calendar=True, battery=True, cities=2
    )
    assert not is_available(entries["weather"], offline)
    assert is_available(entries["clock"], offline)  # no condition
    assert is_available(entries["stats"], offline)

    nocity = dict(offline, net=True, city=False)
    assert not is_available(entries["weather"], nocity)
    assert is_available(entries["weather"], dict(nocity, city=True))

    bare = dict(
        net=True, city=True, player=False, calendar=False, battery=False, cities=0
    )
    assert not is_available(entries["media"], bare)
    assert not is_available(entries["agenda"], bare)
    assert not is_available(entries["battery"], bare)
    assert not is_available(entries["clocks"], bare)
    assert is_available(entries["note"], bare)
    assert is_available(entries["clocks"], dict(bare, cities=1))
    assert is_available(entries["battery"], dict(bare, battery=True))
