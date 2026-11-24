"""Static checks for five low-risk competitive-research fixes.

The QML is not instantiated in this suite, so each fix is asserted against the
source it lives in: the now-playing seek bar tracks user seeks while paused,
scrubs on drag and is exposed as a Slider to assistive tech; the notification
centre groups by desktop entry as the popups do; and the popup layer drops
expired stacks and never sweeps a critical popup away with "Clear all".
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NP = (ROOT / "shani/Modules/ControlCenter/SidebarNowPlaying.qml").read_text(
    encoding="utf-8"
)
SB = (ROOT / "shani/Modules/ControlCenter/SidebarNotifications.qml").read_text(
    encoding="utf-8"
)
POPUPS = (ROOT / "shani/Modules/Notifications/Popups.qml").read_text(encoding="utf-8")


def _slice(text, start, end):
    return text[text.index(start) : text.index(end, text.index(start))]


SEEK = _slice(NP, "id: seek", "Row {")


def test_seek_bar_tracks_user_seeks_while_paused():
    """The sampling timer is off when paused, so a seek must update the bar itself."""
    assert SEEK.count("np.shown = pos") == 2, "both click/step refresh shown"
    step = SEEK[SEEK.index("onStep: dir => {") :]
    assert "sidebar.player.position = pos" in step
    assert "np.shown = pos" in step
    assert "onStep: dir => sidebar.player.position" not in SEEK


def test_seek_drags_scrub_while_the_pointer_is_held():
    """Clicking was not enough: dragging must follow and set the position."""
    area = _slice(SEEK, "MouseArea {", "KeyFocus")
    assert "function seekTo(x)" in area
    assert "sidebar.player.position = pos" in area
    assert "onPressed: me => seekTo(me.x)" in area
    assert "onPositionChanged: me => { if (pressed) seekTo(me.x); }" in area


def test_seek_is_exposed_as_a_slider_to_assistive_tech():
    """AT gets the Slider role and a spoken elapsed / duration name and value."""
    assert "Accessible.role: Accessible.Slider" in SEEK
    assert 'Accessible.name: Tr.t("Position")' in SEEK
    assert "Math.floor(np.shown / 60)" in SEEK, "elapsed in the name"
    assert "Math.floor(len / 60)" in SEEK, "duration in the name"
    assert "property real value: len > 0 ? np.shown / len : 0" in SEEK
    # this codebase has no attachable Accessible.value - assigning one is an error
    assert "Accessible.value:" not in SEEK


def test_notification_groups_key_on_desktop_entry():
    """Grouping must match Popups.appKey so an app's two kinds stay one stack."""
    groups = _slice(SB, "const q = filter.toLowerCase();", "return groups;")
    assert 'const key = n.desktopEntry || n.appName || "Notifications";' in groups
    assert "groups.find(x => x.key === key)" in groups
    assert 'key: key, app: n.appName || "Notifications"' in groups, "friendly name kept"
    assert "groups.find(x => x.app === key)" not in SB


def test_popups_prune_expired_stacks_and_keep_critical_on_clear_all():
    """An empty stack is dropped; an incoming call is not swept away."""
    groups = _slice(POPUPS, "function groupPopups()", "function clearPopups()")
    assert "return out.filter(g => g.items.length > 0);" in groups
    clear = _slice(POPUPS, "function clearPopups()", "function toggleGroup")
    assert "for (const n of Notifs.popups.slice())" in clear
    assert "if (n && n.urgency !== NotificationUrgency.Critical)" in clear
    assert "n.dismiss();" in clear
    assert "win.expanded = ({})" in clear
