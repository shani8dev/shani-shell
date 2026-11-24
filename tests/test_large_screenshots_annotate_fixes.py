"""Static checks for the Screenshots + Annotate capture-and-markup upgrade.

QML cannot run under pytest here, so each test pins the source binding that
carries one fix: capture modes and delay, post-capture actions with
confirmation, pin move/resize/opacity/zoom, and the annotation tool palette
(rect/ellipse/arrow/text/highlight), stroke width, undo/redo, shortcuts and
accessibility names. The competitor baseline is macOS Screenshot (Preview
markup), GNOME Screenshot and Windows Snipping Tool.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHOT = "shani/Services/Screenshots.qml"
PIN = "shani/Modules/Screenshots/PinCapture.qml"
ANN = "shani/Modules/Annotate/Annotate.qml"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def function_body(text, name):
    """The {...} body of `function name(...)` in a QML file."""
    start = text.index("function " + name + "(")
    brace = text.index("{", start)
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1 : i]
    raise AssertionError("unbalanced braces in " + name)


def test_capture_modes_select_the_right_niri_action():
    q = read(SHOT)
    assert "property string captureMode" in q
    assert "captureModes" in q
    for mode in ('"screen"', '"window"', '"region"'):
        assert mode in q
    start = function_body(q, "startCapture")
    assert "later(captureDelay)" in start and "shoot.restart()" in start
    shoot = q.split("id: shoot", 1)[1]
    for action in ("screenshot-window", '"screenshot"', "screenshot-screen"):
        assert action in shoot, action + " is never reached by a capture mode"


def test_capture_delay_is_validated_and_shows_countdown():
    q = read(SHOT)
    assert "captureDelays: [0, 3, 5, 10]" in q
    body = function_body(q, "setCaptureDelay")
    assert "indexOf" in body and "captureDelay = n" in body
    assert 'captureState = "countdown"' in q
    assert 'captureState = "capturing"' in q


def test_copy_share_save_actions_confirm_and_handle_empty_history():
    q = read(SHOT)
    for fn in ("copyImage", "shareImage", "saveImage"):
        body = function_body(q, fn)
        assert "if (!p)" in body, fn + " has no empty-state guard"
        assert "notifySend" in body, fn + " gives no confirmation"
    assert "wl-copy" in function_body(q, "copyImage")
    assert "Share.open" in function_body(q, "shareImage")
    assert 'cp "$1" "$3"' in function_body(q, "saveImage")
    assert '"copy=Copy image"' in function_body(q, "offer")
    assert 'a === "copy"' in q


def test_screenshot_empty_state_guards_are_explicit():
    q = read(SHOT)
    assert "readonly property bool hasCapture" in q
    assert "No screenshot to annotate" in q
    assert "No screenshot to pin" in q


def test_pin_can_be_moved_and_resized():
    q = read(PIN)
    assert "Qt.SizeAllCursor" in q and "win.x +=" in q and "win.y +=" in q
    assert "Qt.SizeFDiagCursor" in q
    assert "win.width =" in q and "win.height =" in q
    assert "Math.max(win.minW" in q and "Math.max(win.minH" in q


def test_pin_opacity_and_zoom_are_controllable():
    q = read(PIN)
    assert "cyclePinOpacity" in q
    assert "opacity: Screenshots.pinOpacity" in q
    assert "onWheel" in q and "Screenshots.pinZoom" in q
    assert "resetPinZoom" in q


def test_pin_has_copy_share_save_actions_and_accessible_names():
    q = read(PIN)
    for call in (
        "Screenshots.copyImage",
        "Screenshots.shareImage",
        "Screenshots.saveImage",
    ):
        assert call in q, call + " is not wired to a pin button"
    assert q.count("accessibleName:") >= 5, "pin buttons need AT-SPI names"


def test_annotate_tool_palette_draws_every_shape():
    q = read(ANN)
    body = function_body(q, "setTool")
    assert "tools.indexOf" in body and "tool = t" in body
    for kind in ('"pen"', '"rect"', '"ellipse"', '"arrow"', '"text"', '"highlight"'):
        assert kind in q, kind + " is not a selectable tool"
    for paint in (
        "g.strokeRect",
        "g.ellipse",
        "g.fillText",
        'k === "arrow"',
        'k === "highlight"',
    ):
        assert paint in q, paint + " is not rendered on the canvas"


def test_annotate_stroke_width_is_selectable():
    q = read(ANN)
    assert "widths: [2, 5, 12]" in q
    assert "property int widthStep" in q
    assert "strokeWidth: widths[widthStep]" in q
    assert "Qt.Key_BracketLeft" in q and "Qt.Key_BracketRight" in q
    assert "widthStep = (win.widthStep + 1) % win.widths.length" in q


def test_annotate_undo_and_redo_keep_both_stacks():
    q = read(ANN)
    assert "property var redoStack" in q
    assert "redoStack = redoStack.concat" in function_body(q, "undo")
    assert "strokes.concat([redoStack" in function_body(q, "redo")
    assert '"redoStack = []"' not in q
    assert 'icon: "edit-redo"' in q


def test_annotate_keyboard_shortcuts_cover_tools_and_history():
    q = read(ANN)
    for key in (
        "Qt.Key_P",
        "Qt.Key_R",
        "Qt.Key_O",
        "Qt.Key_A",
        "Qt.Key_T",
        "Qt.Key_H",
        "Qt.Key_Y",
        "Qt.Key_Z",
        "Qt.Key_BracketLeft",
        "Qt.Key_BracketRight",
    ):
        assert key in q, key + " has no handler"


def test_annotate_accessibility_names_and_empty_hint():
    q = read(ANN)
    assert "Accessible.role: Accessible.Dialog" in q
    assert "Screen annotation toolbar" in q
    assert "1-5 colour" in q
    assert "Drag to draw" in q, "no hint when there are no marks yet"
    # the tool palette is a Repeater: 6 source names cover all 11 buttons at runtime
    assert q.count("accessibleName:") >= 6, "toolbar buttons need AT-SPI names"


def test_annotate_text_tool_commits_on_accept():
    q = read(ANN)
    assert "textBox.visible = true" in function_body(q, "beginText")
    assert "strokes.concat([textStroke" in function_body(q, "finishText")
    assert "onAccepted: win.finishText()" in q
    # a text mark has only one point; the shape minimum-points guard must exempt it
    assert 'if (k !== "text" && s.pts.length < 4) continue;' in q
