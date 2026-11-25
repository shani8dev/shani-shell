"""Static checks for the one canonical Back flow.

Lock/OSK/Niri/whiteboard need a running shell, so these assert the source
wiring rather than driving QML. One test per audit fix.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def body(src, marker):
    """The {...} body of `marker`, by brace matching."""
    start = src.index(marker)
    open_at = src.index("{", start)
    depth = 0
    for i in range(open_at, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[open_at + 1 : i]
    raise AssertionError("unbalanced body for " + marker)


def test_fix1_ui_back_is_the_canonical_flow():
    s = read("shani/Common/Ui.qml")
    b = body(s, "function back()")
    # the order is the priority: lock, keyboard, shell surface, TV, overview, app
    assert b.index("if (Lock.locked) return;") < b.index("if (Osk.remote)")
    assert b.index("if (Osk.remote) Osk.cancelRemote();") < b.index("Osk.toggle()")
    assert b.index("Osk.toggle()") < b.index("closeAll()")
    assert b.index("closeAll()") < b.index("tvHome")
    assert b.index("tvHome") < b.index('Niri.action("close-overview")')
    assert b.index('Niri.action("close-overview")') < b.index('"wtype"')
    # every shell surface that Back closes
    for surface in (
        "quickPanel",
        "dockMenu",
        "windowMenu",
        "ring",
        "switcher",
        "layoutSwitcher",
        "windowLayouts",
        "launcher",
        "controlCenter",
        "player",
        "magnifier",
        "annotate",
        "settingsOpen",
        "desktopMenu",
        "tour",
    ):
        assert surface in b, surface
    assert 'dockMenu !== ""' in b  # it is a string flag
    assert "Niri.mru().some(w => w.app_id" in b  # only with an app behind
    assert "settingsOpen = false;" in b  # closeAll() does not clear it
    assert "closeApps()" not in b  # never close an app window


def test_fix2_both_back_inputs_delegate_to_ui_back():
    shell = read("shani/shell.qml")
    assert "function remoteBack() { Ui.back(); }" in shell
    edge = read("shani/Services/EdgeSwipe.qml")
    b = body(edge, 'action === "back"')
    assert "Ui.back();" in b
    assert "wtype" not in b and "closeAll()" not in b and "overviewOpen" not in b


def test_fix3_left_back_strip_yields_to_the_left_rail():
    s = read("shani/Modules/EdgeStrips/EdgeStrips.qml")
    assert "Settings.data.leftRail && modelData.name === Niri.focusedOutput" in s
    visible = [ln for ln in s.splitlines() if ln.strip().startswith("visible:")][0]
    assert 'modelData === "left"' in visible and "railOnFocused" in visible
    # the gesture mapping is pinned: gating is a visible condition, not a new action
    gestures = read("shani/Common/Gestures.js")
    assert (
        'var ACTIONS = { bottom: "launcher", top: "quick-settings", left: "back", right: "overview" };'
        in gestures
    )


def test_fix4_close_all_adds_desktop_menu_tour_and_guarded_whiteboard():
    ui = read("shani/Common/Ui.qml")
    b = body(ui, "function closeAll()")
    assert "desktopMenu = false;" in b and "tour = false;" in b
    assert "if (whiteboard) closeWhiteboardRequested();" in b
    assert "whiteboard = false" not in b  # unsaved strokes: never blunt-close
    assert "signal closeWhiteboardRequested()" in ui
    shell = read("shani/shell.qml")
    assert (
        "function onCloseWhiteboardRequested() { if (whiteboardLoader.item) whiteboardLoader.item.requestClose(); }"
        in shell
    )
    board = read("shani/Modules/Whiteboard/Whiteboard.qml")
    assert "function requestClose()" in board  # the guard still saves before closing
