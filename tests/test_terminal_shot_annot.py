"""Second-deep-pass checks for Terminal, Screenshots and Annotate.

No QML runtime here: the QML changes are pinned statically, and the close-guard
state machine is exercised as plain Python so the two-step rule is testable.
The Screenshots/Annotate notes record deliberate skips, not missing work.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TERM = ROOT / "shani/Modules/Terminal/TerminalAppWindow.qml"
PIN = ROOT / "shani/Modules/Screenshots/PinCapture.qml"
ANN = ROOT / "shani/Modules/Annotate/Annotate.qml"
I18N = ROOT / "shani/i18n"
CLOSE_MSG = "A connection is open in another window — press Esc again to close"


def read(path):
    return path.read_text(encoding="utf-8")


# ---- Terminal: closing a window with a launched connection ------------------


def test_terminal_close_guard_is_wired():
    s = read(TERM)
    assert "property var openedHosts: []" in s
    assert "property bool confirmingClose: false" in s
    assert (
        "Timer { id: unconfirmClose; interval: 4000; onTriggered: win.confirmingClose = false }"
        in s
    )
    assert "function requestClose()" in s
    assert "Keys.onEscapePressed: win.requestClose()" in s
    assert 'Tr.t("' + CLOSE_MSG + '")' in s
    # every launch path records the host before handing it to the service
    assert (
        s.count("win.noteLaunch(") >= 3
    )  # one per Connect path (plus quick-command launches)
    assert "TerminalApp.connect(h)" in s  # keyboard path unchanged
    assert s.count("TerminalApp.connect(modelData)") >= 2


def test_terminal_note_launch_is_idempotent():
    """Launching the same host twice must not make the warning stick around."""
    guard = CloseGuard()
    guard.note_launch("host-1")
    guard.note_launch("host-1")
    guard.note_launch("host-2")
    assert guard.opened_hosts == ["host-1", "host-2"]


def test_terminal_passive_window_closes_on_first_escape():
    guard = CloseGuard()
    assert guard.request_close() is True
    assert guard.opened_hosts == []


def test_terminal_active_window_needs_a_second_escape():
    guard = CloseGuard()
    guard.note_launch("serial-port")
    assert guard.request_close() is False
    assert guard.confirming is True
    assert guard.request_close() is True
    assert guard.opened_hosts == []


def test_terminal_confirm_disarms_on_timeout_and_on_hide():
    """The 4s timer clears only the armed warning (the connection is still
    tracked, so Esc arms it again); a hide clears the session entirely."""
    guard = CloseGuard()
    guard.note_launch("host-1")
    assert guard.request_close() is False
    guard.expire()
    assert guard.confirming is False
    assert guard.request_close() is False  # still a session: warn again
    assert guard.request_close() is True

    guard = CloseGuard()
    guard.note_launch("host-1")
    assert guard.request_close() is False
    guard.hide()
    assert guard.opened_hosts == []
    assert guard.request_close() is True


class CloseGuard:
    """The QML state machine, mirrored: see requestClose/noteLaunch/onVisibleChanged."""

    def __init__(self):
        self.opened_hosts = []
        self.confirming = False

    def note_launch(self, host):
        if host is not None and host not in self.opened_hosts:
            self.opened_hosts.append(host)

    def request_close(self):
        if self.opened_hosts and not self.confirming:
            self.confirming = True
            return False
        self.confirming = False
        self.opened_hosts = []
        return True

    def expire(self):
        self.confirming = False

    def hide(self):
        self.confirming = False
        self.opened_hosts = []


# ---- Screenshots: active-window capture, deliberately skipped ---------------


def test_screenshot_active_window_path_is_elsewhere_not_in_pin_capture():
    """Niri exposes `screenshot-window` (Ring's Window tile already calls it),
    but PinCapture is only the pinned-image viewer: no capture belongs here.
    Adding a mode would mean editing Services/Screenshots.qml and a UI file
    outside this pass's scope, so it was skipped rather than bolted on."""
    ring = read(ROOT / "shani/Modules/Ring/Ring.qml")
    assert 'Niri.action("screenshot-window")' in ring
    pin = read(PIN)
    assert "screenshot-window" not in pin
    assert "Screenshots.pinnedPath" in pin  # still a viewer of the saved image


# ---- Annotate: a stroke-only tool model, so ellipse/fill were skipped -------


def test_annotate_tool_model_regression():
    """Ellipse/fill would need a shape model: strokes are { c, pts } with a
    boolean straight-line flag, and the canvas only ever calls stroke().
    That is a rewrite, so it was skipped; keep the existing tools intact."""
    s = read(ANN)
    assert "property var strokes: []" in s
    assert "c: win.colours[win.colour]" in s
    assert "g.stroke();" in s
    assert "g.fill()" not in s
    assert (
        len(
            [
                line
                for line in s.splitlines()
                if "required property string modelData" in line
            ]
        )
        == 1
    )
    for token in ('icon: "edit-undo"', 'icon: "draw-eraser"', 'icon: "document-save"'):
        assert token in s
    assert "Qt.Key_1 && e.key <= Qt.Key_5" in s


# ---- i18n: this pass's own strings only -------------------------------------


def test_i18n_new_close_string_is_extracted_and_translated():
    import json

    template = json.loads((I18N / "template.json").read_text(encoding="utf-8"))
    assert CLOSE_MSG in template
    for lang in ("hi", "mr"):
        cat = json.loads((I18N / f"{lang}.json").read_text(encoding="utf-8"))
        assert cat[CLOSE_MSG].strip()
        assert cat[CLOSE_MSG] != CLOSE_MSG
