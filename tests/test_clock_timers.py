"""Clock-driven services wake on the minute boundary, not on a fixed poll.

Automations' time rules and Focus schedules are minute-granular ("HH:MM"),
so both wake once per minute aligned to the boundary (re-arming themselves)
instead of every 15 s / 30 s. Printing's lpstat poll is the one deliberate
exception, documented in Printing.qml itself.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_automations_clock_is_minute_aligned():
    t = read("shani/Services/Automations.qml")
    assert "interval: 15000" not in t
    assert "msToNextMinute" in t and "clock.restart()" in t
    assert 'Qt.formatTime(new Date(), "HH:mm")' in t


def test_focus_clock_is_minute_aligned():
    t = read("shani/Services/Focus.qml")
    assert "interval: 30000" not in t
    assert "msToNextMinute" in t and "clock.restart()" in t


def test_printing_poll_is_documented_as_the_exception():
    t = read("shani/Services/Printing.qml")
    assert "the one that stays by design" in t
    assert "ipp" in t.lower() or "IPP" in t
