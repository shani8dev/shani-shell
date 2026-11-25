"""A month as the calendars draw it (shani/Common/Month.js), run in node."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
COMMON = ROOT / "shani" / "Common"
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def D(y, m, d):
    return {"date": [y, m, d]}


def call(fn, *args):
    fmt = (COMMON / "Format.js").read_text().replace(".pragma library", "")
    month = "\n".join(l for l in (COMMON / "Month.js").read_text().splitlines()
                      if not l.startswith((".pragma", ".import")))
    # dates cross as {"date": [y, m, d]} so node's local time zone cannot shift them
    conv = "const A = %s.map(a => a && a.date ? new Date(a.date[0], a.date[1], a.date[2]) : a);" % json.dumps(list(args))
    prog = ("const Format = (function () {\n%s\nreturn { isoWeek };\n})();\n%s\n%s\n"
            "process.stdout.write(JSON.stringify(%s(...A)));" % (fmt, month, conv, fn))
    out = subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def test_blanks_before_the_first():
    # 2026-11-01 is a Sunday
    assert call("lead", D(2026, 10, 1), False) == 6
    assert call("lead", D(2026, 10, 1), True) == 0


def test_days_in_month_including_leap_february():
    assert call("daysIn", D(2028, 1, 1)) == 29
    assert call("daysIn", D(2026, 1, 1)) == 28
    assert call("daysIn", D(2026, 10, 1)) == 30


def test_cells_with_iso_week_numbers():
    c = call("cells", D(2026, 10, 1), False, True)
    assert c[0] == {"week": 44}                 # 2026-11-01 is in ISO week 44
    assert [x["day"] for x in c[1:8]] == [-5, -4, -3, -2, -1, 0, 1]
    days = [x["day"] for x in c if "day" in x and x["day"] > 0]
    assert days == list(range(1, 31))           # stops at the last day
    assert sum(1 for x in c if "week" in x) == 6


def test_cells_without_week_numbers_have_no_week_entries():
    c = call("cells", D(2026, 10, 1), True, False)
    assert all("day" in x for x in c)
    assert c[0] == {"day": 1}                   # Sunday-first: no blanks


def test_header_follows_the_first_weekday():
    names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    assert call("weekNames", True, names) == names
    assert call("weekNames", False, names) == names[1:] + names[:1]


def test_the_calendars_use_the_shared_month():
    for qml in ("shani/Common/DatePicker.qml", "shani/Modules/ControlCenter/Calendar.qml",
                "shani/Modules/Calendar/CalendarPanel.qml"):
        src = (ROOT / qml).read_text()
        assert "Month.weekNames(" in src, qml
        assert '["Su", "Mo"' not in src and '["Mo", "Tu"' not in src, qml
        assert "DayCell {" in src, qml
