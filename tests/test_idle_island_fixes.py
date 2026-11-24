"""Static checks for the Idle dim and Island focus/stale-state gap fixes.

One test per bug: a dim fade that ignores reduce-motion, an approval card whose
buttons cannot take the keyboard, ask text that survives a dismissal, approval
text a screen reader cannot read, and a permission answered against a card that
has already gone away.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIM = "shani/Modules/Idle/Dim.qml"
ISLAND = "shani/Modules/Island/Island.qml"


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def block(text, needle):
    """The brace-counted {...} that follows the first occurrence of `needle`."""
    start = text.index(needle)
    i = text.index("{", start)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i : j + 1]
    raise AssertionError(f"unterminated block after {needle!r}")


def test_dim_fade_respects_reduce_motion():
    dim = source(DIM)
    fade = block(dim, "Behavior on opacity")
    assert "NumberAnimation" in fade
    assert "Theme.mot(1200)" in fade
    # Behavior.enabled disables the animation so the opacity snaps instead of
    # fading when the accessibility setting is on
    assert "enabled: !Settings.data.reduceMotion" in fade, fade


def test_approval_card_takes_keyboard_focus():
    island = source(ISLAND)
    line = next(l for l in island.splitlines() if "WlrLayershell.keyboardFocus:" in l)
    # the grab must cover the permission card, not just the question field,
    # otherwise its buttons are unreachable by Tab / a screen reader
    assert "(asking || hasApproval) && !Osk.remote" in line, line
    assert "WlrKeyboardFocus.Exclusive" in line
    assert "WlrKeyboardFocus.None" in line


def test_every_ask_exit_clears_the_typed_question():
    island = source(ISLAND)
    assert 'function closeAsk() { asking = false; askInput.text = ""; }' in island
    assert "onHasApprovalChanged: if (hasApproval) closeAsk()" in island
    field = block(island, "TextInput {")
    assert "Keys.onEscapePressed: win.closeAsk()" in field
    accepted = block(field, "onAccepted:")
    assert "Chronoa.ask(text.trim())" in accepted
    assert "win.closeAsk()" in accepted  # text cleared after a send too
    mascot = block(island, "MouseArea {")
    clicked = mascot[mascot.index("onClicked:") :]
    assert "if (win.asking) win.closeAsk();" in clicked
    keyfocus = block(island, "KeyFocus {")
    assert "if (win.asking) win.closeAsk();" in keyfocus


def test_approval_question_is_readable_by_assistive_tech():
    island = source(ISLAND)
    for field in ("text", "detail"):
        needle = "text: Chronoa.approval ? Chronoa.approval." + field
        start = island.index(needle)
        text = island[start - 200 : start]
        assert "Accessible.role: Accessible.StaticText" in text
        assert "Accessible.name: text" in text


def test_approval_button_uses_a_captured_request_id():
    island = source(ISLAND)
    # block() finds the Button's {...} after the Repeater's model line
    btn = block(island, "model: Chronoa.approval ? Chronoa.approval.options")
    assert (
        'readonly property string requestId: Chronoa.approval ? Chronoa.approval.id : ""'
        in btn
    ), btn
    clicked = btn[btn.index("onClicked:") :]
    assert "Chronoa.approve(requestId, modelData)" in clicked, clicked
    assert 'if (requestId !== "")' in clicked
    # reading the live card at click time is the stale-state bug itself
    assert "Chronoa.approval.id" not in clicked
