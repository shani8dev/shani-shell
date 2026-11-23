"""Static regressions for the pass-20 Calls fixes.

QML cannot run under pytest here, so these check the bindings that silently rot:
an in-call card nobody bound, a waiting call that overwrote the active one, and
a history list with no way to narrow it. The bridge verb is checked in source
too (importing it needs gi and a live system bus).
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_incall_card_shows_the_call_and_its_controls():
    """Fix 1: the card binds Modem.call/time and wires Mute/Speaker/Hang up."""
    win = source("shani/Modules/Calls/CallsWindow.qml")
    svc = source("shani/Services/Modem.qml")
    bridge = source("bridge/modem.py")

    assert "visible: Modem.call !== null" in win
    assert "text: Modem.callTime" in win
    assert 'Tr.t("Mute")' in win and 'Tr.t("Speaker")' in win
    assert 'Tr.t("Hang up")' in win
    assert "Modem.setMute(!Modem.muted)" in win
    assert "Modem.setSpeaker(!Modem.speaker)" in win
    assert "Modem.hangup()" in win

    assert "function setMute(on)" in svc and "function setSpeaker(on)" in svc
    assert 'callctl("mute", root.muted)' in svc
    assert 'callctl("speaker", root.speaker)' in svc

    # the audio controls have no ModemManager verb, so the bridge echoes them
    assert '"callctl" in msg' in bridge
    assert '("mute", "speaker", "hold", "swap")' in bridge
    assert 'emit({"callctl": {"action": action, "on": on}})' in bridge


def test_waiting_call_keeps_the_active_one_and_has_answer_hold_swap():
    """Fix 2: a 'waiting' call no longer overwrites root.call; it gets a banner."""
    svc = source("shani/Services/Modem.qml")
    win = source("shani/Modules/Calls/CallsWindow.qml")

    assert "property var waitingCall: null" in svc
    waiting_block = svc.split('if (c.state === "waiting")', 1)[1].split(
        'if (c.state === "held")', 1
    )[0]
    assert "root.waitingCall = c" in waiting_block
    assert "return;" in waiting_block  # do not fall through to root.call = c
    assert (
        "if (root.waitingCall && root.waitingCall.path === c.path) root.waitingCall = null"
        in svc
    )
    assert "function answerCall(path)" in svc

    assert "visible: Modem.waitingCall !== null" in win
    assert 'Tr.t("Call waiting")' in win
    for label in ("Answer", "Hold", "Swap"):
        assert f'Tr.t("{label}")' in win
    assert "Modem.answerCall(Modem.waitingCall.path)" in win
    assert 'Modem.callctl("hold")' in win and 'Modem.callctl("swap")' in win


def test_recents_have_search_and_a_missed_only_filter():
    """Fix 3: search and the chip filter the existing Link.calls model."""
    win = source("shani/Modules/Calls/CallsWindow.qml")

    assert "property string callSearch" in win
    assert "property bool missedOnly" in win
    assert 'placeholder: Tr.t("Search calls")' in win
    assert 'Tr.t("Missed only")' in win
    assert "onTextChanged: win.callSearch = text.trim().toLowerCase()" in win

    model = win.split("model: Link.calls.filter(", 1)[1].split("delegate:", 1)[0]
    assert "win.missedOnly" in model and "c.missed" in model
    assert "win.callSearch" in model and "c.name || c.number" in model
