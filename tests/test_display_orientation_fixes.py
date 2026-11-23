"""Static guards for the display/orientation service fixes.

No QML runtime, accelerometer, wlsunset or convertible here: each test reads
the one service it guards and checks the exact expression that changes behaviour.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICES = ROOT / "shani" / "Services"


def source(name):
    return (SERVICES / name).read_text(encoding="utf-8")


def test_autorotate_off_restores_upright():
    """Turning auto-rotate off must undo a tilt we applied, not freeze it."""
    t = source("AutoRotate.qml")
    assert 'property string applied: ""' in t, "remember the transform we set"
    assert re.search(r"Quickshell\.execDetached\(\[.*?\"transform\", t\]\)", t), (
        "apply() still sends the transform to niri"
    )
    assert "root.applied = t" in t, "apply() records what was sent"
    assert re.search(
        r"onActiveChanged: if \(!active && root\.applied !== \"\" && root\.applied !== \"normal\"\) root\.apply\(\"normal\"\)",
        t,
    ), "only a disabled, actually-rotated panel is restored"


def test_autorotate_stops_when_locked():
    """A locked device must not follow the accelerometer into a new rotation."""
    t = source("AutoRotate.qml")
    assert re.search(r"running: root\.active && root\.available && !Lock\.locked", t), (
        "the watcher is gated on the lock state"
    )
    assert re.search(
        r"onExited: if \(root\.active && root\.available && !Lock\.locked", t
    ), "a stop caused by locking is not retried"
    assert "Timer {" in t and "id: retry" in t, "a retry path exists"


def test_autorotate_recovers_from_a_dead_sensor_watcher():
    """monitor-sensor dying under a restart must not leave auto-rotate inert."""
    t = source("AutoRotate.qml")
    assert "onStarted: root.retries = 0" in t, "a healthy start clears the counter"
    body = t[t.index("id: sensor") : t.index("id: retry")]
    assert re.search(
        r"onExited: if \(.*?root\.retries\+\+ < 3\) retry\.restart\(\)", body
    ), "a bounded number of restarts follows a crash"
    retry = t[t.index("id: retry") :]
    assert "sensor.running = false" in retry and "Qt.binding(" in retry, (
        "the same running binding is re-armed, not just set to true"
    )
    assert "root.active && root.available && !Lock.locked" in retry, (
        "the re-armed binding keeps the lock guard"
    )


def test_nightlight_schedule_state_is_fresh():
    """'Warm now' must clear on manual and update as soon as the times change."""
    t = source("NightLight.qml")
    body = t[t.index("function updateScheduledNow()") : t.index("Timer {")]
    assert (
        'if (root.schedule === "manual") { root.scheduledNow = false; return; }' in body
    ), "leaving a schedule clears the stale value"
    assert "root.scheduledNow = from >= 0 && to >= 0" in body, (
        "the resolver still computes the real schedule window"
    )
    assert "onScheduleChanged: root.updateScheduledNow()" in t, (
        "changing schedule recomputes immediately"
    )
    conn = t[t.index("target: Settings.data") :]
    assert (
        "function onNightLightFromChanged()" in conn
        and "function onNightLightToChanged()" in conn
    ), "editing either time recomputes without waiting a minute"
    assert re.search(r"onTriggered: root\.updateScheduledNow\(\)", t), (
        "the minute tick uses the same resolver"
    )


def test_tabletmode_does_not_leave_a_stale_keyboard():
    """Turning the tablet-mode keyboard option off mid-fold closes our OSK."""
    t = source("TabletMode.qml")
    assert "property bool oskFromTablet: false" in t, "track whether the OSK is ours"
    handler = t[t.index("onOnChanged:") : t.index("Connections {")]
    assert (
        "Osk.toggle();" in handler
        and "root.oskFromTablet = on && Osk.shown;" in handler
    ), "only a keyboard we actually opened is marked as ours"
    setting = t[t.index("function onOskWithTabletModeChanged()") :]
    assert (
        "!Settings.data.oskWithTabletMode && root.oskFromTablet && Osk.shown" in setting
    ), "the option turning off is what closes it"
    assert "Osk.toggle();" in setting and "root.oskFromTablet = false;" in setting, (
        "close our keyboard and drop the flag"
    )
    osk_conn = t[t.index("target: Osk") :]
    assert (
        "function onShownChanged()" in osk_conn
        and "if (!Osk.shown) root.oskFromTablet = false" in osk_conn
    ), "a keyboard closed elsewhere is not ours to close on unfold"
    assert (
        'what === "tablet-on" || what === "tablet-off"' in t
        and 'what === "lid-close"' in t
    ), "switch event handling is unchanged"
