"""Turn filtering: the panel must render only turns this bridge started.

`dev.shani.chronoa.Agent` is bus-wide, so a turn begun anywhere shows up on
every client's `Event` signal. These tests pin the two dangerous directions:
a foreign turn leaking into the panel, and one of our own events being eaten
because it arrived before `Turn`'s reply.
"""

import turn_filter
from turn_filter import TurnFilter


def ev(turn, event="tool", **kw):
    return {"turn": turn, "event": event, **kw}


def test_our_turn_is_forwarded():
    f = TurnFilter()
    f.take("turn-a")
    assert f.see(ev("turn-a")) is True


def test_foreign_turn_is_held_not_forwarded():
    f = TurnFilter()
    f.take("turn-a")
    assert f.see(ev("turn-b")) is False
    assert f.see(ev("turn-b", "reply", text="hi")) is False
    assert f.held() == 2


def test_events_that_beat_the_turn_reply_are_flushed_in_order():
    f = TurnFilter()
    first = ev("turn-a", "tool", text="scan")
    second = ev("turn-a", "reply", text="done")
    assert f.see(first) is False
    assert f.see(second) is False

    flushed = f.take("turn-a")
    assert flushed == [first, second]
    assert f.held() == 0


def test_after_a_flush_the_turn_is_known():
    f = TurnFilter()
    f.see(ev("turn-a"))
    f.take("turn-a")
    assert f.held() == 0
    assert f.see(ev("turn-a", "done")) is True
    assert f.held() == 0


def test_taking_an_unknown_turn_claims_it_and_returns_nothing():
    f = TurnFilter()
    assert f.take("turn-a") == []
    assert f.see(ev("turn-a")) is True


def test_take_only_drains_the_turn_it_names():
    f = TurnFilter()
    f.see(ev("turn-a"))
    f.see(ev("turn-b"))
    assert f.take("turn-a") == [ev("turn-a")]
    assert f.held() == 1


def test_events_without_a_turn_are_forwarded():
    # Turn-less notices (state, cue, errors) are for the whole bus.
    f = TurnFilter()
    assert f.see({"event": "notice", "text": "hi"}) is True
    assert f.see({"turn": "", "event": "notice"}) is True
    assert f.held() == 0


def test_held_turns_are_bounded_and_oldest_dropped():
    f = TurnFilter()
    f.take("turn-own")
    for i in range(TurnFilter.MAX_UNCLAIMED + 3):
        f.see(ev(f"turn-foreign-{i}"))

    assert len(f._held) == TurnFilter.MAX_UNCLAIMED
    # The oldest foreign turn was evicted: asking for it now yields nothing.
    assert f.take("turn-foreign-0") == []
    newest = f"turn-foreign-{TurnFilter.MAX_UNCLAIMED + 2}"
    assert f.take(newest) == [ev(newest)]


def test_one_foreign_turn_cannot_grow_without_limit():
    f = TurnFilter()
    for i in range(TurnFilter.MAX_HELD + 20):
        f.see(ev("turn-foreign", "reply", text=str(i)))

    flushed = f.take("turn-foreign")
    assert len(flushed) == TurnFilter.MAX_HELD
    assert flushed[-1]["text"] == str(TurnFilter.MAX_HELD - 1)


def test_known_turns_are_bounded_and_old_ids_become_foreign():
    f = TurnFilter()
    for i in range(TurnFilter.MAX_KNOWN + 1):
        f.take(f"turn-{i}")

    assert f.known() == TurnFilter.MAX_KNOWN
    assert f.see(ev("turn-0")) is False
    assert f.see(ev(f"turn-{TurnFilter.MAX_KNOWN}")) is True


def test_claiming_again_keeps_the_id_recent():
    f = TurnFilter()
    f.take("turn-a")
    for i in range(TurnFilter.MAX_KNOWN - 1):
        f.take(f"turn-{i}")
    assert f.known() == TurnFilter.MAX_KNOWN

    # turn-a is the oldest id now; claiming it again must make it the newest,
    # or the next MAX_KNOWN-1 turns would evict a turn that is still running.
    f.take("turn-a")
    for i in range(TurnFilter.MAX_KNOWN - 1):
        f.take(f"turn-late-{i}")
    assert f.see(ev("turn-a")) is True


def test_caps_are_sane():
    assert 1 <= TurnFilter.MAX_KNOWN <= 1024
    assert 1 <= TurnFilter.MAX_UNCLAIMED < TurnFilter.MAX_KNOWN
    assert 1 <= TurnFilter.MAX_HELD <= 4096
    assert turn_filter.TurnFilter is TurnFilter
