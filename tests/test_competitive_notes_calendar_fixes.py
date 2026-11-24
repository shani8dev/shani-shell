"""Static checks for the notes/calendar competitive gaps.

Both surfaces are Quickshell QML windows; the tests assert source wiring so a
later edit cannot silently drop a fix. The gap list these close was derived
from GNOME Calendar/Notes, KDE Kontact/KOrganizer and macOS Calendar/Notes.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTES = ROOT / "shani/Modules/Notes/NotesPanel.qml"
CALENDAR = ROOT / "shani/Modules/Calendar/CalendarPanel.qml"


def test_notes_rename_open_note_from_title():
    """GNOME/KDE notes let you rename a note in place; before, the title was
    a read-only Label and renaming meant a file manager."""
    s = NOTES.read_text(encoding="utf-8")
    assert "id: titleField" in s
    assert "onAccepted: win.renameCurrent(text)" in s
    assert (
        "Services.QuickNotes.rename(old, n, Services.QuickNotes.currentNotebook)" in s
    )
    # the field must resync when the service switches notes
    assert (
        "function onCurrentChanged() { titleField.text = Services.QuickNotes.current; }"
        in s
    )


def test_notes_keyboard_shortcuts_new_and_find():
    """macOS/GTK note apps wire Ctrl+N (new) and Ctrl+F (find); neither was
    present in NotesPanel before."""
    s = NOTES.read_text(encoding="utf-8")
    assert (
        'Shortcut { sequence: "Ctrl+N"; onActivated: Services.QuickNotes.create(' in s
    )
    assert (
        'Shortcut { sequence: "Ctrl+F"; onActivated: filterField.forceActiveFocus() }'
        in s
    )
    assert "id: filterField" in s


def test_calendar_search_covers_title_place_and_notes():
    """KOrganizer/GNOME Calendar search the whole event, not only its title."""
    s = CALENDAR.read_text(encoding="utf-8")
    assert '["summary", "location", "description"].some(k =>' in s
    assert 'String(e[k] || "").toLowerCase().indexOf(needle) >= 0' in s
    assert "Search title, place or notes" in s


def test_calendar_jump_to_date():
    """Every competitor has a go-to-date action; paging 12 months to last
    February was the only path before."""
    s = CALENDAR.read_text(encoding="utf-8")
    assert "function goToDate(text) {" in s
    assert 'String(text || "").trim().match(/^(\\d{4})-(\\d{2})-(\\d{2})$/)' in s
    assert 'Choice { text: Tr.t("Go to date…")' in s
    assert "id: dateField" in s
    assert 'onAccepted: { if (win.goToDate(text)) text = "" }' in s


def test_calendar_all_day_labels_real_date():
    """An all-day event detail sheet said 'Today' even for a date months away;
    the day list also gave no all-day hint."""
    s = CALENDAR.read_text(encoding="utf-8")
    assert "function detailWhen(e) {" in s
    assert 'e.allDay ? day + " · " + Tr.t("All day")' in s
    assert "text: win.detailWhen(win.viewingEvent)" in s
    assert '(modelData.allDay ? " · " + Tr.t("All day") : "")' in s
