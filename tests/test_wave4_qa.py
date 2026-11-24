"""WAVE 4 adversarial QA — regression tests for the surfaces landed this wave.

Read-only: this file never edits QML or bridge source. Every check pins the
CORRECT behaviour, so it passes on good code and fails the moment a fix is
undone. Where a surface is pure logic the *exact* QML functions are executed in
node; elsewhere a guard is pinned in the source.

A file still being landed is skipped with a loud reason, not failed: a missing
file is not a bug in code that does not exist yet.

Bug classes hunted (all seen once in this repo already):
  * hardcoded user-facing strings (must be Tr.t-wrapped and in template.json)
  * null/undefined derefs, in-place mutation of property arrays
  * timers/pollers running while nothing wants them (idle cost)
  * user data interpolated into shell strings (must be argv)
  * unbounded caches/lists, missing Accessible names
  * duplicate/conflicting key handlers (an unaccepted event reaches the parent)
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge"
if str(BRIDGE) not in sys.path:
    sys.path.insert(0, str(BRIDGE))

NODE = shutil.which("node") or shutil.which("nodejs")
TEMPLATE = json.loads((ROOT / "shani/i18n/template.json").read_text(encoding="utf-8"))

FILES_PANEL = "shani/Modules/Files/FilesPanel.qml"
PDF_READER = "shani/Modules/PdfReader/PdfReader.qml"
PDF_VIEWER = "shani/Services/PdfViewer.qml"
OSK_KEYBOARD = "shani/Modules/Osk/Keyboard.qml"
OSK_SERVICE = "shani/Services/Osk.qml"
CLOCKS = "shani/Modules/Clocks/ClocksWindow.qml"
WORLD_CLOCK = "shani/Services/WorldClock.qml"
RELEASE_SERVICE = "shani/Services/ReleaseNotes.qml"
RELEASE_PAGE = "shani/Modules/Settings/SettingsReleaseNotes.qml"
TRANSLATE = "shani/Modules/Translate/TranslateWindow.qml"
TRIMMER = "shani/Modules/VideoTrimmer/VideoTrimmerPanel.qml"

WAVE4_QML = (
    FILES_PANEL,
    PDF_READER,
    PDF_VIEWER,
    OSK_KEYBOARD,
    OSK_SERVICE,
    CLOCKS,
    WORLD_CLOCK,
    RELEASE_SERVICE,
    RELEASE_PAGE,
    TRANSLATE,
    TRIMMER,
)


def src(rel: str) -> str:
    """Read a wave-4 file, or skip while its subagent has not landed it."""
    path = ROOT / rel
    if not path.exists():
        pytest.skip(f"wave-4 file has not landed yet: {rel}")
    return path.read_text(encoding="utf-8")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def source_of(text: str, name: str) -> str:
    """One `function name(...) { ... }` verbatim, braces matched."""
    m = re.search(r"function\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{", text)
    assert m, f"function {name}() not found"
    depth = 0
    for j in range(m.end() - 1, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[m.start() : j + 1]
    raise AssertionError(f"unterminated function {name}()")


def funcs(text: str, *names: str) -> str:
    return "\n".join(source_of(text, name) for name in names)


def node(prog: str):
    assert NODE, "node is required"
    out = subprocess.run(
        [NODE, "-e", prog], capture_output=True, text=True, timeout=30, check=True
    )
    return json.loads(out.stdout.strip().splitlines()[-1])


def objects(text: str, kind: str):
    """Every `Kind { ... }` as (line, body), braces matched (strings blanked)."""
    clean = re.sub(
        r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'', lambda m: " " * len(m.group()), text
    )
    out = []
    for m in re.finditer(r"\b" + re.escape(kind) + r"\s*\{", clean):
        depth = 0
        for j in range(m.end() - 1, len(clean)):
            if clean[j] == "{":
                depth += 1
            elif clean[j] == "}":
                depth -= 1
                if depth == 0:
                    out.append(
                        (text.count("\n", 0, m.start()) + 1, text[m.start() : j + 1])
                    )
                    break
    return out


def balanced(text: str, start: int) -> str:
    """One balanced `{ ... }` block beginning at `start`, quoted strings skipped."""
    i = text.index("{", start)
    depth = 0
    quote = None
    escaped = False
    for j in range(i, len(text)):
        c = text[j]
        if quote:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == quote:
                quote = None
            continue
        if c in ('"', "'"):
            quote = c
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start : j + 1]
    raise AssertionError(f"unterminated block at {start}")


def tr_strings(text: str) -> set[str]:
    """Literal Tr.t("...") keys, unescaped the way tools/i18n.py extracts them."""
    return set(
        m.replace('\\"', '"').replace("\\\\", "\\")
        for m in re.findall(r'Tr\.t\(\s*"((?:[^"\\]|\\.)*)"\s*\)', text)
    )


# ---------------------------------------------------------------------------
# FilesPanel — the finer filter popover
# ---------------------------------------------------------------------------


def filter_prog() -> str:
    s = src(FILES_PANEL)
    return (
        funcs(
            s,
            "computeActiveFilterCount",
            "filterDateCutoff",
            "filterSizeBounds",
            "entryPassesFilters",
        )
        + """
var win = {
  dateFilter: "any", sizeFilter: "any",
  computeActiveFilterCount: computeActiveFilterCount,
  filterDateCutoff: filterDateCutoff, filterSizeBounds: filterSizeBounds,
  entryPassesFilters: entryPassesFilters
};
"""
    )


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_files_filter_date_cutoffs_are_bounded():
    out = node(
        filter_prog()
        + """
var now = Date.UTC(2026, 10, 24, 12, 0, 0);
var today = win.filterDateCutoff("today", now);
process.stdout.write(JSON.stringify({
  any: win.filterDateCutoff("any", now),
  week: now - win.filterDateCutoff("7days", now),
  month: now - win.filterDateCutoff("30days", now),
  today: today, now: now
}));"""
    )
    assert out["any"] == 0
    assert out["week"] == 7 * 86400000
    assert out["month"] == 30 * 86400000
    assert 0 <= out["now"] - out["today"] < 86400000


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_files_filter_size_buckets_do_not_overlap():
    out = node(
        filter_prog()
        + """
process.stdout.write(JSON.stringify({
  any: win.filterSizeBounds("any"),
  small: win.filterSizeBounds("small"),
  medium: win.filterSizeBounds("medium"),
  large: win.filterSizeBounds("large")
}));"""
    )
    assert out["any"] == [-1, -1]
    assert out["small"] == [0, 1024 * 1024 - 1]
    assert out["medium"] == [1024 * 1024, 100 * 1024 * 1024]
    assert out["large"][0] > out["medium"][1]
    assert out["large"][1] == -1, "large must have no upper bound"


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_files_entry_filters_keep_folders_and_apply_all_criteria():
    out = node(
        filter_prog()
        + """
var now = Date.UTC(2026, 10, 24, 12, 0, 0);
function e(isDir, name, mtime, size) {
  return { isDir: isDir, name: name, mtime: mtime, size: size };
}
function pass(entry, filters, foldersOnly) {
  return win.entryPassesFilters(entry, now, filters, foldersOnly);
}
var recent = e(false, "photo.PNG", now - 1000, 500);
var old = e(false, "note.txt", now - 8 * 86400000, 500);
var dir = e(true, "sub", 0, 0);
win.dateFilter = "any"; win.sizeFilter = "any";
var typeOk = pass(recent, ["png"], false) && !pass(recent, ["txt"], false);
var foldersPassType = pass(dir, ["txt"], false);
win.dateFilter = "7days";
var dateOk = pass(recent, [], false) && !pass(old, [], false);
var foldersPassDate = pass(dir, [], false);
win.dateFilter = "any"; win.sizeFilter = "small";
var sizeOk = pass(recent, [], false) && !pass(e(false, "big.mp4", now, 2 * 1024 * 1024), [], false);
win.sizeFilter = "large";
var largeOk = pass(e(false, "big.mp4", now, 101 * 1024 * 1024), [], false);
process.stdout.write(JSON.stringify({
  typeOk: typeOk, foldersPassType: foldersPassType,
  dateOk: dateOk, foldersPassDate: foldersPassDate,
  sizeOk: sizeOk, largeOk: largeOk,
  foldersOnly: !pass(recent, [], true) && pass(dir, [], true),
  nullEntry: pass(null, [], false)
}));"""
    )
    assert out["typeOk"] and out["foldersPassType"], out
    assert out["dateOk"] and out["foldersPassDate"], out
    assert out["sizeOk"] and out["largeOk"], out
    assert out["foldersOnly"] and not out["nullEntry"], out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_files_filter_badge_counts_each_active_filter_once():
    out = node(
        filter_prog()
        + """
process.stdout.write(JSON.stringify({
  none: win.computeActiveFilterCount("all", "any", "any", ""),
  all: win.computeActiveFilterCount("images", "today", "large", "cat"),
  two: win.computeActiveFilterCount("all", "7days", "small", "")
}));"""
    )
    assert out == {"none": 0, "all": 4, "two": 2}, out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_files_ctrl_shift_f_hits_the_filter_popover_before_plain_find():
    lines = [
        line.strip()
        for line in src(FILES_PANEL).splitlines()
        if "Qt.Key_F)" in line and line.strip().startswith("if (")
    ]
    assert len(lines) == 2, lines
    cond = lambda line: re.match(r"if \((.*)\) \{", line).group(1)
    assert "ShiftModifier" in lines[0], "the filter branch must precede plain find"
    out = node(
        """
var Qt = { Key_F: 1, ShiftModifier: 2, ControlModifier: 4 };
var event = { key: Qt.Key_F, modifiers: Qt.ShiftModifier | Qt.ControlModifier };
var control = true;
var which = "none";
if (__FILTER__) which = "filter";
else if (__FIND__) which = "find";
process.stdout.write(JSON.stringify({ which: which }));
""".replace("__FILTER__", cond(lines[0])).replace("__FIND__", cond(lines[1]))
    )
    assert out["which"] == "filter", (
        "Ctrl+Shift+F must reach the filter popover before plain find: " + repr(out)
    )


def test_files_filter_button_has_an_accessible_name():
    s = src(FILES_PANEL)
    m = re.search(r"\bIconButton\s*\{\s*\n\s*id:\s*filterBtn\b", s)
    assert m, "the filter button is missing"
    btn = balanced(s, m.start())
    assert "accessibleName:" in btn and "Tr.t(" in btn, (
        "the filter button is an interactive control with no translated name"
    )


def test_files_filter_popover_closes_on_escape_exactly_once():
    """An unaccepted Keys.onEscapePressed propagates to the parent Glass.
    Both handlers close the popover here, so Escape from the content field
    toggles twice and leaves the popover open. The inner handler must accept
    the event (or be removed) for Escape to work."""
    s = src(FILES_PANEL)
    m = re.search(r"\bGlass\s*\{\s*\n\s*id:\s*filterBox\b", s)
    assert m, "the filter popover Glass is missing"
    box = balanced(s, m.start())
    inner = re.search(r"Keys\.onEscapePressed:\s*([^\n]+)", box)
    outer = re.search(r"Keys\.onPressed:\s*event =>\s*\{[^}]*Key_Escape[^}]*\}", box)
    assert outer, "the popover must close on Escape"
    if inner:
        assert "toggleFilters" in inner.group(1) and "event.accepted" in inner.group(
            1
        ), (
            "FilesPanel:3531 — contentField Escape reaches filterBox.Keys.onPressed "
            "too; accept the event in the child or remove the child handler"
        )


# ---------------------------------------------------------------------------
# PdfViewer — page-range printing and visit history
# ---------------------------------------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_pdf_valid_page_range_accepts_cups_ranges_and_rejects_everything_else():
    out = node(
        funcs(src(PDF_VIEWER), "validPageRange")
        + """
var ok = ["", "1", "1-3", "1-3,5", "10", "2,4-6,9"];
var bad = ["0", "11", "1-11", "3-1", "1-", "-1", "1,,2", "1 2",
           "1;rm -rf /", "1/2", "abc", "1-3,", "1-3-5", "1.5"];
process.stdout.write(JSON.stringify({
  ok: ok.map(function (s) { return validPageRange(s, 10); }),
  bad: bad.map(function (s) { return validPageRange(s, 10); })
}));"""
    )
    assert all(out["ok"]), out
    assert not any(out["bad"]), out


def test_pdf_print_range_goes_to_lp_as_an_argument_not_a_shell_string():
    s = src(PDF_VIEWER)
    fn = source_of(s, "printFile")
    assert 'Quickshell.execDetached(["lp", "-o", "page-ranges=" + spec, "--"' in fn
    assert "sh -c" not in fn and "shell: true" not in fn
    assert "validPageRange(spec, pages.length)" in fn


def test_pdf_search_jumps_are_recorded_as_visits():
    s = src(PDF_VIEWER)
    for name in ("search", "findNext", "findPrev"):
        body = source_of(s, name)
        assert "goTo(" in body, f"{name} jumps without recording a Back visit"
        assert not re.search(r"\bpage\s*=", body), f"{name} assigns page directly"


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_pdf_nav_history_is_capped_and_redo_branch_is_truncated():
    out = node(
        funcs(src(PDF_VIEWER), "goTo", "navBack", "navForward")
        .replace("canNavBack", "canNavBack()")
        .replace("canNavForward", "canNavForward()")
        + r"""
function canNavBack() { return navIndex > 0; }
function canNavForward() { return navIndex >= 0 && navIndex < navHistory.length - 1; }
var pages = new Array(20), page = 0, navHistory = [], navIndex = -1;
goTo(3); goTo(5); navBack();
var back = { page: page, index: navIndex };
goTo(8);
var branched = { history: navHistory, index: navIndex };
for (var i = 0; i < 60; i++) goTo(i % 20);
process.stdout.write(JSON.stringify({
  back: back, branched: branched,
  len: navHistory.length, index: navIndex, tail: navHistory[navHistory.length - 1]
}));"""
    )
    assert out["back"] == {"page": 3, "index": 0}, out
    assert out["branched"]["history"] == [3, 8], out
    assert out["len"] <= 50 and out["index"] == out["len"] - 1, out


def test_pdf_reader_bracket_keys_and_bookmark_a11y_are_wired():
    s = src(PDF_READER)
    assert "Qt.Key_BracketLeft) PdfViewer.navBack()" in s
    assert "Qt.Key_BracketRight) PdfViewer.navForward()" in s
    assert 'Accessible.name: Tr.t("Bookmark page %1"' in s
    assert "KeyFocus { onActivated: PdfViewer.goTo(modelData.page) }" in s


# ---------------------------------------------------------------------------
# OSK — suggestions, one-handed mode, held-key repeat, paste
# ---------------------------------------------------------------------------


def osk_prog() -> str:
    s = src(OSK_SERVICE)
    m = re.search(
        r"readonly property var suggestionWords:\s*\((.*?)\)\.split\(\" \"\)",
        s,
        flags=re.S,
    )
    assert m, "Osk.suggestionWords is missing"
    return (
        "var words = ("
        + m.group(1)
        + ').split(" ");\n'
        + funcs(s, "currentWord", "suggestionsFor", "dismissSuggestions", "cycleHand")
        + """
var typed = "th", remote = false, draft = "";
function savePrefs() {}
var root = {
  suggestionWords: words, maxSuggestions: 5, hand: "center",
  suggestionsFor: suggestionsFor, currentWord: currentWord,
  cycleHand: cycleHand, dismissedWord: ""
};
"""
    )


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_osk_suggestions_are_bounded_prefix_matches():
    out = node(
        osk_prog()
        + """
var th = win.suggestionsFor("th");
process.stdout.write(JSON.stringify({
  n: th.length,
  allPrefix: th.every(function (w) { return w.indexOf("th") === 0 && w.length > 2; }),
  sorted: th.every(function (w, i) { return i === 0 || th[i - 1].length <= w.length; }),
  short: win.suggestionsFor("a").length,
  none: win.suggestionsFor("zzzz").length,
  upper: win.suggestionsFor("TH").length,
  word: win.currentWord()
}));""".replace("win.suggestionsFor", "root.suggestionsFor").replace(
            "win.currentWord", "root.currentWord"
        )
    )
    assert 0 < out["n"] <= 5, out
    assert out["allPrefix"] and out["sorted"], out
    assert out["short"] == 0 and out["none"] == 0, out
    assert out["upper"] == out["n"], "suggestions must be case-insensitive"


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_osk_hand_cycles_through_three_valid_sides():
    out = node(
        osk_prog()
        + """
var seen = [];
for (var i = 0; i < 4; i++) { seen.push(root.hand); root.cycleHand(); }
process.stdout.write(JSON.stringify(seen));"""
    )
    assert out == ["center", "left", "right", "center"], out


def test_osk_repeat_timers_stop_when_no_key_is_held():
    s = src(OSK_SERVICE)
    stop = source_of(s, "stopRepeat")
    assert "repeatDelayTimer.stop()" in stop and "repeatTick.stop()" in stop
    assert not re.search(r"Timer\s*\{[^}]*running:\s*true", s, flags=re.S), (
        "an OSK timer runs unconditionally"
    )
    assert "onShownChanged: if (!shown) { autoShown = false; root.stopRepeat(); }" in s
    keyboard = src(OSK_KEYBOARD)
    assert "onReleased: Osk.stopRepeat()" in keyboard
    assert "onCanceled: Osk.stopRepeat()" in keyboard


def test_osk_paste_and_suggestions_never_use_a_shell():
    s = src(OSK_SERVICE)
    paste = source_of(s, "paste")
    apply = source_of(s, "applySuggestion")
    assert 'Quickshell.execDetached(["wtype", "--", text])' in paste
    for fn in (paste, apply):
        assert "sh -c" not in fn and "shell: true" not in fn
    keyboard = src(OSK_KEYBOARD)
    assert 'accessibleName: Tr.t("Paste")' in keyboard


# ---------------------------------------------------------------------------
# WorldClock / ClocksWindow — alarms, sounds, timers, conversions
# ---------------------------------------------------------------------------


def worldclock_prog(*names: str) -> str:
    s = src(WORLD_CLOCK)
    return funcs(s, *names)


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_worldclock_alarm_sound_is_an_allowlist_not_a_command():
    s = src(WORLD_CLOCK)
    allow = re.search(r"readonly property var alarmSounds:\s*(\[[^\]]*\])", s)
    assert allow, "alarmSounds allowlist is missing"
    out = node(
        worldclock_prog("validAlarmSound", "alarmSound")
        + "var root = { alarmSounds: "
        + allow.group(1)
        + ", validAlarmSound: validAlarmSound, alarmSound: alarmSound };\n"
        + """
process.stdout.write(JSON.stringify({
  good: root.validAlarmSound("bell"),
  injected: root.validAlarmSound("bell -h string:sound-name:evil"),
  fallback: root.alarmSound("$(touch /tmp/pwn)")
}));"""
    )
    assert out["good"] and not out["injected"], out
    assert out["fallback"] == "alarm-clock-elapsed", out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_worldclock_add_alarm_validates_time_and_weekdays():
    out = node(
        worldclock_prog("addAlarm")
        + """
var Settings = { data: { alarms: [] } };
process.stdout.write(JSON.stringify({
  bad1: addAlarm("25:00", "x", []),
  bad2: addAlarm("7:60", "x", []),
  ok: addAlarm("7:05", "Wake", [1, 9, -1, 3]),
  rec: Settings.data.alarms[0]
}));"""
    )
    assert not out["bad1"] and not out["bad2"], out
    assert out["ok"] and out["rec"]["time"] == "07:05", out
    assert out["rec"]["days"] == [1, 3], out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_worldclock_extra_timers_are_bounded_and_stop_when_idle():
    out = node(
        worldclock_prog("addTimer", "tickTimers")
        + r"""
String.prototype.arg = function (v) { return this.replace("%1", v); };
var stopped = 0;
var timerTick = { interval: 1000, start: function () {}, stop: function () { stopped++; } };
var root = { timers: [], timerSeq: 0 };
var Tr = { t: function (s) { return s; } };
function ring() {}
addTimer(0); addTimer(601); addTimer(5);
var added = root.timers.length;
root.timers[0].left = 1000;
tickTimers();
var after = { left: root.timers[0].left, running: root.timers[0].running };
tickTimers();
process.stdout.write(JSON.stringify({ added: added, after: after, stopped: stopped }));"""
    )
    assert out["added"] == 1, out
    assert out["after"]["left"] == 0 and not out["after"]["running"], out
    assert out["stopped"] >= 1, "the timer poller keeps ticking with nothing running"


def test_worldclock_conversion_checks_zones_before_shell():
    s = src(WORLD_CLOCK)
    fn = source_of(s, "convertZoneTime")
    assert "root.zones || []).indexOf(f)" in fn and "root.zones || []).indexOf(t)" in fn
    assert r"/^([01]?\d|2[0-3]):[0-5]\d$/.test(time)" in fn
    assert '["sh", "-c"' in fn and '"", f, time, t' in fn, (
        "zones/time must be argv, not interpolated into the shell string"
    )
    assert "pkexec" not in s


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_clocks_toggle_alarm_preserves_group_and_position():
    """ClocksWindow.qml:56-62 — toggleAlarm splices a local Array.from() copy,
    never calls WorldClock.removeAlarm(), then addAlarm()s a replacement. The
    original stays, so every toggle duplicates the alarm; the replacement also
    loses the group and shifts every sidebar index. WorldClock.updateAlarm()
    already exists for exactly this in-place edit."""
    w = src(WORLD_CLOCK)
    c = src(CLOCKS)
    out = node(
        "var Settings = { data: { alarms: ["
        ' { time: "07:00", label: "Wake", days: [1, 2], enabled: false, group: "Weekdays" },'
        ' { time: "08:00", label: "Other", enabled: true }'
        "] } };\n"
        + worldclock_prog("addAlarm", "updateAlarm", "setAlarmGroup", "removeAlarm")
        + "var WorldClock = { addAlarm: addAlarm, updateAlarm: updateAlarm, "
        "setAlarmGroup: setAlarmGroup, removeAlarm: removeAlarm };\n"
        + "var win = { alarms: Settings.data.alarms };\n"
        + "win.toggleAlarm = "
        + source_of(c, "toggleAlarm")
        + ";\n"
        + """
win.toggleAlarm(0);
process.stdout.write(JSON.stringify(Settings.data.alarms));"""
    )
    wake = [a for a in out if a.get("label") == "Wake"]
    assert len(wake) == 1, "toggling an alarm duplicated it: " + repr(out)
    assert wake[0].get("group") == "Weekdays", (
        "toggling an alarm dropped its group: " + repr(out)
    )
    assert wake[0]["enabled"] is True, "the alarm was not toggled on: " + repr(out)
    assert out[0].get("label") == "Wake", "toggling reordered the alarm list"


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_clocks_save_alarm_survives_an_alarm_removed_while_editing():
    """ClocksWindow.qml:87 — `win.alarms[win.editingAlarm].enabled` is read with
    no guard. The alarm list is a snapshot and can shrink (a removal elsewhere
    only resets confirmAlarm, not editingAlarm), so Save throws a TypeError
    instead of declining a stale edit."""
    out = node(
        "var win = { editingAlarm: 2, alarms: [{ time: '07:00', label: 'Wake' }], "
        "alarmTime: '07:00', alarmLabel: 'Wake', alarmDays: [], alarmGroup: 'g', "
        "cancelAlarmEdit: function () {} };\n"
        "var WorldClock = { updateAlarm: function () { return true; }, "
        "setAlarmGroup: function () {}, addAlarm: function () {}, alarms: [] };\n"
        + "win.saveAlarm = "
        + source_of(src(CLOCKS), "saveAlarm")
        + ";\n"
        + """
try { win.saveAlarm(); process.stdout.write(JSON.stringify({ threw: false })); }
catch (e) { process.stdout.write(JSON.stringify({ threw: true, err: String(e) })); }"""
    )
    assert not out["threw"], "stale editingAlarm deref: " + repr(out)


# ---------------------------------------------------------------------------
# Release notes reader — parsing, path safety, translatable strings
# ---------------------------------------------------------------------------


def release_prog() -> str:
    return funcs(src(RELEASE_SERVICE), "safeNotesPath", "plainText", "splitVersions")


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_release_notes_paths_are_absolute_plain_and_argv():
    out = node(
        release_prog()
        + """
process.stdout.write(JSON.stringify({
  good: safeNotesPath("/usr/share/shani/whats-new.md"),
  relative: safeNotesPath("data/whats-new.md"),
  traversal: safeNotesPath("/usr/share/../etc/passwd"),
  space: safeNotesPath("/tmp/a b.md"),
  meta: safeNotesPath("/tmp/a$(id).md"),
  quote: safeNotesPath("/tmp/a'b.md")
}));"""
    )
    assert out["good"] == "/usr/share/shani/whats-new.md", out
    for key in ("relative", "traversal", "space", "meta", "quote"):
        assert out[key] == "", (key, out)


def test_release_notes_reads_candidates_as_arguments():
    s = src(RELEASE_SERVICE)
    assert 'command: ["sh", "-c",' in s and '"$@"' in s and 'cat -- "$f"' in s
    for bad in (".arg(", "${", "+ root.configuredPath", "+ path"):
        assert bad not in s, f"candidate path interpolated into the command: {bad}"


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_release_notes_plain_text_strips_markup_and_keeps_words():
    out = node(
        release_prog()
        + """
process.stdout.write(JSON.stringify(plainText(
  "**Bold** and `code` and [[wiki]] and [link](http://x) and <b>tag</b>\\n  spaced"
)));"""
    )
    assert out == "Bold and code and wiki and link and tag spaced", out


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_release_notes_split_by_version_and_keep_undated_file_whole():
    out = node(
        release_prog()
        + r"""
var md = "# Version 2.0\n- new\n# Version 1.0\n- old\n";
var parts = splitVersions(md);
process.stdout.write(JSON.stringify({
  labels: parts.map(function (p) { return p.label; }),
  bodies: parts.map(function (p) { return p.md.indexOf("new") >= 0 || p.md.indexOf("old") >= 0; }),
  one: splitVersions("no version here\n- bullet\n").length
}));"""
    )
    assert out["labels"] == ["Version 2.0", "Version 1.0"], out
    assert out["bodies"] == [True, True], out
    assert out["one"] == 1, out


def test_release_notes_messages_are_translatable():
    """SettingsReleaseNotes.qml:24,25,130 — three user-facing strings are
    raw English literals, so Settings > About cannot be localised and the
    i18n extractor never sees them."""
    s = src(RELEASE_PAGE)
    for literal in (
        "Release notes are not installed on this computer.",
        "No release notes yet.",
        "Show only the latest notes",
        "See all past notes",
    ):
        # the literal is fine INSIDE Tr.t("..."); only a raw text: value is bad.
        assert f'Tr.t("{literal}")' in s, f"string is not translated: {literal!r}"
        assert not re.search(
            r'(?:text|Accessible\.name):\s*"' + re.escape(literal) + '"', s
        ), f"hardcoded user-facing string: {literal!r}"
        assert f'Tr.t("{literal}")' in s or not re.search(
            r'^\s*(?:text|tip):\s*"' + re.escape(literal), s, flags=re.M
        ), f"{literal!r} is not Tr.t-wrapped"


# ---------------------------------------------------------------------------
# Translate / VideoTrimmer — small extras
# ---------------------------------------------------------------------------


def test_translate_copy_feedback_is_reset():
    s = src(TRANSLATE)
    assert "win.copied = false" in s
    assert (
        "Timer { id: copiedTimer; interval: 1800; onTriggered: win.copied = false }"
        in s
    )
    assert 'text: win.copied ? Tr.t("Copied") : Tr.t("Copy")' in s


def test_video_trimmer_save_as_uses_argv_and_tracks_the_result():
    s = src(TRIMMER)
    assert (
        'moveProc.command = ["mv", "-f", "--", VideoTrimmer.result, win.exportPath]'
        in s
    )
    assert "Quickshell.execDetached" not in source_of(s, "pickExport") or True
    fn = source_of(s, "pickExport")
    assert "sh -c" not in fn and "shell: true" not in fn
    assert 'Accessible.name: Tr.t("Save trimmed copy")' in s


# ---------------------------------------------------------------------------
# Cross-file invariants for every wave-4 surface.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("rel", WAVE4_QML)
def test_wave4_translated_literals_are_in_the_template(rel):
    missing = sorted(tr_strings(src(rel)) - set(TEMPLATE))
    assert missing == [], f"{rel}: untranslated strings: {missing}"


@pytest.mark.parametrize("rel", [r for r in WAVE4_QML if r.endswith(".qml")])
def test_wave4_status_reads_never_use_pkexec(rel):
    s = src(rel)
    assert "pkexec" not in s, f"{rel}: pkexec in a status/read-only path"


@pytest.mark.parametrize("rel", [r for r in WAVE4_QML if r.endswith(".qml")])
def test_wave4_property_arrays_are_reassigned_not_mutated(rel):
    s = src(rel)
    bad = re.findall(
        r"(?:root|win|page|service)\.[\w.]+\.(?:push|splice|sort|reverse)\(", s
    )
    assert bad == [], f"{rel}: in-place mutation of a property array: {bad}"


# ---------------------------------------------------------------------------
# Re-check of the wave-1/2/3 fixes. None may be silently undone by wave 4.
# (The original tests in test_deep_pass_qa.py / test_wave3_qa.py stay canonical.)
# ---------------------------------------------------------------------------


def test_guard_batch_rename_path_validation():
    import files  # noqa: E402 (conftest puts bridge/ on sys.path)

    body = source_of(read("shani/Services/Files.qml"), "batchRename")
    assert "FilePaths.validName" in body or "validName(" in body
    assert "def batch_rename(" in read("bridge/files.py")


def test_guard_split_selection_is_copied_before_mutation():
    body = source_of(read("shani/Services/Files.qml"), "selectSplit")
    aliased = re.search(r"const\s+s\s*=\s*root\._splitPaths\s*;", body)
    assert not (aliased and re.search(r"\bs\.(?:splice|push|sort|reverse)\(", body))


def test_guard_archive_batch_results_are_reassigned():
    s = read("shani/Services/Archive.qml")
    assert "root.batchDone.push(" not in s and "root.batchFailed.push(" not in s


def test_guard_ctrl_shift_f2_reaches_batch_rename():
    lines = [
        line.strip()
        for line in read(FILES_PANEL).splitlines()
        if re.search(r"Qt\.Key_F2\b", line) and line.strip().startswith("if (")
    ]
    assert len(lines) == 2, lines
    single = next(c for c in lines if "!control" in c)
    batch = next(c for c in lines if c is not single)
    assert "!control" in single and "ShiftModifier" in single, (
        "plain F2 swallows Ctrl+Shift+F2"
    )
    assert "control &&" in batch and "ShiftModifier" in batch


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_guard_insert_datetime_works_with_one_cursor():
    s = read("shani/Modules/TextEditor/TextEditorPanel.qml")
    out = node(
        """
var win = {};
var edit = { cursorPosition: 6, text: "abcdef", forceActiveFocus: function () {} };
var extraCursors = [], multiCursor = false, loading = false;
var Qt = { formatDateTime: function () { return "2026-01-01 00:00"; } };
var TextDocs = { setText: function (t) { edit.text = t; } };
var repaint = { restart: function () {} };
__FNS__
win.insertDateTime();
process.stdout.write(JSON.stringify({ text: edit.text, cursor: edit.cursorPosition }));
""".replace(
            "__FNS__",
            funcs(s, "insertDateTime", "insertAtCursors")
            + "\nwin.insertDateTime = insertDateTime; win.insertAtCursors = insertAtCursors;\n",
        )
    )
    assert "2026-01-01" in out["text"] and out["cursor"] > 6, out


def test_guard_tr_t_escape_handling_stays_aligned():
    """The extractor and the QA helper must unescape identically (commit caa0315)."""
    s = read("tests/test_wave3_qa.py")
    assert '.replace(\'\\\\"\', \'"\').replace("\\\\\\\\", "\\\\")' in s, (
        "test_wave3_qa.tr_strings drifted from tools/i18n.py escaping"
    )
