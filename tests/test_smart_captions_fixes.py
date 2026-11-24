"""Static guards for the SmartReplies / Captions fixes in this pass.

These singletons need a running shell to exercise, so each test asserts the
source carries the exact wiring: a failed bridge send is retried, the message
sent to the model is bounded, malformed/duplicate replies are dropped, stale
or blank caption lines are ignored, and a capture failure is shown in the bar.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SMART = (ROOT / "shani/Services/SmartReplies.qml").read_text(encoding="utf-8")
CAPTIONS = (ROOT / "shani/Services/Captions.qml").read_text(encoding="utf-8")
BAR = (ROOT / "shani/Modules/Captions/CaptionBar.qml").read_text(encoding="utf-8")


def _object(src, anchor):
    """The brace-balanced block starting at `anchor` (nested blocks included)."""
    pos = src.index(anchor)
    start = src.index("{", pos)
    depth = 0
    for j in range(start, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[pos : j + 1]
    raise AssertionError(f"unbalanced block at {anchor}")


def test_suggest_marks_asked_only_after_a_successful_send():
    # fix 1: an empty message or a down bridge must not burn the notification's
    # one chance — the asked flag is written only after Bridge.send succeeds.
    suggest = _object(SMART, "function suggest(n)")
    assert "if (!message)" in suggest
    assert "const sent = Bridge.send({" in suggest
    assert "if (!sent)" in suggest and "return;" in suggest
    assert suggest.index("if (!message)") < suggest.index("const sent = Bridge.send")
    assert suggest.index("if (!sent)") < suggest.index("asked = a;")
    assert suggest.index("a[n.id] = true;") > suggest.index("if (!sent)")


def test_suggest_caps_the_message_sent_to_the_model():
    # fix 2: data minimisation — only the start of a long notification body is
    # shipped to the model for three short replies.
    suggest = _object(SMART, "function suggest(n)")
    assert "message.slice(0, 600)" in suggest
    assert "+ message\n" not in suggest  # no uncapped send


def test_written_handler_validates_id_and_dedupes():
    # fix 3: "rubbish" must not create suggestions[NaN], and a repeated model
    # line must not become a duplicate chip.
    handler = _object(SMART, "function onMessage(msg)")
    assert "Number.isInteger(id)" in handler and "id < 0" in handler
    assert 'String(msg.id || "").charAt(0)' in handler
    assert "raw.indexOf(l) === i" in handler
    assert "root.clean" in handler and "l.length <= 80" in handler


def test_caption_onread_drops_stale_and_blank_lines():
    # fix 4: a subshell killed on source switch/off can still print; whitespace
    # captions must not suppress the "Listening…" placeholder either.
    onread = _object(CAPTIONS, "onRead: line =>")
    assert "if (!root.on) return;" in onread
    assert "if (t) root.lines = root.lines.concat([t]).slice(-3)" in onread
    assert "root.lines.concat([line.trim()])" not in CAPTIONS
    assert "stderr: SplitParser" in CAPTIONS


def test_caption_error_is_exposed_and_shown_in_the_bar():
    # fix 5: capture / transcript-write failures have a state and a surface,
    # instead of "Listening…" forever.
    assert 'property string error: ""' in CAPTIONS
    start = _object(CAPTIONS, "function start(from)")
    assert 'error = "";' in start
    handler = (
        _object(CAPTIONS, "onRead: line => { const t")
        if "onRead: line => { const t" in CAPTIONS
        else ""
    )
    assert "root.error = t" in handler
    label = [l for l in BAR.splitlines() if 'Captions.source === "mic"' in l][0]
    assert "Captions.error && !Captions.text" in label
    assert "Captions.error :" in label
    assert "Captions.error && !Captions.text) ? Theme.red : Theme.dim" in BAR
