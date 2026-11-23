"""Static regressions for Calls/Messages gaps not covered by test_calls_fixes.py.

QML cannot run under pytest here, so each test pins the binding that would
silently rot: a thread that never scrolls, a failed send that loses its text,
a stale header, a recents tap that leaves the pad unfocused, and a Delete key
that always eats the last digit.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def block(text, marker, end):
    return text.split(marker, 1)[1].split(end, 1)[0]


def test_thread_scrolls_to_the_newest_message():
    """Opening a thread or receiving a message shows the end, not the top."""
    msg = source("shani/Modules/Messages/MessagesWindow.qml")

    assert (
        "onCountChanged: if (count > 0) Qt.callLater(() => thread.positionViewAtEnd())"
        in msg
    )
    conn = block(msg, "function onOpenThreadChanged()", "function onNoteChanged()")
    assert "Qt.callLater(() => thread.positionViewAtEnd())" in conn


def test_header_does_not_keep_a_closed_conversations_name():
    """openDevice() leaves threadName set; the header must key off openThread."""
    msg = source("shani/Modules/Messages/MessagesWindow.qml")
    assert (
        'text: Link.openThread !== "" && Link.threadName !== "" ? Link.threadName : Tr.t("Messages")'
        in msg
    )


def test_failed_send_keeps_its_text_for_retry():
    """The bridge clears the draft on success; on error we put the text back."""
    msg = source("shani/Modules/Messages/MessagesWindow.qml")

    assert "property string retryText" in msg
    send = block(msg, "function send()", "\n}")
    assert "retryText = t;" in send
    assert "Link.send(t);" in send and "Link.clearDraft();" in send

    note = block(msg, "function onNoteChanged()", "\n    }")
    assert "reply.text = win.retryText" in note
    assert 'Link.note !== Tr.t("Text sent")' in note
    opened = block(msg, "function onOpenThreadChanged()", "function onNoteChanged()")
    assert 'Link.openThread === "") win.retryText = ""' in opened


def test_recents_tap_focuses_and_cares_for_the_number_field():
    """A tapped call fills the pad; Enter should call without an extra Tab."""
    calls = source("shani/Modules/Calls/CallsWindow.qml")
    recents = block(
        calls, "ListView {", "Text {\n                anchors.centerIn: parent"
    )
    row = block(recents, "onClicked: { number.text = modelData.number;", "\n")
    assert "number.forceActiveFocus()" in row
    assert "number.cursorPosition = number.text.length" in row


def test_delete_respects_selection_and_caret():
    """Delete removes a selection or the digit before the cursor, not the last."""
    calls = source("shani/Modules/Calls/CallsWindow.qml")
    assert "onClicked: win.deleteDigit()" in calls
    fn = block(calls, "function deleteDigit()", "\n    }")
    assert "number.selectionStart !== number.selectionEnd" in fn
    assert (
        "number.remove(number.selectionStart, number.selectionEnd - number.selectionStart)"
        in fn
    )
    assert "number.remove(number.cursorPosition - 1, 1)" in fn
