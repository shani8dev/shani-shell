"""Static guards for the OSD / display-confirm fixes.

Each change is source-only (no live compositor or screens here): the adaptive
brightness pill must not print its percentage twice, a screenshot countdown
must not cut an unrelated OSD, the scale notice is keyed by output, and the
display-confirmation modal is answerable by keyboard on the screen in use and
named for assistive tech.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OSD = ROOT / "shani" / "Modules" / "Osd" / "Osd.qml"
CONFIRM = ROOT / "shani" / "Modules" / "DisplayConfirm" / "DisplayConfirm.qml"


def _handler(text, name):
    """The body of one `function name(...)` up to its closing brace."""
    start = text.index("function " + name + "(")
    depth = 0
    for i in range(text.index("{", start), len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    raise AssertionError(name + " has no closing brace")


def test_adaptive_osd_does_not_print_the_percentage_twice():
    t = OSD.read_text(encoding="utf-8")
    # the adaptive notice hands a "NN%" label to a slider...
    assert 'Math.round(AmbientLight.targetBrightness * 100) + "%"' in _handler(
        t, "onTargetBrightnessChanged"
    )
    # ...so the pill's own percentage text must stand down for a % label
    pct = t[
        t.index('text: Math.round(root.value * 100) + "%"') - 220 : t.index(
            'text: Math.round(root.value * 100) + "%"'
        )
    ]
    assert '!root.label.endsWith("%")' in pct


def test_screenshot_countdown_does_not_hide_an_unrelated_osd():
    t = OSD.read_text(encoding="utf-8")
    body = _handler(t, "onCountdownChanged")
    assert 'else if (root.icon === "applets-screenshooter")' in body
    assert "else\n                root.shown = false" not in body


def test_scale_osd_is_keyed_by_the_output():
    t = OSD.read_text(encoding="utf-8")
    body = _handler(t, "onOutputsChanged")
    assert 'property string lastScaleOutput: ""' in t
    assert "const same = root.lastScaleOutput === Niri.focusedOutput" in body
    assert "if (same && root.lastScale >= 0" in body
    assert "root.lastScaleOutput = Niri.focusedOutput" in body


def test_display_confirm_focuses_the_screen_in_use():
    t = CONFIRM.read_text(encoding="utf-8")
    assert "Quickshell.screens.find(s => s.name === Niri.focusedOutput)" in t
    assert (
        "keyScreen && !Lock.locked ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None"
        in t
    )
    assert "onVisibleChanged: if (visible && win.keyScreen) forceActiveFocus()" in t
    assert "Keys.onEscapePressed: Displays.revert()" in t
    assert "Keys.onReturnPressed: Displays.keep()" in t


def test_display_confirm_is_named_for_assistive_tech():
    t = CONFIRM.read_text(encoding="utf-8")
    assert "Accessible.role: Accessible.Dialog" in t
    assert 'Accessible.name: Tr.t("Keep these display settings?")' in t
    assert "Accessible.name: text" in t  # the countdown, with its live seconds
