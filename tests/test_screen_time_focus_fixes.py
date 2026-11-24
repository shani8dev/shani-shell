"""Static checks for ScreenTime/Focus accounting, persistence and schedule fixes.

These two singletons have no QML runtime in the suite; each test pins the
source expression that implements one fix so a future edit cannot quietly
restore the old behaviour.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCREEN = (ROOT / "shani/Services/ScreenTime.qml").read_text()
FOCUS = (ROOT / "shani/Services/Focus.qml").read_text()


def test_label_carries_rounded_minutes_into_the_hour():
    # 1h59m30s used to render "1 h 60 min": minutes were rounded after the
    # hour was taken from the unrounded remainder.
    label = SCREEN.split("function label(s) {", 1)[1].split("}", 1)[0]
    assert "Math.round(s / 60)" in label
    assert "Math.floor(m / 60)" in label
    assert "m -= h * 60" in label
    assert "(s % 3600)" not in label


def test_tick_counts_elapsed_time_capped_to_one_interval():
    assert "property var lastTick: 0" in SCREEN
    tick = SCREEN.split("onTriggered: {", 1)[1].split(
        "const w = Niri.focusedWindow", 1
    )[0]
    assert "Date.now()" in tick
    assert "Math.min(15000, now - root.lastTick)" in tick
    assert "Math.round(" in tick and "root.lastTick = now" in tick
    assert "t[app] = (t[app] || 0) + secs" in SCREEN
    assert "root.streak += secs" in SCREEN
    assert "+ 15" not in SCREEN


def test_daily_limit_marker_survives_a_restart_without_being_pruned():
    assert "{ _told: root.today }" in SCREEN
    assert 'typeof stored._told === "string"' in SCREEN
    assert (
        'root.limitToldFor = stored && typeof stored._told === "string" ? stored._told : ""'
        in SCREEN
    )
    assert "filter(k => /^\\d{4}-\\d{2}-\\d{2}$/.test(k))" in SCREEN
    assert "dates.slice(0, -35)" in SCREEN


def test_focus_minutes_rejects_impossible_times():
    body = FOCUS.split("function minutes(hhmm) {", 1)[1].split(
        "function inSchedule", 1
    )[0]
    assert "if (!m) return -1" in body
    assert "if (h > 23 || min > 59) return -1" in body
    assert "return h * 60 + min" in body


def test_dangling_manual_mode_does_not_disable_schedules():
    active = FOCUS.split("readonly property string active: {", 1)[1].split("}", 1)[0]
    assert "const manual = Settings.data.focusMode" in active
    assert "modes.some(m => m.name === manual)" in active
    assert "? manual : scheduled" in active


def test_today_guards_the_clock_date_against_a_startup_undefined():
    """clock.date is undefined until the SystemClock is up; handing that to
    Qt.formatDate assigns undefined to a string and warns at shell start."""
    assert "clock && clock.date ? clock.date : new Date()" in SCREEN
