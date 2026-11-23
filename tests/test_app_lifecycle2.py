"""Static guards for the second set of pass-22 app-lifecycle fixes.

Fix 1: every window close goes through a canClose() guard; for the text editor
that means a Save / Discard / Cancel choice when TextDocs has unsaved buffers.
Fix 2: the title bar no longer closes the window on a middle click.
Fix 3: Reopen flushes its app list on a logind session exit and as a fallback
when the singleton is destroyed, instead of relying only on the 5 s timer.

Fix 4 (a first-open "Opening…" chip) was deliberately skipped. Runtime
behaviour is not exercised here.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPWINDOW = (ROOT / "shani/Common/AppWindow.qml").read_text(encoding="utf-8")
REOPEN = (ROOT / "shani/Services/Reopen.qml").read_text(encoding="utf-8")


def _section(src, start, end):
    """Source from `start` up to (but excluding) `end`."""
    i = src.index(start)
    return src[i : src.index(end, i)]


def test_close_asks_before_discarding_unsaved_text():
    guard = _section(APPWINDOW, "function canClose()", "\n    function requestClose()")
    # the guard is the editor's unsaved buffers, read from TextDocs
    assert 'win.appName === "Text Editor"' in guard
    assert "TextDocs.unsaved > 0" in guard
    assert "closePending = true" in guard and "return false" in guard
    # all three close paths go through the guard, never a bare visible=false
    assert "close: () => { win.requestClose(); }" in APPWINDOW
    assert (
        'tip: Tr.t("Close"); danger: true; onClicked: win.requestClose()' in APPWINDOW
    )
    req = APPWINDOW[APPWINDOW.index("function requestClose()") :]
    assert (
        req[: req.index("\n")]
        == "function requestClose() { if (canClose()) win.visible = false; }"
    )
    # Save / Discard / Cancel choice with Tr.t labels, and Save actually writes
    assert 'Tr.t("Save changes before closing?")' in APPWINDOW
    for label in ("Save", "Discard", "Cancel"):
        assert f'GuardButton {{ label: Tr.t("{label}")' in APPWINDOW
    assert "TextDocs.save()" in APPWINDOW


def test_middle_click_no_longer_closes_the_window():
    header = _section(
        APPWINDOW, "// the empty part of the header", "\n            RowLayout {"
    )
    assert "acceptedButtons: Qt.LeftButton" in header
    assert "Qt.MiddleButton" not in header
    assert "startSystemMove()" in header and "toggleMaximised()" in header


def test_reopen_flushes_on_session_exit_and_on_destruction():
    flush = _section(REOPEN, "function flush()", "\n    onOpenNowChanged")
    assert "root.saved = root.openNow" in flush
    assert "file.setText(JSON.stringify" in flush
    # the calm timer now delegates to the same flush
    assert "onTriggered: root.flush()" in REOPEN
    # the existing Bridge logind path flushes on session exit
    conn = _section(REOPEN, "Connections {", "\n    Component.onDestruction")
    assert "target: Bridge" in conn
    assert 'm.type === "logind"' in conn
    assert 'm.op === "sleep"' in conn
    assert "root.flush()" in conn
    # and a synchronous fallback runs when the singleton goes away
    destruct = REOPEN[REOPEN.index("Component.onDestruction") :]
    assert "root.flush()" in destruct[: destruct.index("\n")]
