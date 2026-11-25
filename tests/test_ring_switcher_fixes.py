"""Static checks for Ring/Switcher gaps found by reading the two modules
against Niri.qml, Ui.qml and Dock.qml (none of these are in docs/GAPS*.md).

Both are layer-shell windows that need a running shell to drive, so each test
asserts the source carries the exact wiring rather than exercising QML.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def section(src, start, stop):
    """The text between two landmarks, so a change cannot hide elsewhere."""
    return src.split(start, 1)[1].split(stop, 1)[0]


def test_switcher_cancelled_gesture_does_not_commit_on_modifier_release():
    s = read("shani/Modules/Switcher/Switcher.qml")
    released = section(s, "Keys.onReleased:", 'MouseArea { objectName: "nav:pointer"')
    assert "if (Ui.switcher &&" in released
    assert released.index("if (Ui.switcher &&") < released.index("win.commit();")

    # both dismiss paths really clear Ui.switcher, which is what the guard reads
    pressed = section(s, "Keys.onPressed:", "Keys.onReleased:")
    assert "Qt.Key_Escape" in pressed and "Ui.switcher = false" in pressed
    background = section(s, 'MouseArea { objectName: "nav:pointer"', "Glass {")
    assert "Ui.switcher = false" in background


def test_switcher_excludes_minimised_windows_from_the_mru():
    s = read("shani/Modules/Switcher/Switcher.qml")
    opening = section(s, "function open(back) {", "function step(d)")
    assert "list = Niri.mru().filter(w => !Niri.isMinimised(w));" in opening
    assert "\n        list = Niri.mru();" not in opening
    # Niri documents the hidden workspace as hidden from Alt+Tab; the dock agrees
    niri = read("shani/Services/Niri.qml")
    assert "Alt+Tab treat it as hidden" in niri
    # the dock's apps and what a click does are Services/Taskbar's (shared with the bar and the rail)
    taskbar = read("shani/Services/Taskbar.qml")
    assert "it.windows.filter(w => !Niri.isMinimised(w))" in taskbar


def test_switcher_keeps_the_g_toggle_between_opens():
    s = read("shani/Modules/Switcher/Switcher.qml")
    opening = section(s, "function open(back) {", "function step(d)")
    assert "if (win.buildGroups().length <= 1)" in opening
    assert "grouped = false;" in opening
    # the old unconditional reset threw away the person's G choice
    assert "grouped = win.buildGroups().length > 1;" not in opening


def test_ring_dwell_cannot_act_after_the_ring_is_dismissed():
    s = read("shani/Modules/Ring/Ring.qml")
    dwell = section(s, "id: dwell", "// ---- drawing")
    assert "if (!win.visible)" in dwell
    assert dwell.index("if (!win.visible)") < dwell.index("win.choose(win.hot)")
    visible = section(s, "onVisibleChanged:", "Item {")
    assert "dwell.stop()" in visible


def test_ring_depth_is_reset_when_the_ring_closes():
    s = read("shani/Modules/Ring/Ring.qml")
    assert "onStackChanged: Ui.ringDepth = stack.length" in s
    visible = section(s, "onVisibleChanged:", "Item {")
    assert "} else {" in visible
    hide = visible.split("} else {", 1)[1]
    assert "stack = [];" in hide
