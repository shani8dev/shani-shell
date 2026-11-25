"""Static asserts for module uniformity round 4.

Owned files migrate hand-rolled patterns to shared components where the shape
matches: ConfirmButton for stable two-tap confirms, BusyNote for busy rows,
EmptyState for empty placeholders, SearchField for search+clear. Unsafe
confirms stay hand-rolled with a shortcut note.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_terminal_host_search_uses_searchfield():
    text = source("shani/Modules/Terminal/TerminalAppWindow.qml")
    assert "SearchField {" in text
    assert "id: hostSearch" in text
    assert "hostSearch.input.forceActiveFocus()" in text


def test_terminal_snippet_search_uses_searchfield():
    text = source("shani/Modules/Terminal/TerminalAppWindow.qml")
    assert "id: snipSearch" in text
    assert "snipSearch.input.forceActiveFocus()" in text


def test_terminal_unsafe_delete_confirm_has_shortcut_note():
    text = source("shani/Modules/Terminal/TerminalAppWindow.qml")
    # Delete confirm is coupled to keyboard Delete + global warning text;
    # replacing with per-row ConfirmButton would change behavior.
    assert "confirmingDelete" in text
    assert "shortcut:" in text


def test_services_window_keeps_shared_components():
    text = source("shani/Modules/Services/ServicesWindow.qml")
    assert "ConfirmButton {" in text
    assert "EmptyState {" in text


def test_sidebar_clock_unsafe_row_confirm_has_shortcut_note():
    text = source("shani/Modules/ControlCenter/SidebarClock.qml")
    # Alarm removal fires on row click (two-tap on ListRow), not a dedicated
    # button; converting to ConfirmButton would change affordance/behavior.
    assert "shortcut:" in text
