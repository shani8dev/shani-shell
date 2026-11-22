"""Editing an event must not drop the iCalendar fields the UI doesn't own."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))
import agenda  # noqa: E402

EVENT = "\r\n".join(
    [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "BEGIN:VEVENT",
        "UID:abc123",
        "DTSTAMP:20260101T000000Z",
        "DTSTART;VALUE=DATE-TIME:20260105T090000",
        "DTEND;VALUE=DATE-TIME:20260105T100000",
        "SUMMARY:Weekly standup",
        "LOCATION:Room 1",
        "DESCRIPTION:Notes for the meeting",
        "RRULE:FREQ=WEEKLY;BYDAY=MO",
        "ATTENDEE;CN=Bob:mailto:bob@example.com",
        "BEGIN:VALARM",
        "TRIGGER:-PT10M",
        "ACTION:DISPLAY",
        "DESCRIPTION:reminder",
        "END:VALARM",
        "END:VEVENT",
        "END:VCALENDAR",
        "",
    ]
)


def test_edit_keeps_rrule_description_attendees_and_alarms():
    out = agenda._replace_event_fields(
        EVENT,
        {
            "start": 1767600000,  # 2026-01-05 09:20 local-ish, only shape matters
            "end": 1767603600,
            "summary": "Daily standup",
            "location": "Room 2",
        },
    )
    for kept in (
        "UID:abc123",
        "DESCRIPTION:Notes for the meeting",
        "RRULE:FREQ=WEEKLY;BYDAY=MO",
        "ATTENDEE;CN=Bob:mailto:bob@example.com",
        "BEGIN:VALARM",
        "TRIGGER:-PT10M",
    ):
        assert kept in out, kept
    assert "SUMMARY:Daily standup" in out
    assert "LOCATION:Room 2" in out
    assert "SUMMARY:Weekly standup" not in out
    assert "LOCATION:Room 1" not in out


def test_edit_can_add_a_location_that_was_not_there():
    minimal = "\r\n".join(["BEGIN:VEVENT", "SUMMARY:Old", "END:VEVENT", ""])
    out = agenda._replace_event_fields(
        minimal,
        {"start": 1000, "end": 2000, "summary": "New", "location": "Hall"},
    )
    assert "LOCATION:Hall" in out
    assert out.index("LOCATION:Hall") < out.index("END:VEVENT")
