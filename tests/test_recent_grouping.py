"""Launcher recent files: grouped by day, with the app xbel actually recorded.

Researched from CuboCore's libcprime/activitesmanage.cpp (one group per day,
app name stored with the path) and corebox/corebox.cpp loadRecent() (a tree of
day groups, newest first, each child labelled with its app). Shani already has
the shared recently-used.xbel list; this only changes how the launcher reads
and shows it, so Housekeeping stays the one eraser and Settings Privacy the
one control.

Static checks hold the QML to the algorithm; the pure-Python mirror is run
against xbel fixtures and date cases a render cannot easily stage.
"""

import re
import time
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib.parse import unquote

import pytest

ROOT = Path(__file__).resolve().parent.parent
LAUNCHER = ROOT / "shani/Modules/Launcher/Launcher.qml"


@pytest.fixture(autouse=True)
def fixed_local_timezone(monkeypatch):
    """A day is local: pin the zone so the date cases mean the same everywhere."""
    monkeypatch.setenv("TZ", "UTC")
    if hasattr(time, "tzset"):
        time.tzset()
    yield
    if hasattr(time, "tzset"):
        time.tzset()


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


# ---- the QML contract ------------------------------------------------------


def test_launcher_still_reads_the_shared_xbel_store():
    # one reader for the shell (Services/RecentFiles); the launcher and the
    # overview search bind to it instead of parsing the file themselves
    q = read("shani/Services/RecentFiles.qml")
    assert '"/recently-used.xbel"' in q
    assert "watchChanges: true" in q
    assert "onFileChanged: reload()" in q
    # GTK appends: file order is oldest first, so the reader must sort (the
    # overview's own copy did not and listed the ten oldest files)
    assert "out.sort((a, b) => a.when < b.when" in q
    for surface in ("shani/Modules/Launcher/Launcher.qml", "shani/Modules/Overview/OverviewSearch.qml"):
        src = read(surface)
        assert "RecentFiles.files" in src, surface
        assert "recently-used.xbel" not in src, surface


def test_xbel_parse_keeps_when_and_the_recorded_app():
    q = read("shani/Services/RecentFiles.qml")
    # self-closing and paired bookmarks both parse; dates fall back in order
    assert r"/<bookmark[\s][^>]*>/g" in q
    assert r'href="file:\/\/([^"]+)"' in q
    assert r'\bmodified="([^"]+)"' in q
    assert r'\badded="([^"]+)"' in q
    assert r'\bvisited="([^"]+)"' in q
    # the app comes only from bookmark:application metadata - never a guess
    assert r'/<bookmark:application\b[^>]*\bname="([^"]+)"/.exec(' in q
    assert "app: app" in q
    assert "decodeURIComponent(href[1])" in q


def test_the_view_groups_by_day_without_inventing_attribution():
    q = read("shani/Modules/Launcher/Launcher.qml")
    assert "function recentDayKey(v)" in q
    assert "function recentDayLabel(key, todayKey, yesterdayKey)" in q
    assert "function groupRecent(entries, perGroup)" in q
    assert 'Tr.t("Today")' in q
    assert 'Tr.t("Yesterday")' in q
    assert 'Qt.formatDate(new Date(p[0], p[1] - 1, p[2]), "d MMM")' in q
    # undated entries land in one flat fallback group, not a fabricated day
    assert 'other = { key: "", label: Tr.t("Recent files"), items: [] }' in q
    assert "groups.concat(other ? [other] : [])" in q
    assert "win.groupRecent(win.recent.slice(0, 18), 6)" in q
    assert 'g.key ? Tr.t("Recent files") + " · " + g.label : g.label' in q
    # the flat keyboard list is still built from the sections
    assert "sections.reduce((acc, s) => acc.concat(s.items), [])" in q


def test_app_only_shows_when_metadata_gave_one():
    q = read("shani/Modules/Launcher/Launcher.qml")
    assert '(app ? app + " · " : "") + p.replace' in q
    # no second store: the shared reader never writes a recent list of its own
    reader = read("shani/Services/RecentFiles.qml")
    assert "setText" not in reader and "execDetached" not in reader


def test_erase_and_control_stay_single_owners():
    house = read("shani/Services/Housekeeping.qml")
    privacy = read("shani/Modules/Settings/SettingsPrivacy.qml")
    assert "recently-used.xbel" in house
    assert "Housekeeping.clearRecent()" in privacy
    assert "rememberRecent" in privacy


# ---- pure logic: the same algorithm, in Python -----------------------------


def parse_recent_xbel(xml):
    """Mirror of the launcher's FileView parser, in Python."""
    out = []
    for tag in re.finditer(r"<bookmark\s[^>]*>", xml):
        text = tag.group(0)
        href = re.search(r'href="file://([^"]+)"', text)
        if not href:
            continue
        when = ""
        for attr in ("modified", "added", "visited"):
            m = re.search(r"\b" + attr + r'="([^"]+)"', text)
            if m:
                when = m.group(1)
                break
        nxt = re.search(r"<bookmark\s", xml[tag.end() :])
        stop = tag.end() + nxt.start() if nxt else len(xml)
        block = xml[tag.end() : stop]
        app = re.search(r'<bookmark:application\b[^>]*\bname="([^"]+)"', block)
        path = unquote(href.group(1))
        out.append(
            {
                "path": path,
                "name": path.split("/")[-1],
                "when": when,
                "app": app.group(1) if app else "",
            }
        )
    return out


def day_key(value):
    """Mirror of recentDayKey: local calendar day of an ISO time."""
    if not isinstance(value, str):
        d = value
    else:
        try:
            d = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return ""
    if d is None:
        return ""
    if d.tzinfo is not None:
        d = d.astimezone()  # JS Date converts an ISO offset to local time
    return f"{d.year:04d}-{d.month:02d}-{d.day:02d}"


def day_label(key, today_key, yesterday_key):
    """Mirror of recentDayLabel."""
    if key == today_key:
        return "Today"
    if key == yesterday_key:
        return "Yesterday"
    y, m, d = (int(x) for x in key.split("-"))
    return date(y, m, d).strftime("%-d %b")  # Qt's "d MMM": 2 Nov


def group_recent(entries, per_group, now):
    """Mirror of groupRecent: one group per day, newest first."""
    today_key = day_key(now)
    yesterday_key = day_key(now - timedelta(days=1))
    groups = []
    by_key = {}
    other = None
    for r in entries:
        key = day_key(r["when"])
        if not key:
            if other is None:
                other = {"key": "", "label": "Recent files", "items": []}
            if len(other["items"]) < per_group:
                other["items"].append(r)
            continue
        if key not in by_key:
            by_key[key] = {
                "key": key,
                "label": day_label(key, today_key, yesterday_key),
                "items": [],
            }
            groups.append(by_key[key])
        if len(by_key[key]["items"]) < per_group:
            by_key[key]["items"].append(r)
    return groups + ([other] if other else [])


NOW = datetime(2026, 11, 24, 15, 0, 0)  # a Tuesday, local time


def entries(*specs):
    """(name, iso-when, app) → the entry shape the launcher keeps."""
    return [
        {"path": "/home/me/" + name, "name": name, "when": when, "app": app}
        for name, when, app in specs
    ]


def test_xbel_reads_app_name_from_metadata_only(tmp_path):
    xml = """<?xml version="1.0"?>
<xbel version="1.0" xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks">
  <bookmark href="file:///home/me/notes.txt" added="2026-11-24T10:00:00Z" modified="2026-11-24T11:00:00Z" visited="2026-11-24T12:00:00Z">
    <title>notes.txt</title>
    <info><metadata owner="http://www.freedesktop.org/wiki/Specifications/desktop-bookmark-spec">
      <bookmark:application name="Text Editor" exec="gedit %s" count="2" time="2026-11-24T11:00:00Z"/>
    </metadata></info>
  </bookmark>
  <bookmark href="file:///home/me/my%20report.pdf" added="2026-11-23T09:00:00Z">
    <title>my report.pdf</title>
  </bookmark>
  <bookmark href="https://example.com/nope" added="2026-11-24T10:00:00Z"/>
</xbel>"""
    got = parse_recent_xbel(xml)
    assert [e["name"] for e in got] == ["notes.txt", "my report.pdf"]
    assert got[0]["app"] == "Text Editor"
    assert got[0]["when"] == "2026-11-24T11:00:00Z"  # modified wins
    assert got[1]["path"] == "/home/me/my report.pdf"  # decoded
    assert got[1]["app"] == ""  # no metadata: no invented attribution
    assert got[1]["when"] == "2026-11-23T09:00:00Z"  # added when no modified


def test_app_metadata_does_not_leak_between_bookmarks():
    xml = """<xbel>
  <bookmark href="file:///a" modified="2026-11-24T10:00:00Z"><title>a</title></bookmark>
  <bookmark href="file:///b" modified="2026-11-24T09:00:00Z"><info>
    <bookmark:application name="Writer" exec="lowriter %s"/>
  </info></bookmark>
  <bookmark href="file:///c" modified="2026-11-24T08:00:00Z"/>
</xbel>"""
    got = parse_recent_xbel(xml)
    assert [e["app"] for e in got] == ["", "Writer", ""]
    assert [e["name"] for e in got] == ["a", "b", "c"]  # self-closing included


def test_no_app_guess_from_a_file_extension():
    got = parse_recent_xbel(
        '<xbel><bookmark href="file:///home/me/presentation.pdf" '
        'modified="2026-11-24T10:00:00Z"/></xbel>'
    )
    assert got[0]["app"] == ""  # .pdf is not an app attribution


def test_day_key_is_the_local_calendar_day_and_handles_bad_input():
    assert day_key("2026-11-24T23:30:00Z") == "2026-11-24"
    assert day_key("2026-11-25T01:30:00+05:30") == "2026-11-24"
    assert day_key(NOW) == "2026-11-24"
    assert day_key("") == ""
    assert day_key("not a date") == ""
    assert day_key(None) == ""


def test_day_labels_today_yesterday_and_older():
    assert day_label("2026-11-24", "2026-11-24", "2026-11-23") == "Today"
    assert day_label("2026-11-23", "2026-11-24", "2026-11-23") == "Yesterday"
    assert day_label("2026-11-22", "2026-11-24", "2026-11-23") == "22 Nov"
    assert day_label("2026-11-02", "2026-11-24", "2026-11-23") == "2 Nov"
    # a year boundary is not "earlier this week"
    assert day_key(NOW - timedelta(days=1)) == "2026-11-23"


def test_recent_entries_group_by_day_newest_first():
    items = entries(
        ("a.txt", "2026-11-24T14:00:00Z", "Text Editor"),
        ("b.pdf", "2026-11-24T09:00:00Z", "Document Viewer"),
        ("c.md", "2026-11-23T18:00:00Z", ""),
        ("d.png", "2026-11-22T08:00:00Z", "Image Viewer"),
    )
    groups = group_recent(items, 6, NOW)
    assert [(g["label"], [e["name"] for e in g["items"]]) for g in groups] == [
        ("Today", ["a.txt", "b.pdf"]),
        ("Yesterday", ["c.md"]),
        ("22 Nov", ["d.png"]),
    ]


def test_grouping_caps_each_day_without_dropping_undated_entries():
    items = entries(
        ("a", "2026-11-24T14:00:00Z", ""),
        ("b", "2026-11-24T13:00:00Z", ""),
        ("c", "2026-11-24T12:00:00Z", ""),
        ("undated", "", ""),
        ("bad", "garbage", "Some App"),
    )
    groups = group_recent(items, 2, NOW)
    assert [g["label"] for g in groups] == ["Today", "Recent files"]
    assert [e["name"] for e in groups[0]["items"]] == ["a", "b"]
    assert [e["name"] for e in groups[1]["items"]] == ["undated", "bad"]


def test_all_undated_entries_keep_the_flat_fallback():
    items = entries(("a", "", ""), ("b", "", ""), ("c", "nope", ""))
    groups = group_recent(items, 6, NOW)
    assert len(groups) == 1
    assert groups[0]["key"] == "" and groups[0]["label"] == "Recent files"
    assert [e["name"] for e in groups[0]["items"]] == ["a", "b", "c"]


def test_empty_recent_list_has_no_fallback_section():
    assert group_recent([], 6, NOW) == []
