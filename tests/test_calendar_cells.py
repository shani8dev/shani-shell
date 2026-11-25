"""Day-cell event markers in the Calendar: reminder dots, holiday diamond.

CuboCore's desktop-plugins calendar paints reminders and holidays straight into
the day cells (two marker types in one cell). Shani's month grid already had a
single undifferentiated "has events" dot; this module checks the refined
markers: up to three reminder dots plus "+n", one holiday diamond, a legend,
and a name on the cell (the markers themselves are decorative).

QML cannot run under pytest here, so the wiring is asserted on source and the
actual JS helpers are extracted and executed with node against a Python
reference implementation of the same rules.
"""

import json
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PANEL = (ROOT / "shani/Modules/Calendar/CalendarPanel.qml").read_text(encoding="utf-8")

node = shutil.which("node")
node_mark = pytest.mark.skipif(node is None, reason="node is not installed")

DOT_CAP = 3  # win.cellDotCap in the panel


# ---- pure reference rules (mirrored by the QML helpers) ---------------------


def is_holiday(event):
    return "holiday" in str(event.get("calendar") or "").lower()


def reminders(events):
    return [e for e in events if not is_holiday(e)]


def holidays(events):
    return [e for e in events if is_holiday(e)]


def dot_count(events):
    return min(DOT_CAP, len(reminders(events)))


def overflow(events):
    return max(0, len(reminders(events)) - DOT_CAP)


def _events(**counts):
    """Build events at local noon on 2026-11-15 in the named calendars."""
    stamp = datetime(2026, 11, 15, 12, 0, 0).timestamp()
    out = []
    for calendar, n in counts.items():
        name = None if calendar == "none" else calendar
        for _ in range(n):
            out.append({"start": stamp, "calendar": name, "summary": name or "item"})
    return out


@pytest.mark.parametrize(
    "counts,exp_r,exp_h,exp_dots,exp_over",
    [
        ({}, 0, 0, 0, 0),
        ({"Personal": 1}, 1, 0, 1, 0),
        ({"Personal": 2}, 2, 0, 2, 0),
        ({"Personal": 3}, 3, 0, 3, 0),
        ({"Personal": 5}, 5, 0, 3, 2),
        ({"Holidays": 2}, 0, 2, 0, 0),
        ({"US Holidays": 1, "Personal": 1}, 1, 1, 1, 0),
        ({"HOLIDAY": 1, "Personal": 4}, 4, 1, 3, 1),
        ({"none": 1}, 1, 0, 1, 0),  # no calendar name is not a holiday
    ],
)
def test_marker_rules(counts, exp_r, exp_h, exp_dots, exp_over):
    events = _events(**counts)
    assert len(reminders(events)) == exp_r
    assert len(holidays(events)) == exp_h
    assert dot_count(events) == exp_dots
    assert overflow(events) == exp_over
    assert exp_dots <= DOT_CAP  # never paint more than the cap


def test_holiday_match_is_case_insensitive_and_name_only():
    assert is_holiday({"calendar": "India Holidays 2026"})
    assert is_holiday({"calendar": "holidays"})
    assert not is_holiday({"calendar": "Personal"})
    assert not is_holiday({"summary": "Holiday", "calendar": "Personal"})


# ---- the shipping QML source ------------------------------------------------


def test_helpers_are_defined_once_and_share_the_date_filter():
    for name in (
        "eventsOnDay",
        "hasEvents",
        "isHolidayEvent",
        "cellReminders",
        "cellHolidays",
        "cellDotCount",
        "cellOverflow",
        "cellA11yName",
    ):
        assert "function " + name + "(" in PANEL, name
    assert "function hasEvents(day) { return eventsOnDay(day).length > 0; }" in PANEL
    assert '/holiday/i.test(String(e.calendar || ""))' in PANEL
    assert "readonly property int cellDotCap: 3" in PANEL
    assert "Math.min(cellDotCap, cellReminders(day).length)" in PANEL
    assert "Math.max(0, cellReminders(day).length - cellDotCap)" in PANEL


def test_day_cell_paints_both_marker_types_and_no_new_store():
    assert "model: win.cellDotCount(monthCell.day)" in PANEL
    assert 'text: "+" + win.cellOverflow(monthCell.day)' in PANEL
    assert "win.cellHolidays(monthCell.day).length > 0" in PANEL
    assert (
        "color: monthCell.isSelected ? Theme.accentInk : Theme.accent" in PANEL
    )
    assert (
        "color: monthCell.isSelected ? Theme.accentInk : Theme.amber" in PANEL
    )
    assert "rotation: 45" in PANEL  # holiday diamond
    # no opaque card was introduced for the markers
    assert "id: cellMarkers" in PANEL


def test_markers_are_decorative_and_the_cell_carries_the_name():
    assert PANEL.count("Accessible.ignored: true") >= 4  # row + dot + count + diamond
    assert (
        'Accessible.name: isWeek ? Tr.t("Week %1").arg(modelData.week) : win.cellA11yName(day)'
        in PANEL
    )
    assert '", " + Tr.t("Reminders") + ": " + r' in PANEL
    assert 'Tr.t("Holiday") + ": " + h' in PANEL
    assert 'if (day <= 0) return "";' in PANEL  # blank cells stay unnamed


def test_clicking_a_marked_day_reuses_the_existing_selection():
    assert "onActivated: win.selectDay(day)" in PANEL  # Common/DayCell
    assert "onActivated: win.selectDay(day)" in PANEL
    assert "function selectDay(day) {" in PANEL


def test_legend_explains_the_markers():
    assert (
        "● " in PANEL
        and 'Tr.t("Reminders")' in PANEL
        and 'Tr.t("Holidays")' in PANEL
        and "+n " in PANEL
    )
    assert 'visible: win.view === "month"' in PANEL


# ---- execute the actual JS helpers with node --------------------------------


def _js_functions(source, names):
    parts = []
    for name in names:
        start = source.index("function " + name + "(")
        brace = source.index("{", start)
        depth = 0
        for i in range(brace, len(source)):
            if source[i] == "{":
                depth += 1
            elif source[i] == "}":
                depth -= 1
                if depth == 0:
                    parts.append(source[start : i + 1])
                    break
        else:
            raise AssertionError("unbalanced function " + name)
    return "\n".join(parts)


HELPERS = _js_functions(
    PANEL,
    [
        "eventsOnDay",
        "hasEvents",
        "isHolidayEvent",
        "cellReminders",
        "cellHolidays",
        "cellDotCount",
        "cellOverflow",
        "cellA11yName",
    ],
)


@node_mark
@pytest.mark.parametrize(
    "counts,exp_r,exp_h,exp_dots,exp_over",
    [
        ({}, 0, 0, 0, 0),
        ({"Personal": 3}, 3, 0, 3, 0),
        ({"Personal": 5}, 5, 0, 3, 2),
        ({"Holidays": 2}, 0, 2, 0, 0),
        ({"HOLIDAY": 1, "Personal": 4}, 4, 1, 3, 1),
        ({"Personal": 1, "Other": 1}, 2, 0, 2, 0),
    ],
)
def test_shipping_js_matches_the_rules(counts, exp_r, exp_h, exp_dots, exp_over):
    events = _events(**counts)
    script = """
        const Agenda = { events: %s };
        const month = new Date(2026, 10, 1);
        const cellDotCap = 3;
        const Tr = { t: s => s };
        const Qt = { formatDate: () => "DATE" };
        %s
        process.stdout.write(JSON.stringify({
            r: cellReminders(15).length,
            h: cellHolidays(15).length,
            dots: cellDotCount(15),
            over: cellOverflow(15),
            otherDay: cellReminders(16).length,
            name: cellA11yName(15),
            blank: cellA11yName(0)
        }));
    """ % (json.dumps(events), HELPERS)
    got = json.loads(subprocess.check_output([node, "-e", script], text=True))
    assert (got["r"], got["h"], got["dots"], got["over"]) == (
        exp_r,
        exp_h,
        exp_dots,
        exp_over,
    )
    assert got["otherDay"] == 0  # only events in the shown month/day count
    assert got["blank"] == ""
    expected = "DATE"
    if exp_r or exp_h:
        expected += ", has events"
    if exp_r:
        expected += ", Reminders: %d" % exp_r
    if exp_h:
        expected += ", Holiday: %d" % exp_h
    assert got["name"] == expected
