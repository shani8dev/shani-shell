"""Wave 4 deep pass on Clocks: sound picker, inline rename, existing rows.

The world-clock add/remove/search and the 5/9/15-minute snooze choice arrived in
earlier waves, so those are pinned here rather than re-implemented. The genuinely
new logic - a per-alarm sound hint and a quick rename - runs through node as
plain JS: extraction keeps the test on the shipped function, not a Python copy.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
CLOCKS = (ROOT / "shani/Modules/Clocks/ClocksWindow.qml").read_text(encoding="utf-8")
SERVICE = (ROOT / "shani/Services/WorldClock.qml").read_text(encoding="utf-8")
NODE = shutil.which("node") or shutil.which("nodejs")

node_only = pytest.mark.skipif(NODE is None, reason="node is not installed")

# The five canonical freedesktop sound-theme hints the picker may offer. Only
# these may ever be concatenated into notify-send's -h string:sound-name: value.
SOUNDS = ["alarm-clock-elapsed", "alarm-clock", "bell", "chime", "default"]
FALLBACK = "alarm-clock-elapsed"


def section(text, start, end):
    return text[text.index(start) : text.index(end)]


def js_function(text, name):
    """One `function name(...) { ... }` from the QML, braces balanced."""
    m = re.search(r"\bfunction\s+" + re.escape(name) + r"\s*\(", text)
    assert m, name
    start = text.index("{", m.end())
    depth = 0
    for j in range(start, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[m.start() : j + 1]
    raise AssertionError("unbalanced function " + name)


def run_js(prog, expr):
    source = prog + "\nconsole.log(JSON.stringify(" + expr + "));\n"
    out = subprocess.run(
        [NODE, "-e", source], capture_output=True, text=True, timeout=30
    )
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout.strip().splitlines()[-1])


def sound_prog():
    """The shipped sound helpers with a captured notify-send argv."""
    return "\n".join(
        [
            "var captured = null;",
            "var Quickshell = { execDetached: function(argv) { captured = argv; } };",
            "var root = { alarmSounds: " + json.dumps(SOUNDS) + " };",
            js_function(SERVICE, "validAlarmSound"),
            js_function(SERVICE, "alarmSound"),
            js_function(SERVICE, "ring"),
            "root.validAlarmSound = validAlarmSound;",
            "root.alarmSound = alarmSound;",
        ]
    )


def store_prog(alarms):
    """Sound + label setters over an in-memory Settings.data.alarms."""
    return "\n".join(
        [
            "var Settings = { data: { alarms: " + json.dumps(alarms) + " } };",
            "var root = { alarmSounds: " + json.dumps(SOUNDS) + " };",
            js_function(SERVICE, "validAlarmSound"),
            js_function(SERVICE, "alarmSound"),
            "root.validAlarmSound = validAlarmSound;",
            "root.alarmSound = alarmSound;",
            js_function(SERVICE, "setAlarmSound"),
            js_function(SERVICE, "setAlarmLabel"),
        ]
    )


# ---- existing features stay wired ------------------------------------------


def test_world_clock_search_add_and_remove_are_pinned():
    ui = section(CLOCKS, "// ---- world:", "// ---- alarms ----")
    for line in (
        "id: zoneSearch",
        'objectName: "clocks-zone-search"',
        "WorldClock.matchingZones(zoneSearch.text)",
        'objectName: "clocks-zone-result"',
        "WorldClock.addWorldClock(modelData)",
        'objectName: "clocks-remove-city"',
        "WorldClock.removeWorldClock(modelData.zone)",
        'WorldClock.zonesError !== ""',
        "No matching time zones",
    ):
        assert line in ui, line
    svc = section(SERVICE, "// ---- zone picker", "// ---- convert a wall-clock")
    for line in (
        "function matchingZones(query)",
        '.replace(/ /g, "_")',
        "function addWorldClock(zone)",
        "(root.zones || []).indexOf(z) < 0",
        "function removeWorldClock(zone)",
        "Settings.data.worldClocks = list;",
    ):
        assert line in svc, line


def test_snooze_duration_choice_drives_the_snooze_button():
    ui = section(CLOCKS, "model: [5, 9, 10, 15]", "// ---- stopwatch ----")
    for line in (
        "clocks-snooze-length",
        "win.snoozeMinutes = modelData",
        "Snooze %1 minutes",
        "WorldClock.snooze(win.alarmLabel || win.alarmTime, win.snoozeMinutes, win.alarmGroup)",
        "clocks-snooze-row",
        "WorldClock.cancelSnooze(index)",
    ):
        assert line in ui, line
    choices = set(map(int, re.search(r"model: \[([0-9, ]+)\]", ui).group(1).split(",")))
    assert {5, 9, 15} <= choices


def test_wave_one_repeat_days_and_toggle_survive_the_row_change():
    ui = section(CLOCKS, "// ---- alarms ----", "// ---- stopwatch ----")
    for line in (
        'objectName: "clocks-repeat-day"',
        "win.alarmDays = d;",
        "Every day",
        'objectName: "clocks-alarm-toggle"',
        "onClicked: win.toggleAlarm(index)",
        "win.confirmAlarm === index",
    ):
        assert line in ui, line


def test_alarm_row_has_inline_label_and_sound_picker():
    ui = section(CLOCKS, "// ---- alarms ----", "// ---- stopwatch ----")
    for line in (
        'objectName: "clocks-alarm-row-label"',
        "WorldClock.setAlarmLabel(index, text)",
        'objectName: "clocks-alarm-sound"',
        "WorldClock.alarmSounds",
        "WorldClock.alarmSound(modelData.sound)",
        "WorldClock.setAlarmSound(index,",
        'Accessible.name: Tr.t("Sound: %1")',
    ):
        assert line in ui, line
    # only removal still needs the two-tap confirmation
    rename = section(ui, 'objectName: "clocks-alarm-row-label"', "clocks-alarm-sound")
    assert "win.confirmAlarm" not in rename


# ---- sound hints cannot become command-line options -------------------------


def test_the_hint_list_is_the_allowlist_used_by_the_service():
    m = re.search(r"readonly property var alarmSounds: (\[[^\]]*\])", SERVICE)
    assert m
    assert json.loads(m.group(1)) == SOUNDS
    assert "function validAlarmSound(name)" in SERVICE
    assert "function alarmSound(name)" in SERVICE


def test_ring_sends_one_allowlisted_hint_as_a_single_argv_item():
    ring = section(SERVICE, "function ring(summary", "function checkAlarms(")
    assert "root.alarmSound(soundName)" in ring
    assert '"string:sound-name:" + sound' in ring
    assert "Quickshell.execDetached([" in ring
    # no shell string, no raw user value in the hint slot
    assert '"sh", "-c"' not in ring
    assert "sound-name:" + '" + soundName' not in ring
    assert (
        'ring("⏰ " + (hit.label || hit.time), Tr.t("Alarm for %1", now), hit.sound)'
        in SERVICE
    )


@node_only
@pytest.mark.parametrize("name", SOUNDS)
def test_valid_sound_names_pass_through(name):
    prog = sound_prog()
    assert run_js(prog, "validAlarmSound(" + json.dumps(name) + ")") is True
    assert run_js(prog, "alarmSound(" + json.dumps(name) + ")") == name
    argv = captured_argv(prog, "ring('s', 'b', " + json.dumps(name) + ")")
    assert argv[argv.index("-h") + 1] == "string:sound-name:" + name


@node_only
@pytest.mark.parametrize(
    "bad",
    [
        "alarm-clock-elapsed; rm -rf /",
        "-u low",
        "--help",
        "bell: extra",
        "$(id)",
        "default\n-U all",
        "",
        None,
        42,
        {},
    ],
)
def test_untrusted_sound_values_fall_back_without_touching_argv(bad):
    prog = sound_prog()
    value = json.dumps(bad)
    assert run_js(prog, "validAlarmSound(" + value + ")") is False
    assert run_js(prog, "alarmSound(" + value + ")") == FALLBACK
    argv = captured_argv(prog, "ring('sub', 'body', " + value + ")")
    assert argv[0] == "notify-send"
    assert argv.count("-h") == 1
    assert argv[argv.index("-h") + 1] == "string:sound-name:" + FALLBACK
    assert argv[-2:] == ["sub", "body"]
    if isinstance(bad, str) and bad:
        assert bad not in json.dumps(argv)


@node_only
def test_ring_without_a_sound_keeps_the_original_hint():
    prog = sound_prog()
    argv = captured_argv(prog, "ring('s', 'b')")
    assert argv[argv.index("-h") + 1] == "string:sound-name:alarm-clock-elapsed"


def captured_argv(prog, call):
    """capture argv after a call while keeping the helper program pristine."""
    return run_js(prog + "\n" + call + ";", "captured")


# ---- per-alarm persistence is pure record editing ---------------------------


@node_only
def test_inline_label_edit_changes_one_record_and_keeps_the_rest():
    alarms = [
        {
            "time": "07:00",
            "label": "Wake up",
            "days": [1, 2],
            "group": "Weekdays",
            "sound": "bell",
            "enabled": True,
        },
        {"time": "08:00", "label": "Second"},
    ]
    prog = store_prog(alarms)
    assert run_js(prog, "setAlarmLabel(0, '  Coffee  ')") is True
    stored = run_js(prog, "setAlarmLabel(0, '  Coffee  ') && Settings.data.alarms")
    assert stored[0]["label"] == "Coffee"
    assert stored[0]["days"] == [1, 2] and stored[0]["group"] == "Weekdays"
    assert stored[0]["sound"] == "bell" and stored[0]["enabled"] is True
    assert stored[1] == alarms[1]
    assert run_js(prog, "setAlarmLabel(0, '   ')") is False
    assert run_js(prog, "setAlarmLabel(9, 'x')") is False


@node_only
def test_sound_edit_validates_before_it_writes():
    alarms = [
        {"time": "07:00", "label": "Wake up"},
        {"time": "08:00", "label": "Second"},
    ]
    prog = store_prog(alarms)
    result = run_js(
        prog,
        "(function () {"
        "var ok = setAlarmSound(0, 'chime');"
        "var rejected = ['-u low', 'bell; echo pwned', '', 7].every("
        "function (v) { return setAlarmSound(0, v) === false; });"
        "return { ok: ok, rejected: rejected, alarms: Settings.data.alarms };"
        "})()",
    )
    assert result["ok"] and result["rejected"]
    stored = result["alarms"]
    assert stored[0]["sound"] == "chime"
    assert stored[0]["label"] == "Wake up" and stored[1] == alarms[1]


@node_only
def test_snooze_minutes_are_bounded_at_the_service():
    ui = section(CLOCKS, "model: [5, 9, 10, 15]", "// ---- stopwatch ----")
    choices = [
        int(x) for x in re.search(r"model: \[([0-9, ]+)\]", ui).group(1).split(",")
    ]
    assert all(1 <= m <= 600 for m in choices)
    prog = "\n".join(
        [
            "var root = { snoozes: [] };",
            "var snoozeTick = { restart: function() {} };",
            js_function(SERVICE, "snooze"),
        ]
    )
    for m in (5, 9, 15):
        assert (
            run_js(
                prog + "\nroot.snoozes = []; snooze('x', " + str(m) + ");",
                "root.snoozes[0].minutes",
            )
            == m
        )
    for bad in (0, -5, None, "abc"):
        minutes = run_js(
            prog + "\nroot.snoozes = []; snooze('x', " + json.dumps(bad) + ");",
            "root.snoozes[0].minutes",
        )
        assert minutes >= 1, bad
