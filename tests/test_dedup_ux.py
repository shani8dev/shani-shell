"""UX dedup: one home for the formatters several surfaces show.

The same file size, minute boundary, week number or "HH:MM" used to be
computed in a handful of services, each with its own copy. The copies drifted
(binary vs SI sizes, TB lost, whole vs one-decimal MB). Format.js is now the
single implementation; the QML functions are thin adapters that keep the
format each surface already showed people.

Static pins catch a new copy appearing in another file. Pure-logic pins run
the real Format.js under node, so a change to a format cannot slip through a
source-text check.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"
NODE = shutil.which("node") or shutil.which("nodejs")

FORMAT_JS = SHANI / "Common/Format.js"

# Who delegates which formatter, and the style that keeps their old output.
DELEGATES = {
    "Services/Files.qml": ("humanSize", "humanSize", None),
    "Services/DiskUsage.qml": ("humanSize", "humanSize", None),
    "Services/QuickLook.qml": ("humanSize", "humanSize", "si"),
    "Services/Archive.qml": ("human", "humanSize", "si"),
    "Modules/Settings/SettingsStorage.qml": ("human", "humanSize", "si"),
    "Services/FileMeta.qml": ("humanSize", "humanSize", "tb"),
    "Services/Backup.qml": ("formatBytes", "humanSize", "whole"),
    "Services/Automations.qml": ("msToNextMinute", "msToNextMinute", None),
    "Services/Focus.qml": ("msToNextMinute", "msToNextMinute", None),
    "Services/WorldClock.qml": ("msToNextMinute", "msToNextMinute", None),
    # isoWeek: the calendars reach it through Common/Month.js (tests/test_month.py)
    "Services/Appearance.qml": ("minutes", "minutes", None),
    "Services/Notifs.qml": ("minutes", "minutes", None),
}


def source_of(text, name):
    for m in re.finditer(r"function\s+" + re.escape(name) + r"\s*\(", text):
        depth = 0
        for j in range(m.end() - 1, len(text)):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    return text[m.start() : j + 1]
    raise AssertionError(f"no function {name}()")


def node_json(prog):
    assert NODE, "node is required for the pure-logic pins"
    out = subprocess.run(
        [NODE, "-e", prog], capture_output=True, text=True, timeout=30, check=True
    )
    return json.loads(out.stdout.strip().splitlines()[-1])


# ---- static: one implementation, thin adapters -------------------------------


def test_format_js_is_the_only_home_for_these_helpers():
    # Disks shows disk *capacity* (decimal, its own unit selector) - not a
    # file size, so it deliberately keeps its own formatter.
    domain_exceptions = {"Services/Disks.qml"}
    for helper in ("humanSize", "msToNextMinute", "isoWeek"):
        owners = {
            str(p.relative_to(SHANI))
            for p in SHANI.rglob("*.qml")
            if re.search(r"function\s+" + helper + r"\s*\(", p.read_text())
        }
        for rel in owners - domain_exceptions:
            body = source_of((SHANI / rel).read_text(), helper)
            assert "Format." + helper in body, f"{rel} has its own {helper}: {body}"
        assert owners - domain_exceptions == {
            rel for rel, (fn, _, _) in DELEGATES.items() if fn == helper
        }, f"a new copy of {helper} appeared"


def test_every_delegate_imports_format_and_calls_it():
    for rel, (fn, canonical, style) in DELEGATES.items():
        text = (SHANI / rel).read_text()
        assert re.search(r'import ".*Format\.js" as Format\b', text), rel
        body = source_of(text, fn)
        assert f"Format.{canonical}(" in body, f"{rel}: {fn} does not delegate"
        if style:
            assert f'"{style}"' in body, f"{rel}: {fn} lost its {style} format"
        # The adapter must be a one-liner, not a second implementation.
        assert body.count("{") == 1, f"{rel}: {fn} grew a body of its own"


def test_no_stale_local_byte_formatter_copies():
    """The 1000-unit loops and the toFixed(0) MB branch lived in five files."""
    for rel in (
        "Services/QuickLook.qml",
        "Services/Archive.qml",
        "Modules/Settings/SettingsStorage.qml",
        "Services/FileMeta.qml",
        "Services/Backup.qml",
    ):
        text = (SHANI / rel).read_text()
        assert "v /= 1000" not in text and "n /= 1024" not in text, rel
        assert "toFixed(0)" not in text, rel


# ---- pure logic: the real Format.js, executed --------------------------------

FORMAT_PROG = (
    FORMAT_JS.read_text().replace(".pragma library", "")
    + "\nvar args = __ARGS__; process.stdout.write(JSON.stringify(args.map(a => "
    "humanSize(a[0], a[1]))));"
)


def test_human_size_styles_keep_what_each_surface_showed():
    got = node_json(
        FORMAT_PROG.replace(
            "__ARGS__",
            json.dumps(
                [
                    [1000, None],
                    [1536, None],
                    [1048576, None],
                    [1000, "si"],
                    [1_000_000, "si"],
                    [1_099_511_627_776, "tb"],
                    [2_097_152, "whole"],
                ]
            ),
        )
    )
    assert got == [
        "1000 B",
        "1.5 KB",
        "1.0 MB",  # Files / Disk Usage
        "1.0 kB",
        "1.0 MB",  # Quick Look / Archives / Storage
        "1.0 TB",  # File Meta keeps TB
        "2 MB",  # Backup keeps whole MB
    ]


def test_minutes_are_shared_by_the_dark_and_dnd_schedules():
    prog = (
        FORMAT_JS.read_text().replace(".pragma library", "")
        + '\nvar x = ["07:05", "23:59", "bad", ""];'
        "process.stdout.write(JSON.stringify(x.map(minutes)));"
    )
    assert node_json(prog) == [425, 1439, -1, -1]


def test_minute_wake_is_aligned_and_never_immediate():
    prog = (
        FORMAT_JS.read_text().replace(".pragma library", "")
        + "\nvar v = msToNextMinute();"
        "process.stdout.write(JSON.stringify([v >= 1000, v <= 61250]));"
    )
    assert node_json(prog) == [True, True]


def test_iso_week_matches_the_known_year_boundary():
    prog = (
        FORMAT_JS.read_text().replace(".pragma library", "")
        + '\nvar d = ["2026-01-01", "2026-11-25", "2027-01-01"]'
        '.map(x => new Date(x + "T12:00:00"));'
        "process.stdout.write(JSON.stringify(d.map(isoWeek)));"
    )
    # 1 Jan 2026 is in ISO week 1; 25 Nov 2026 is week 48; 1 Jan 2027 week 53.
    assert node_json(prog) == [1, 48, 53]


@pytest.mark.parametrize(
    "helper", ["humanSize", "msToNextMinute", "isoWeek", "minutes"]
)
def test_format_js_declares_every_shared_helper(helper):
    assert re.search(r"function\s+" + helper + r"\s*\(", FORMAT_JS.read_text())
