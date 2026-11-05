"""One persistent connection to niri: the EventStream socket.

Queries are answered from the single long-lived EventStream (never a process
per query); `niri msg action` processes exist only on the action path, which
runs solely when asked. See the measurement note in Niri.qml.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NIRI = (ROOT / "shani" / "Services" / "Niri.qml").read_text()


def test_exactly_one_event_stream_socket():
    assert NIRI.count("Socket {") == 1
    assert '"EventStream"' in NIRI


def test_queries_come_from_the_stream_not_from_processes():
    # no `niri msg` query processes (Workspaces/Windows requests): the only
    # processes are `msg action` on the action path
    procs = re.findall(r'"niri", "msg", "(\w+)"', NIRI)
    assert procs and set(procs) == {"action"}


def test_no_query_polling_timer_for_windows():
    timers = re.findall(r"Timer \{[^}]*interval: (\d+)", NIRI)
    # pendingReset (minimise naming) + the EventStream reconnect: neither
    # asks niri for anything
    assert set(timers) == {"1500"}
