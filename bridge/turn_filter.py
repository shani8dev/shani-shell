"""Which Agent events belong in this shell's panel.

`dev.shani.chronoa.Agent` is a bus-wide service: any client can call `Turn`,
and every client on the bus sees every `Event`. The panel can only show one
turn at a time, so it must show only the turns this bridge started — otherwise
a turn begun in another window (or by a test) appears in the shell.

Two wrinkles make that more than a set membership test:

* `Turn` answers with the id *after* the turn is scheduled, and events are
  queued onto the GLib loop as they happen. The first `tool` event can
  therefore reach the bridge before the id it belongs to does. Those events
  are held, not dropped, and flushed when `Turn` returns.
* A held turn that never gets claimed (a foreign turn) must not grow without
  limit: only the most recent few unclaimed turns are held, each up to a cap.

`see()` answers "forward this now?", `take()` returns what was held for a turn
the moment it is claimed.
"""

from __future__ import annotations

import threading
from collections import OrderedDict


class TurnFilter:
    #: How many of our own turn ids to remember. Events for an older id are
    #: treated as foreign; a turn does not outlive a few dozen turns anyway.
    MAX_KNOWN = 64
    #: How many unclaimed turns to hold events for.
    MAX_UNCLAIMED = 8
    #: How many events to hold per unclaimed turn.
    MAX_HELD = 64

    def __init__(self) -> None:
        # Events arrive on the GLib loop; Turn/Approve answers arrive on client
        # threads. Both touch the same two tables.
        self._lock = threading.RLock()
        self._known: OrderedDict[str, None] = OrderedDict()
        self._held: OrderedDict[str, list[dict]] = OrderedDict()

    # -- our own turns --------------------------------------------------
    def claim(self, turn_id: str) -> None:
        """Remember a turn id returned by `Turn`."""
        with self._lock:
            self._known[turn_id] = None
            self._known.move_to_end(turn_id)
            while len(self._known) > self.MAX_KNOWN:
                self._known.popitem(last=False)

    def take(self, turn_id: str) -> list[dict]:
        """Claim `turn_id` and return the events held for it, oldest first."""
        with self._lock:
            self.claim(turn_id)
            # A copy: the caller iterates this while more events may arrive.
            return list(self._held.pop(turn_id, []))

    # -- every event ----------------------------------------------------
    def see(self, event: dict) -> bool:
        """True if `event` belongs to a turn we started (forward it now)."""
        turn = event.get("turn")
        if not turn:
            # Notices and other turn-less events are for whoever is listening.
            return True
        with self._lock:
            if turn in self._known:
                return True
            self._hold(turn, event)
            return False

    def _hold(self, turn: str, event: dict) -> None:
        held = self._held.setdefault(turn, [])
        if len(held) < self.MAX_HELD:
            held.append(event)
        self._held.move_to_end(turn)
        while len(self._held) > self.MAX_UNCLAIMED:
            self._held.popitem(last=False)

    # -- introspection, used by the tests -------------------------------
    def known(self) -> int:
        with self._lock:
            return len(self._known)

    def held(self) -> int:
        with self._lock:
            return sum(len(v) for v in self._held.values())
