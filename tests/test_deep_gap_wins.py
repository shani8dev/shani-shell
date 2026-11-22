"""Fixes found in the second-pass deep gap audit."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return (ROOT / path).read_text()


def test_process_tree_keeps_parent_links():
    s = read("shani/Services/TopProcesses.qml")
    # The helper emitted ppid but the row dropped it, so buildTree saw no
    # parents and every process became a root (indent always 0).
    assert "pid: p.pid, ppid: p.ppid, name: p.name" in s
    assert "function end(pid, signal)" in s
    assert 'TERM", "KILL", "INT", "HUP", "STOP", "CONT' in s
    assert '/"' + "^-?[A-Z]*" in s or "indexOf(signal)" in s


def test_end_signal_selector_is_global_and_bounded():
    p = read("shani/Modules/Processes/Processes.qml")
    assert 'property string endSignal: "TERM"' in p
    assert "TopProcesses.end(procRow.p.pid, win.endSignal)" in p
    assert "End with signal:" in p
    # the selector must be outside the per-row delegate
    assert p.index("End with signal:") < p.index("model: win.shownList")


def test_software_shows_all_screenshots():
    s = read("shani/Modules/Software/SoftwareWindow.qml")
    assert "model: appCol.a.screenshots || []" in s
    assert "orientation: ListView.Horizontal" in s
    assert "(appCol.a.screenshots || [])[0]" not in s


def test_feeds_mark_all():
    bridge = read("bridge/feeds.py")
    svc = read("shani/Services/Feeds.qml")
    win = read("shani/Modules/Feeds/FeedsWindow.qml")
    assert 'cmd == "markall"' in bridge
    assert 'read = c.setdefault("read", {})' in bridge
    assert "function markAll()" in svc
    assert "Mark all read" in win


def test_photos_tile_has_slideshow_and_trash():
    s = read("shani/Modules/Photos/PhotosWindow.qml")
    assert "Viewer.toggleSlideshow();" in s
    assert "Viewer.trash(); win.scan();" in s


def test_notification_progress_bar():
    s = read("shani/Modules/Notifications/NotificationCard.qml")
    assert "notification.progress >= 0" in s
    assert "notification.progress <= 1" in s
    assert "width: parent.width * notification.progress" in s


def test_window_menu_lists_all_workspaces():
    s = read("shani/Modules/WindowMenu/WindowMenu.qml")
    assert "Niri.workspacesOn(Niri.focusedOutput).map(" in s
    assert '"ws1"' not in s and '"ws2"' not in s and '"ws3"' not in s
