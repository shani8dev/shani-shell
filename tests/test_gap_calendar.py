"""Calendar gaps: description/repeat/alarm/timezone in the bridge and UI."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))
import agenda  # noqa: E402

PANEL = (ROOT / "shani/Modules/Calendar/CalendarPanel.qml").read_text()
SERVICE = (ROOT / "shani/Services/Agenda.qml").read_text()

EVENT = "\r\n".join(
    [
        "BEGIN:VEVENT",
        "UID:abc123",
        "DTSTART;VALUE=DATE-TIME:20260105T090000",
        "DTEND;VALUE=DATE-TIME:20260105T100000",
        "SUMMARY:Standup",
        "DESCRIPTION:Original notes",
        "RRULE:FREQ=DAILY",
        "BEGIN:VALARM",
        "TRIGGER:-PT10M",
        "ACTION:DISPLAY",
        "DESCRIPTION:old",
        "END:VALARM",
        "ATTENDEE;CN=Bob:mailto:bob@example.com",
        "END:VEVENT",
        "",
    ]
)
PAYLOAD = {"start": 1767600000, "end": 1767603600, "summary": "Standup", "location": ""}


def test_bridge_reads_description_rrule_alarm_and_zone():
    # the readback helper parses raw iCalendar text, so it needs no EDS bindings
    import types

    original_bindings = agenda.bindings

    def fake_bindings():
        lib = types.SimpleNamespace(component_as_ical_string=lambda comp: EVENT)
        return (None, None, lib)

    agenda.bindings = fake_bindings
    try:
        got = agenda._event_extras(object())
    finally:
        agenda.bindings = original_bindings
    assert got["description"] == "Original notes"
    assert got["rrule"] == "FREQ=DAILY"
    assert got["alarm"] == 10


def test_new_event_writes_description_rrule_alarm_and_timezone():
    text = agenda._ical_text(
        {
            **PAYLOAD,
            "description": "Agenda notes",
            "rrule": "FREQ=WEEKLY;BYDAY=MO",
            "alarm": 15,
            "timezone": "Europe/London",
        }
    )
    assert "DESCRIPTION:Agenda notes" in text
    assert "RRULE:FREQ=WEEKLY;BYDAY=MO" in text
    assert "TRIGGER:-PT15M" in text
    assert "TZID=Europe/London" in text


def test_edit_updates_extras_but_keeps_attendees():
    out = agenda._replace_event_fields(
        EVENT,
        {
            **PAYLOAD,
            "description": "Updated notes",
            "rrule": "FREQ=WEEKLY",
            "alarm": 30,
        },
    )
    assert "DESCRIPTION:Updated notes" in out
    assert "RRULE:FREQ=WEEKLY" in out
    assert "TRIGGER:-PT30M" in out
    assert "ATTENDEE;CN=Bob:mailto:bob@example.com" in out
    assert "DESCRIPTION:Original notes" not in out
    assert "TRIGGER:-PT10M" not in out


def test_bad_rrule_and_timezone_are_rejected():
    text = agenda._ical_text(
        {
            **PAYLOAD,
            "rrule": "FREQ=DAILY;X=bad value with spaces",
            "timezone": "../etc/passwd",
        }
    )
    assert "RRULE" not in text
    assert "TZID" not in text


def test_ui_has_detail_popover_repeat_alarm_zone_and_readonly_banner():
    assert "function viewEvent(e)" in PANEL
    assert "visible: win.readOnlyEvent" in PANEL
    assert "function ruleFromForm()" in PANEL
    assert "fDescription" in PANEL
    assert "Reminder (minutes before)" in PANEL
    assert "model: win.zones" in PANEL
    assert "win.isNowHour(" in PANEL  # current-time indicator


def test_service_passes_description_and_repeat_down():
    for key in ("description", "rrule", "alarm", "timezone"):
        assert key + ":" in SERVICE
