"""Static and JS-unit checks for the calendar/agenda competitive upgrade.

Benchmarks: GNOME Calendar (quick add, search everywhere, drag to reschedule,
Home/PageUp navigation), KDE KOrganizer (agenda of upcoming/overdue items,
recurrence with interval and weekdays) and Apple Calendar (drag between days,
all-day/timed conversion with the clock kept, deliberate delete). Quickshell
QML cannot run under pytest here, so the wiring is asserted on source and the
natural-language parser is executed with node.
"""

import json
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PANEL_PATH = ROOT / "shani/Modules/Calendar/CalendarPanel.qml"
SERVICE_PATH = ROOT / "shani/Services/Agenda.qml"
PANEL = PANEL_PATH.read_text(encoding="utf-8")
SERVICE = SERVICE_PATH.read_text(encoding="utf-8")

node = shutil.which("node")
node_mark = pytest.mark.skipif(node is None, reason="node is not installed")


def _js_function(source, name):
    """Extract one balanced-brace JS function body from QML source."""
    start = source.index("function " + name + "(")
    brace = source.index("{", start)
    depth = 0
    for i in range(brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start : i + 1]
    raise AssertionError("unbalanced function " + name)


# ---- keyboard navigation ---------------------------------------------------


def test_navigation_keys_are_wired_to_the_grid():
    assert "function handleCalendarKey(key) {" in PANEL
    for key in (
        "Qt.Key_Left",
        "Qt.Key_Right",
        "Qt.Key_Up",
        "Qt.Key_Down",
        "Qt.Key_Home",
        "Qt.Key_End",
        "Qt.Key_PageUp",
        "Qt.Key_PageDown",
    ):
        assert key in PANEL, key
    assert "Keys.onPressed: event => {" in PANEL
    assert "if (win.handleCalendarKey(event.key)) event.accepted = true;" in PANEL
    assert "function stepSelected(delta) {" in PANEL
    assert "function selectMonthEnd() {" in PANEL


def test_navigation_keeps_the_selected_day_on_screen():
    # a plain "selectedDate = d" would leave the selected day outside the
    # displayed week/month after a boundary crossing
    assert "Math.round((d - weekStart) / 86400000)" in PANEL
    assert "if (days < 0) offset += Math.ceil(days / 7);" in PANEL
    assert "else if (days >= 7) offset += Math.floor(days / 7);" in PANEL
    assert "if (dm !== 0) offset += dm;" in PANEL
    assert "selectedDate = weekDays[6];" in PANEL
    assert "new Date(month.getFullYear(), month.getMonth() + 1, 0)" in PANEL


# ---- drag / move -----------------------------------------------------------


def test_move_preserves_the_event_and_respects_read_only():
    assert "function isReadOnly(e) {" in PANEL
    assert "return !!(cal && cal.readOnly);" in PANEL
    assert "function moveEventTo(e, day, hour, asAllDay) {" in PANEL
    assert "if (!e || win.isReadOnly(e))" in PANEL
    assert "const dur = Math.max(3600, (e.end || (e.start + 3600)) - e.start);" in PANEL
    assert (
        'Agenda.editEvent({ uid: e.uid, summary: e.summary || "", start: ns, end: ns + dur,'
        in PANEL
    )
    assert (
        'alarm: Number(e.alarm || 0), timezone: e.timezone || "", attendees: e.attendees || [],'
        in PANEL
    )
    assert 'allDay: allDay, calendar: e.calendar || "" }' in PANEL
    assert "Agenda.refresh();" in PANEL


def test_drag_sources_and_day_hour_drop_targets_are_wired():
    assert PANEL.count('Drag.keys: ["shani-event"]') == 2
    assert PANEL.count("DropArea {") == 2
    assert "win.moveEventTo(e, win.weekDays[allDayCell.index], 0, true)" in PANEL
    assert (
        "win.moveEventTo(e, win.weekDays[hourCell.index], hourRow.hour, false)" in PANEL
    )
    assert "drag.target: parent" in PANEL
    assert "drag.threshold: Theme.px(8)" in PANEL


# ---- all-day / timed -------------------------------------------------------


def test_all_day_toggle_keeps_the_original_clock():
    assert "function toggleAllDay() {" in PANEL
    assert "fSavedTimeA = fTimeA.text;" in PANEL
    assert "fSavedTimeB = fTimeB.text;" in PANEL
    assert 'fTimeA.text = "00:00";' in PANEL
    assert 'fTimeB.text = "23:59";' in PANEL
    assert 'fTimeA.text = fSavedTimeA !== "" ? fSavedTimeA : "09:00";' in PANEL
    assert "onClicked: win.toggleAllDay()" in PANEL
    assert "Toggle all-day; the original time is kept" in PANEL


# ---- recurrence ------------------------------------------------------------


def test_recurrence_edits_interval_and_weekdays():
    assert "property int fRepeatInterval: 1" in PANEL
    assert '";INTERVAL=" + Math.max(1, Math.min(99, win.fRepeatInterval))' in PANEL
    assert '";BYDAY=" + win.fByDay' in PANEL
    assert "function formFromRule(rule) {" in PANEL
    assert r"/INTERVAL=(\d+)/" in PANEL
    assert r"/BYDAY=((?:MO|TU|WE|TH|FR|SA|SU)" in PANEL
    assert "function toggleRepeatDay(day) {" in PANEL
    assert "model: win.repeatDays" in PANEL
    assert "onClicked: win.toggleRepeatDay(modelData)" in PANEL
    assert "input.validator: IntValidator { bottom: 1; top: 99 }" in PANEL


def test_complex_recurrence_is_reported_instead_of_flattened():
    assert "readonly property bool complexRule" in PANEL
    assert "/(COUNT|BYMONTHDAY|BYSETPOS|BYMONTH|WKST)/.test(r)" in PANEL
    assert "visible: win.complexRule" in PANEL
    assert 'if (original !== "" && !win.repeatTouched) return original;' in PANEL


# ---- quick add -------------------------------------------------------------


def test_quick_add_validates_and_reports_errors():
    assert "function quickAdd(text) {" in PANEL
    assert 'quickError = Tr.t("Type something like' in PANEL
    assert 'quickError = Tr.t("Could not read a date' in PANEL
    assert "error: win.quickError" in PANEL
    assert 'onTextChanged: win.quickError = ""' in PANEL
    assert "onAccepted: { if (win.quickAdd(text)) clear(); }" in PANEL


def test_relative_dates_are_anchored_on_the_selected_day():
    assert "function _parseNaturalDateTime(text, anchor) {" in PANEL
    assert "const base = anchor instanceof Date ? anchor : selectedDate;" in PANEL
    assert "targetDay = base.getDay();" in PANEL
    assert "const d = new Date(base.getTime());" in PANEL
    assert 'String(t[1]).padStart(2, "0") + ":" + t[2]' in PANEL
    assert (
        '_parseNaturalDateTime(fTitle.text + " " + fDateA.text + " " + fTimeA.text, selectedDate)'
        in PANEL
    )


@node_mark
def test_parser_uses_the_anchor_not_the_wall_clock():
    js = (
        """
    var selectedDate = new Date(2026, 10, 20, 0, 0, 0, 0);  // 20 Nov 2026
    var fAllDay = false;
    """
        + _js_function(PANEL, "_parseDateTime")
        + "\n"
        + _js_function(PANEL, "_parseNaturalDateTime")
        + """
    var out = {
      tomorrow: _parseNaturalDateTime("tomorrow at 3pm"),
      weekday: _parseNaturalDateTime("monday at 9:30"),
      iso: _parseNaturalDateTime("2026-11-25 9:30"),
      nonsense: _parseNaturalDateTime("just some words"),
      anchored: _parseNaturalDateTime("tomorrow at noon", new Date(2027, 0, 4))
    };
    process.stdout.write(JSON.stringify(out));
    """
    )
    out = json.loads(
        subprocess.run(
            [node, "-e", js], capture_output=True, text=True, check=True
        ).stdout
    )
    assert out["tomorrow"] == int(datetime(2026, 11, 21, 15, 0).timestamp())
    assert out["weekday"] == int(datetime(2026, 11, 23, 9, 30).timestamp())
    assert out["iso"] == int(datetime(2026, 11, 25, 9, 30).timestamp())
    assert out["nonsense"] is None or str(out["nonsense"]) == "NaN"
    assert out["anchored"] == int(datetime(2027, 1, 5, 12, 0).timestamp())


# ---- agenda view -----------------------------------------------------------


def test_agenda_view_shows_upcoming_and_earlier():
    assert 'text: Tr.t("Agenda")' in PANEL
    assert 'Ui.calendarView = "agenda"' in PANEL
    assert 'if (view === "agenda") return Tr.t("Agenda");' in PANEL
    assert "readonly property var agendaUpcoming:" in PANEL
    assert "readonly property var agendaEarlier:" in PANEL
    assert "property bool showEarlier: true" in PANEL
    assert 'text: Tr.t("Upcoming (%1)").arg(win.agendaUpcoming.length)' in PANEL
    assert 'Tr.t("Ended") + " " + Agenda.when(modelData)' in PANEL
    assert "function showDayOf(e) {" in PANEL
    assert "win.agendaUpcoming.slice(0, 20)" in PANEL


def test_agenda_loads_a_window_with_past_and_future_events():
    assert '} else if (view === "agenda") {' in PANEL
    assert "today.getDate() - 14 + offset * 7" in PANEL
    assert "a.getDate() + 42" in PANEL
    assert 'if (view === "week" || view === "agenda")' in PANEL


# ---- search ----------------------------------------------------------------


def test_search_is_global_multi_term_and_clearable():
    assert "readonly property bool searchActive:" in PANEL
    assert "readonly property var searchTerms:" in PANEL
    assert "readonly property var searchResults:" in PANEL
    assert "return searchTerms.every(t => hay.indexOf(t) >= 0);" in PANEL
    assert "model: win.searchActive ? win.searchResults : win.shownEvents" in PANEL
    assert 'icon: "edit-clear"' in PANEL
    assert 'tip: Tr.t("Clear search")' in PANEL
    assert "matches across all calendars" in PANEL
    assert "if (win.searchActive) win.showDayOf(modelData);" in PANEL


# ---- error states ----------------------------------------------------------


def test_service_reports_read_and_write_failures_to_the_panel():
    assert 'property string loadError: ""' in SERVICE
    assert 'property string writeError: ""' in SERVICE
    assert 'root.loadError = Tr.t("Could not read the calendar");' in SERVICE
    assert 'root.loadError = Tr.t("No calendar service' in SERVICE
    assert 'root.writeError = Tr.t("Not saved' in SERVICE
    assert 'root.writeError = Tr.t("Handed to Chronoa' in SERVICE
    assert 'if (code === 0) root.writeError = "";' in SERVICE
    assert 'visible: !win.editor && Agenda.loadError !== ""' in PANEL
    assert "text: Agenda.loadError" in PANEL
    assert "text: Agenda.writeError" in PANEL


# ---- deliberate delete -----------------------------------------------------


def test_delete_needs_a_second_click():
    assert "property bool confirmDelete: false" in PANEL
    assert 'formError = Tr.t("Click Delete again to remove this event");' in PANEL
    assert "if (!win.confirmDelete) {" in PANEL
    assert "win.confirmDelete = true;" in PANEL
    assert 'win.confirmDelete ? Tr.t("Confirm delete") : Tr.t("Delete")' in PANEL
    assert "if (!editingEvent || win.readOnlyEvent)" in PANEL


# ---- accessibility ---------------------------------------------------------


def test_accessible_names_describe_events_and_actions():
    assert 'Tr.t("has events")' in PANEL
    assert 'Tr.t("drag to another day")' in PANEL
    assert 'Tr.t("drag to another day or hour")' in PANEL
    assert 'Tr.t("Agenda: upcoming and earlier events")' in PANEL
    assert 'Accessible.name: Tr.t("New event")' in PANEL
    assert 'Accessible.name: Tr.t("Clear search")' in PANEL


# ---- nothing previously built was lost ------------------------------------


def test_existing_calendar_wiring_still_there():
    for snippet in (
        "function goToDate(text) {",
        "function detailWhen(e) {",
        'e.allDay ? day + " · " + Tr.t("All day")',
        '(modelData.allDay ? " · " + Tr.t("All day") : "")',
        '["summary", "location", "description"].some(k =>',
        'String(e[k] || "").toLowerCase().indexOf(needle) >= 0',
        "Search title, place or notes",
        "fAttendees",
        "win.isNowHour(",
        "function onOffsetChanged() { win.ensureRange(); }",
        "function onViewChanged() { win.ensureRange(); }",
        "visible: win.readOnlyEvent",
        "function ruleFromForm() {",
    ):
        assert snippet in PANEL, snippet
    for snippet in ("description:", "rrule:", "alarm:", "timezone:", "attendees"):
        assert snippet in SERVICE, snippet
