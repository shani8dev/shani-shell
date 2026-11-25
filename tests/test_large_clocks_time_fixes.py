"""Static checks for the large time-management upgrade of the Clocks window.

Benchmarked against GNOME Clocks (edit/rename an alarm, 9-minute snooze, lap
splits, add a city, custom timer duration), KDE KClock (multiple named timers,
timer presets, alarm repeat days) and Apple Clock (named/repeating alarms,
several timers, stopwatch lap sharing, a world-clock city list). The QML is
compiled by the shell's render harness, so here each branch is asserted on the
shipped source rather than by launching a shell. Every check reads only our two
owned files.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


CLOCKS = source("shani/Modules/Clocks/ClocksWindow.qml")
SERVICE = source("shani/Services/WorldClock.qml")


def section(text, start, end):
    """The source between two markers, so an assertion stays in its branch."""
    return text[text.index(start) : text.index(end)]


# ---- alarms -----------------------------------------------------------------


def test_alarm_rings_once_per_record_not_once_per_minute():
    # GNOME/KClock add an alarm during the current minute and expect it to ring;
    # a single "lastFired" string swallowed it. Keys include the record.
    assert "if (now === lastFired) return;" not in SERVICE
    assert "property string lastFired:" in SERVICE
    assert "property var firedKeys: []" in SERVICE
    check = SERVICE[SERVICE.index("function checkAlarms()") :]
    check = check[: check.index("function snooze(")]
    for line in (
        "if (now !== root.lastFired) {",
        "root.firedKeys = [];",
        "const key = root.alarmKey(a, now);",
        "if (root.firedKeys.indexOf(key) >= 0) return false;",
        "keys.push(key);",
        "root.firedKeys = root.firedKeys.concat(keys);",
    ):
        assert line in check, line
    keyfn = SERVICE[SERVICE.index("function alarmKey(a, minute)") :]
    keyfn = keyfn[: keyfn.index("readonly property var groups")]
    assert 'a.days.join(",")' in keyfn  # a changed repeat pattern is a new alarm


def test_alarm_edit_preserves_identity_group_and_repeat_days():
    # GNOME Clocks' Edit changes the time/label without deleting and re-adding.
    assert "function updateAlarm(index, time, label, days, enabled)" in SERVICE
    edit = SERVICE[SERVICE.index("function updateAlarm(") :]
    edit = edit[: edit.index("function removeAlarm(")]
    for line in (
        "Object.assign({}, list[index], {",
        "if (!/^([01]?\\d|2[0-3]):[0-5]\\d$/.test(t)) return false;",
        "delete rec.days;",
        "list[index] = rec;",
    ):
        assert line in edit, line
    assert "function setAlarmGroup(index, group)" in edit
    assert "delete rec.group;" in edit
    assert "readonly property var groups:" in SERVICE
    assert ".filter(g => g))).sort()" in SERVICE


def test_alarm_form_loads_edits_and_filters_by_group():
    for line in (
        'property string alarmGroup: ""',
        'property string alarmFilter: ""',
        "property int editingAlarm: -1",
        "function editAlarm(index)",
        "function cancelAlarmEdit()",
        "function saveAlarm()",
        "WorldClock.updateAlarm(win.editingAlarm,",
        "WorldClock.setAlarmGroup(win.editingAlarm,",
        "WorldClock.setAlarmGroup(WorldClock.alarms.length - 1,",
        "function alarmVisible(a)",
        'model: [""].concat(Array.from(WorldClock.groups || []))',
        'modelData.group ? " [" + modelData.group + "]" : ""',
        "No alarms in this group",
    ):
        assert line in CLOCKS, line
    # the same form still adds a new alarm through the service's original call
    assert "WorldClock.addAlarm(win.alarmTime, win.alarmLabel, win.alarmDays)" in CLOCKS
    assert (
        "WorldClock.addAlarm(win.alarmTime, win.alarmLabel, win.alarmDays)"
        in CLOCKS[
            CLOCKS.index("function saveAlarm()") : CLOCKS.index(
                "function alarmVisible("
            )
        ]
    )
    assert "onClicked: win.saveAlarm()" in CLOCKS
    assert "Every day" in CLOCKS  # weekday repeat untouched


# ---- snooze ------------------------------------------------------------------


def test_snooze_length_list_cancel_and_pending_rows():
    assert "function snooze(label, minutes)" in SERVICE  # old two-arg callers
    assert 'arguments.length > 2 ? arguments[2] : ""' in SERVICE
    assert 'minutes: m, group: String(group || "")' in SERVICE
    assert "function cancelSnooze(index)" in SERVICE
    cancel = SERVICE[SERVICE.index("function cancelSnooze(") :]
    cancel = cancel[: cancel.index("function checkSnoozes(")]
    assert "list.splice(index, 1);" in cancel
    assert "if (list.length === 0) snoozeTick.stop();" in cancel
    ui = section(CLOCKS, "model: [5, 9, 10, 15]", "// ---- stopwatch ----")
    for line in (
        "clocks-snooze-length",
        "model: WorldClock.snoozes",
        "clocks-snooze-row",
        "WorldClock.cancelSnooze(index)",
        "Snoozed %1 min",
        "WorldClock.snooze(win.alarmLabel || win.alarmTime, win.snoozeMinutes, win.alarmGroup)",
    ):
        assert line in ui, line


# ---- timers ------------------------------------------------------------------


def test_multiple_named_timers_tick_and_notify():
    timers = section(SERVICE, "property var timers: []", "// ---- stopwatch ----")
    for line in (
        "function addTimer(minutes, label)",
        "if (!(m >= 1 && m <= 600)) return false;",
        "id: ++root.timerSeq",
        "timerTick.start();",
        "function toggleTimer(index)",
        "function restartTimer(index)",
        "function removeTimer(index)",
        "function tickTimers()",
        "Math.max(0, t.left - timerTick.interval)",
        "if (!list.some(t => t.running)) timerTick.stop();",
        'ring(Tr.t("Timer done"), label)',
    ):
        assert line in timers, line
    # one ticker serves all timers, and it does not run when none is active
    assert "Timer { id: timerTick; interval: 1000; repeat: true;" in timers


def test_multi_timer_ui_has_presets_name_pause_restart_remove_and_empty_state():
    ui = CLOCKS[CLOCKS.index("Other timers") :]
    for line in (
        "clocks-multitimer-preset",
        "id: timerName",
        "id: timerCustom",
        'error: text !== "" && !(Number(text) >= 1 && Number(text) <= 600)',
        "WorldClock.addTimer(Number(timerCustom.text) || win.timerMinutes, timerName.text)",
        "WorldClock.toggleTimer(index)",
        "WorldClock.restartTimer(index)",
        "WorldClock.removeTimer(index)",
        "WorldClock.fmt(modelData.left)",
        "No other timers",
    ):
        assert line in ui, line


def test_preset_timer_and_restart_contract_is_kept():
    # the island timer is still driven by FocusTimer; the presets are preset.
    assert "property int lastTimerMinutes: 0" in CLOCKS
    assert "win.lastTimerMinutes = modelData; FocusTimer.start(modelData)" in CLOCKS
    assert 'Tr.t("Restart %1 min")' in CLOCKS
    assert "FocusTimer.start(win.lastTimerMinutes)" in CLOCKS
    assert "FocusTimer.stop()" in CLOCKS


# ---- stopwatch ---------------------------------------------------------------


def test_stopwatch_laps_carry_splits_and_export():
    sw = section(SERVICE, "property var swLaps:", "id: swTick")
    for line in (
        "property var swLapDeltas: []",
        "property var swLapTotals: []",
        "function fmtDelta(ms)",
        "root.fmtDelta(total - previous)",
        "root.swLapDeltas.slice(root.swLapDeltas.length - 12)",
        "root.swLapTotals.slice(root.swLapTotals.length - 12)",
        "function swExportText()",
        'Tr.t("Stopwatch laps")',
        'lines.push(String(i + 1) + ". " + root.swLaps[i] + " (" + root.swLapDeltas[i] + ")")',
    ):
        assert line in sw, line
    assert "swLaps = []; swLapDeltas = []; swLapTotals = [];" in sw
    ui = section(CLOCKS, "// ---- stopwatch ----", "// ---- timer:")
    assert "WorldClock.swLapDeltas[index]" in ui
    assert "Quickshell.clipboardText = WorldClock.swExportText()" in ui
    assert "win.lapsCopied" in ui
    assert "No laps yet" in ui


# ---- world clock + conversion ------------------------------------------------


def test_zone_list_search_add_remove_and_error_state():
    zones = section(SERVICE, "// ---- zone picker", "// ---- convert a wall-clock")
    for line in (
        "property var zones: []",
        'property string zonesError: ""',
        "timedatectl list-timezones",
        "Time zones unavailable",
        "function matchingZones(query)",
        '.replace(/ /g, "_")',
        ".slice(0, 8);",
        "function addWorldClock(zone)",
        "(root.zones || []).indexOf(z) < 0",
        "Settings.data.worldClocks = list;",
        "function removeWorldClock(zone)",
        "root.refresh();",
    ):
        assert line in zones, line
    ui = section(CLOCKS, "// ---- world:", "// ---- alarms ----")
    for line in (
        "id: zoneSearch",
        "WorldClock.matchingZones(zoneSearch.text)",
        "WorldClock.addWorldClock(modelData)",
        "WorldClock.removeWorldClock(modelData.zone)",
        'WorldClock.zonesError !== ""',
        "No matching time zones",
    ):
        assert line in ui, line
    assert "contentHeight: worldCol.implicitHeight" in ui  # results fit on screen


def test_timezone_conversion_helper_validates_before_spawning_date():
    conv = section(SERVICE, "// ---- convert a wall-clock", "// ---- alarms ---")
    for line in (
        "function convertZoneTime(fromZone, toZone, timeText)",
        "(root.zones || []).indexOf(f) < 0",
        "(root.zones || []).indexOf(t) < 0",
        "/^([01]?\\d|2[0-3]):[0-5]\\d$/.test(time)",
        'epoch=$(TZ="$1" date -d "$2" +%s',
        "convertProc.running = true;",
        "root.convertResult = s;",
        'Tr.t("That time could not be converted")',
    ):
        assert line in conv, line
    ui = section(CLOCKS, "Convert a time", "// ---- alarms ----")
    for line in (
        "id: convFrom",
        "id: convTo",
        "id: convTime",
        "WorldClock.convertZoneTime(convFrom.text, convTo.text, convTime.text)",
        'WorldClock.convertError !== ""',
        'WorldClock.convertResult !== ""',
    ):
        assert line in ui, line


# ---- keyboard and accessibility ----------------------------------------------


def test_keyboard_navigation_covers_home_end_and_page_keys():
    keys = section(CLOCKS, "readonly property bool textFocus", "ColumnLayout {")
    for line in (
        "readonly property bool textFocus",
        "function navTab(delta)",
        "Keys.onPressed: e => {",
        "Qt.Key_Home",
        "Qt.Key_End",
        "Qt.Key_PageUp",
        "Qt.Key_PageDown",
    ):
        assert line in keys, line
    assert "Keys.onEscapePressed" in CLOCKS and "Keys.onSpacePressed" in CLOCKS
    # Home/End/Page navigation now uses Keys.onPressed with key checks (canonical)
    assert CLOCKS.count("Keys.onPressed:") >= 2
    for key in ("Qt.Key_Home", "Qt.Key_End", "Qt.Key_PageUp", "Qt.Key_PageDown"):
        assert key in CLOCKS


def test_interactive_controls_carry_stable_names_for_assistive_tech():
    named = (
        "clocks-tab-",
        "clocks-zone-search",
        "clocks-remove-city",
        "clocks-convert-from",
        "clocks-convert-go",
        "clocks-alarm-edit",
        "clocks-alarm-save",
        "clocks-alarm-label",
        "clocks-alarm-group",
        "clocks-snooze-length",
        "clocks-snooze-row",
        "clocks-sw-export",
        "clocks-timer-preset",
        "clocks-timer-restart",
        "clocks-multitimer-preset",
        "clocks-timer-name",
        "clocks-multitimer-row",
    )
    for obj in named:
        assert ('objectName: "' + obj) in CLOCKS, obj
    assert CLOCKS.count("Accessible.name:") >= 10
    # buttons whose label is a state or a variable still get a spoken name
    for line in (
        'Accessible.name: Tr.t("Remove world clock %1").arg(modelData.city)',
        'Accessible.name: Tr.t("Edit alarm at %1").arg(modelData.time)',
        'Accessible.name: Tr.t("Copy all laps to the clipboard")',
        'Accessible.name: Tr.t("Restart %1").arg(modelData.label)',
    ):
        assert line in CLOCKS, line
    assert 'label: Tr.t("Alarm group")' in CLOCKS
    assert 'label: Tr.t("From zone")' in CLOCKS


def test_empty_and_error_states_are_visible_in_every_tab():
    for line in (
        "No other cities yet",
        'WorldClock.zonesError !== ""',
        "No matching time zones",
        'WorldClock.convertError !== ""',
        "No alarms",
        "No alarms in this group",
        "No laps yet",
        "No other timers",
        "Use 1–600 minutes",
    ):
        assert line in CLOCKS, line


def test_sidebar_and_older_service_callers_still_work():
    # SidebarClock passes two arguments to addAlarm and reads string laps.
    assert "function addAlarm(time, label, days, enabled)" in SERVICE
    assert "function snooze(label, minutes)" in SERVICE
    assert "property var swLaps: []" in SERVICE
    assert "swLaps = swLaps.concat([swDisplay]);" in SERVICE
    assert "readonly property var alarms: Array.from(WorldClock.alarms || [])" in CLOCKS
    assert "onAlarmsChanged: win.confirmAlarm = -1" in CLOCKS
    assert "win.confirmAlarm === index" in CLOCKS
    assert "function toggleAlarm(index)" in CLOCKS
    assert "onClicked: win.toggleAlarm(index)" in CLOCKS
