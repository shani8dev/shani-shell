"""Pass-18 calendar grid fixes: range loading, overflow chip, calendar colours."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))
import agenda  # noqa: E402

PANEL = (ROOT / "shani/Modules/Calendar/CalendarPanel.qml").read_text()
SERVICE = (ROOT / "shani/Services/Agenda.qml").read_text()


def test_bridge_accepts_a_range_and_keeps_the_legacy_days_form():
    assert agenda.range_window(["agenda.py", "range", "1000", "2600"]) == (
        1000.0,
        2600.0,
    )
    start, end = agenda.range_window(["agenda.py"])
    assert round(end - start) == 7 * 86400
    start, end = agenda.range_window(["agenda.py", "14"])
    assert round(end - start) == 14 * 86400
    try:
        agenda.range_window(["agenda.py", "range", "9", "1"])
    except ValueError:
        pass
    else:
        raise AssertionError("end before start must be rejected")
    calls = []
    original = agenda.events
    agenda.events = lambda a, b: calls.append((a, b)) or []
    try:
        assert agenda.main(["agenda.py", "range", "10", "20"]) == 0
    finally:
        agenda.events = original
    assert calls == [(10.0, 20.0)]


def test_service_and_panel_load_the_window_on_screen():
    assert "function loadRange(from, to)" in SERVICE
    assert '"range", String(s), String(e)' in SERVICE
    assert "root.allEvents = merged" in SERVICE  # date-keyed merge, not a replace
    assert "root.loadedDays = days" in SERVICE
    assert "function ensureRange()" in PANEL
    assert "Agenda.loadRange(from, to)" in PANEL
    assert "function onOffsetChanged() { win.ensureRange(); }" in PANEL
    assert "function onSelectedDateChanged() { win.ensureRange(); }" in PANEL
    assert "function onViewChanged() { win.ensureRange(); }" in PANEL


def test_overflow_chip_reveals_events_hidden_by_the_two_row_cap():
    assert "model: hourCell._evs.slice(0, 2)" in PANEL
    assert 'Tr.t("+%1 more").arg(hourCell._evs.length - 2)' in PANEL
    assert "win.openDayFromWeek(hourCell.index)" in PANEL
    assert 'Ui.calendarView = "day"' in PANEL


def test_calendar_colour_reaches_every_event_delegate():
    assert "function eventColor(cal)" in PANEL
    assert "Agenda.colorOf(cal)" in PANEL
    assert (
        PANEL.count(
            "readonly property color calColor: win.eventColor(modelData.calendar)"
        )
        == 3
    )
    assert PANEL.count("color: Theme.alpha(calColor, 0.45)") == 3
    assert PANEL.count("color: parent.calColor") == 3
