"""Feeds gaps: next-unread, search, tags, bookmarks, mark-unread,
auto-discovery and podcast enclosures.

Everything is driven through feeds.py's command dispatcher with a private
config and cache, so the assertions cover the same argv path the shell uses.
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge/feeds.py"
SERVICE = ROOT / "shani/Services/Feeds.qml"
WINDOW = ROOT / "shani/Modules/Feeds/FeedsWindow.qml"


def load(tmp):
    loader = importlib.machinery.SourceFileLoader("feeds_gap_under_test", str(BRIDGE))
    spec = importlib.util.spec_from_loader("feeds_gap_under_test", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    mod.CONF = tmp / "feeds.json"
    mod.CACHE = tmp / "cache.json"
    return mod


def run(mod, *args):
    buf = io.StringIO()
    old = sys.argv
    sys.argv = ["feeds.py"] + list(args)
    try:
        with contextlib.redirect_stdout(buf):
            rc = mod.main()
    finally:
        sys.argv = old
    return rc, json.loads(buf.getvalue() or "null")


def item(ident, title, summary=""):
    return {
        "id": ident,
        "title": title,
        "link": "https://example.test/" + ident,
        "date": "2026-11-22T10:00:00+00:00",
        "summary": summary,
        "enclosure": {},
    }


def seed(mod, items, feeds=None, read=None, saved=None):
    feeds = feeds or [{"title": "Demo", "url": "u", "tags": []}]
    mod._save(mod.CONF, {"feeds": feeds, "interval": 0})
    mod.save_cache(
        {
            "feeds": {"u": {"title": "Demo", "items": items}},
            "read": read or {},
            "saved": saved or {},
        }
    )


def test_next_unread_skips_read_articles_and_wraps(tmp_path):
    f = load(tmp_path)
    seed(
        f,
        [item("a", "A"), item("b", "B"), item("c", "C")],
        read={"u|a": True, "u|b": True},
    )
    rc, answer = run(f, "nextunread", "u", "a")
    assert rc == 0
    assert (answer["id"], answer["title"]) == ("c", "C")
    # make a unread and c read: the next unread from c wraps to the start
    run(f, "markunread", "u", "a")
    run(f, "markread", "u", "c")
    rc, answer = run(f, "nextunread", "u", "c")
    assert answer["id"] == "a"
    _, rows = run(f, "nextunread", "u", "a")
    assert rows == {"ok": False}


def test_mark_unread_restores_the_unread_count(tmp_path):
    f = load(tmp_path)
    seed(f, [item("a", "A"), item("b", "B")], read={"u|a": True})
    _, before = run(f, "list")
    assert before[0]["unread"] == 1
    rc, answer = run(f, "markunread", "u", "a")
    assert rc == 0 and answer["ok"]
    _, after = run(f, "list")
    assert after[0]["unread"] == 2
    _, articles = run(f, "items", "u")
    assert all(a["read"] is False for a in articles)


def test_search_finds_titles_and_summaries_in_every_feed(tmp_path):
    f = load(tmp_path)
    f._save(
        f.CONF,
        {
            "feeds": [{"title": "Alpha", "url": "u"}, {"title": "Beta", "url": "v"}],
            "interval": 0,
        },
    )
    f.save_cache(
        {
            "feeds": {
                "u": {
                    "title": "Alpha",
                    "items": [item("1", "Python tips", "about code")],
                },
                "v": {
                    "title": "Beta",
                    "items": [
                        item("2", "Cooking", "python in the kitchen"),
                        item("3", "Unrelated"),
                    ],
                },
            },
            "read": {},
            "saved": {},
        }
    )
    rc, rows = run(f, "search", "python")
    assert rc == 0
    assert [r["id"] for r in rows] == ["1", "2"]
    assert rows[0]["feed"] == "Alpha" and rows[0]["url"] == "u"
    _, rows = run(f, "search", "")
    assert rows == []


def test_tags_are_saved_listed_and_shared_between_feeds(tmp_path):
    f = load(tmp_path)
    seed(
        f,
        [item("a", "A")],
        feeds=[
            {"title": "Demo", "url": "u", "tags": []},
            {"title": "Other", "url": "v", "tags": ["tech"]},
        ],
    )
    rc, answer = run(f, "settags", "u", "news, tech")
    assert rc == 0 and answer["tags"] == ["news", "tech"]
    _, rows = run(f, "list")
    assert rows[0]["tags"] == ["news", "tech"] and rows[1]["tags"] == ["tech"]
    _, tags = run(f, "tags")
    assert tags == ["news", "tech"]


def test_bookmark_toggles_and_the_saved_list_carries_its_feed(tmp_path):
    f = load(tmp_path)
    seed(f, [item("a", "A", "a summary")])
    rc, answer = run(f, "save", "u", "a")
    assert rc == 0 and answer["saved"] is True
    _, rows = run(f, "saved")
    assert len(rows) == 1 and rows[0]["id"] == "a" and rows[0]["feed"] == "Demo"
    _, articles = run(f, "items", "u")
    assert articles[0]["saved"] is True
    _, answer = run(f, "save", "u", "a")
    assert answer["saved"] is False
    _, rows = run(f, "saved")
    assert rows == []


PODCAST = """<?xml version="1.0"?>
<rss version="2.0"><channel><title>Pod</title>
  <item><title>Episode 1</title><link>https://example.test/1</link><guid>1</guid>
    <description>A talk</description>
    <enclosure url="https://example.test/1.mp3" type="audio/mpeg" length="123"/>
  </item>
</channel></rss>"""


def test_podcast_enclosure_is_parsed_and_exposed(tmp_path):
    f = load(tmp_path)
    _, items = f.parse_feed(PODCAST.encode(), "u")
    assert items[0]["enclosure"] == {
        "url": "https://example.test/1.mp3",
        "type": "audio/mpeg",
        "length": "123",
    }
    seed(f, items)
    _, rows = run(f, "items", "u")
    assert rows[0]["enclosure"]["url"] == "https://example.test/1.mp3"
    _, article = run(f, "article", "u", "1")
    assert article["enclosure"]["url"] == "https://example.test/1.mp3"


SITE = """<html><head>
  <link rel="alternate" type="application/rss+xml" title="Demo feed" href="/feed.xml">
  <link rel="stylesheet" href="/style.css">
</head><body>A site, not a feed</body></html>"""


def test_discover_finds_a_site_feed_and_add_uses_it(tmp_path, monkeypatch):
    f = load(tmp_path)

    def fake_fetch(url):
        if url == "https://site.test":
            return SITE.encode()
        raise OSError("unexpected fetch: " + url)

    monkeypatch.setattr(f, "fetch", fake_fetch)
    monkeypatch.setattr(f, "refresh_one", lambda feed, cache: {"ok": True})
    rc, found = run(f, "discover", "https://site.test")
    assert rc == 0 and found[0]["href"] == "https://site.test/feed.xml"
    assert found[0]["title"] == "Demo feed"
    assert len(found) == 1  # the stylesheet is not a feed
    rc, added = run(f, "add", "https://site.test")
    assert rc == 0 and added["ok"]
    assert f.subs()[0]["url"] == "https://site.test/feed.xml"


def test_ui_wires_the_new_feeds_commands():
    service = SERVICE.read_text()
    window = WINDOW.read_text()
    for cmd in ("nextunread", "markunread", "search", "saved", "settags", "discover"):
        assert 'run("%s"' % cmd in service or '"%s"' % cmd in service
    assert "function toggleSave(" in service and "Show read" in window
    assert "Save for later" in window and "Open episode" in window
    # both have a visible control in the window, not just a bridge verb
    assert (
        'Tr.t("Next unread article")' in window and "function nextUnread()" in service
    )
    assert (
        "win.tagFilter" in window
        and "Repeater {" in window
        and "model: Feeds.tags" in window
    )
    part = (ROOT / "dev" / "shell-parts" / "feeds.sh").read_text()
    assert "feedsNextUnread" in part and "feedsSetTags" in part
    # setting tags refreshes both the rows and the chips: neither may be dropped
    assert "property var pending: []" in service and "root.pending.shift()" in service
    assert "Qt.callLater(() => { root.refresh(); root.loadTags(); })" in service
