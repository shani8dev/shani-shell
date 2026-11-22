"""Calendar invitations: METHOD:REQUEST, attendees and mail fallback."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
src = (ROOT / "bridge/agenda.py").read_text()
qml = (ROOT / "shani/Services/Agenda.qml").read_text()
panel = (ROOT / "shani/Modules/Calendar/CalendarPanel.qml").read_text()


def test_ical_has_invite_fields():
    assert "METHOD:REQUEST" in src
    assert "ORGANIZER" in src
    assert "ATTENDEE;CN=" in src
    assert "RSVP=TRUE" in src
    assert "SEQUENCE:" in src


def test_send_with_mail_fallback():
    assert "send_objects_sync" in src
    assert "xdg-email" in src
    assert "mailDraft" in src


def test_ui_and_whitelist():
    assert "attendees" in qml
    assert "fAttendees" in panel
    assert "Invite by email" in panel
