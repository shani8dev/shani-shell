"""Static checks for five stale-state / keyboard fixes in the utility windows.

These three windows need a running shell to exercise, so each test asserts the
source carries the exact wiring rather than driving QML.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_clocks_drops_stale_alarm_confirmation_when_list_changes():
    t = source("shani/Modules/Clocks/ClocksWindow.qml")
    assert "readonly property var alarms: Array.from(WorldClock.alarms || [])" in t
    # an alarm removed from the sidebar shifts the indices, so the pending
    # two-tap confirmation must be dropped instead of deleting the wrong row
    assert "onAlarmsChanged: win.confirmAlarm = -1" in t
    # the two-tap confirmation itself is kept
    assert "win.confirmAlarm === index" in t


def test_characters_focuses_search_when_window_opens():
    t = source("shani/Modules/Characters/CharactersPanel.qml")
    for handler in (
        "onVisibleChanged: if (visible) { Characters.browse(); searchField.forceActiveFocus() }",
        "Component.onCompleted: if (visible) { Characters.browse(); searchField.forceActiveFocus() }",
    ):
        assert handler in t
    # the search field really is the one that got focus
    assert "id: searchField" in t
    assert "onTextChanged: Characters.search(text)" in t


def test_fonts_focuses_search_when_window_opens():
    t = source("shani/Modules/Fonts/FontsPanel.qml")
    for handler in (
        "onVisibleChanged: if (visible) { refresh(); searchField.forceActiveFocus() }",
        "Component.onCompleted: if (visible) { refresh(); searchField.forceActiveFocus() }",
    ):
        assert handler in t
    assert 'objectName: "font-search"' in t


def test_fonts_refresh_clears_stale_counts():
    t = source("shani/Modules/Fonts/FontsPanel.qml")
    refresh = t.split("function refresh() {", 1)[1].split("\n    }", 1)[0]
    for line in (
        "totalFonts = 0;",
        "filteredCount = 0;",
        "truncated = false;",
    ):
        assert line in refresh, f"{line} missing from refresh()"
    # the counts are repopulated when the listing finishes
    assert "win.totalFonts = out.length;" in t
    assert "win.applyFilter();" in t


def test_font_details_are_tied_to_the_selected_font():
    t = source("shani/Modules/Fonts/FontsPanel.qml")
    assert 'property string detailsFor: ""' in t
    # selection records which file the pending query belongs to
    assert 'detailsFor = f.file || "";' in t
    assert 'fontDetails.command = ["fc-query"' in t
    assert "fontDetails.running = true" in t
    # a late result for a different font is ignored
    guard = t.split("id: fontDetails", 1)[1]
    assert "win.selectedFont.file !== win.detailsFor" in guard
    assert "win.selectedDetails = [" in guard
