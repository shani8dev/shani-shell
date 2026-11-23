"""Static guards for the pass-22 app-lifecycle fixes.

Fix 1: force-closing a shell app must never SIGKILL the shared org.quickshell
process (that would kill the whole desktop); it closes the owning window via
Ui instead. Fix 2: the AppWindow minimise button must minimise its own window,
not Niri.focusedWindow. Runtime behaviour is not exercised here.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NIRI = (ROOT / "shani/Services/Niri.qml").read_text(encoding="utf-8")
APPWINDOW = (ROOT / "shani/Common/AppWindow.qml").read_text(encoding="utf-8")
UI = (ROOT / "shani/Common/Ui.qml").read_text(encoding="utf-8")


def _func(src, anchor):
    """The function starting at `anchor`, up to its closing brace line."""
    body = src[src.index(anchor) :]
    return body[: body.index("\n    }")]


def test_force_close_never_sigkills_a_shell_window():
    fn = _func(NIRI, "function forceCloseFocused()")
    # shell windows are detected (own() sets `shell` and rewrites org.quickshell)
    assert "w.shell === true" in fn
    assert "org.quickshell" in fn
    # the owning window is closed through Ui, not by killing its pid
    assert "Ui.closeAppWindow(id)" in fn
    assert "function closeAppWindow(id)" in UI
    # SIGKILL must sit in the external-app branch, i.e. after the shell check
    assert fn.index('"/bin/kill"') > fn.index("w.shell === true")


def test_minimise_button_targets_its_own_window():
    line = APPWINDOW[APPWINDOW.index('icon: "window-minimize"') :]
    line = line[: line.index("\n")]
    # passes this window's id through Ui.minimise(id), not the focused window
    assert "Ui.minimise(win.desktopId)" in line
    assert "Ui.minimiseFocused" not in line
    assert "function minimise(id)" in UI
    # the registered per-window action resolves and minimises this window
    assert "Ui.registerAppWindow(win.desktopId" in APPWINDOW
    assert "Niri.minimiseWindowByTitle(win.title)" in APPWINDOW
