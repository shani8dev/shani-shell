"""bridge/feeds.py: RSS and Atom parsing, HTML stripping, read state.

The reader's whole job is turning other people's XML into rows, so the shapes
that matter are pinned here: RSS 2.0, Atom, a description full of markup, and a
feed that cannot be fetched.
"""

import importlib.machinery
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge/feeds.py"

RSS = """<?xml version="1.0"?>
<rss version="2.0"><channel>
  <title>Shani Notes</title>
  <item>
    <title>First &amp; best</title>
    <link>https://example.com/1</link>
    <description>&lt;p&gt;Hello &lt;b&gt;world&lt;/b&gt;&lt;/p&gt;</description>
    <pubDate>Sat, 22 Nov 2026 08:00:00 +0000</pubDate>
    <guid>one</guid>
  </item>
  <item>
    <title>Second</title>
    <link>https://example.com/2</link>
    <description>Plain body</description>
    <pubDate>Fri, 21 Nov 2026 18:30:00 +0000</pubDate>
    <guid>two</guid>
  </item>
</channel></rss>"""

ATOM = """<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Notes</title>
  <entry>
    <title>Atom entry</title>
    <link rel="alternate" href="https://example.com/a"/>
    <id>urn:uuid:a</id>
    <summary>A &lt;em&gt;summary&lt;/em&gt;</summary>
    <updated>2026-11-20T12:00:00Z</updated>
  </entry>
</feed>"""


def load(tmp):
    loader = importlib.machinery.SourceFileLoader("feeds_under_test", str(BRIDGE))
    spec = importlib.util.spec_from_loader("feeds_under_test", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    mod.CONF = tmp / "feeds.json"
    mod.CACHE = tmp / "cache.json"
    return mod


def test_rss_parses_title_items_and_strips_markup(tmp_path):
    f = load(tmp_path)
    title, items = f.parse_feed(RSS.encode(), "http://example.com/feed")
    assert title == "Shani Notes"
    assert [i["title"] for i in items] == ["First & best", "Second"]
    # the description is HTML: the reader shows text
    assert items[0]["summary"] == "Hello world"
    assert items[1]["summary"] == "Plain body"
    # dates are normalised to ISO, newest sort is possible
    assert items[0]["date"].startswith("2026-11-22T08:00:00")
    assert items[0]["link"] == "https://example.com/1"


def test_atom_parses_link_and_id(tmp_path):
    f = load(tmp_path)
    title, items = f.parse_feed(ATOM.encode(), "http://example.com/atom")
    assert title == "Atom Notes"
    assert len(items) == 1
    assert items[0]["title"] == "Atom entry"
    assert items[0]["link"] == "https://example.com/a"
    assert items[0]["summary"] == "A summary"


def test_read_state_survives_and_counts(tmp_path):
    f = load(tmp_path)
    f._save(f.CONF, {"feeds": [{"title": "Shani Notes", "url": "u"}]})
    c = f.cache()
    _, items = f.parse_feed(RSS.encode(), "u")
    c["feeds"]["u"] = {"title": "Shani Notes", "items": items}
    f.save_cache(c)

    def run(*args):
        import io, contextlib

        buf = io.StringIO()
        old = sys.argv
        sys.argv = ["feeds.py"] + list(args)
        try:
            with contextlib.redirect_stdout(buf):
                f.main()
        finally:
            sys.argv = old
        return json.loads(buf.getvalue())

    assert run("list")[0]["unread"] == 2
    run("markread", "u", "one")
    listed = run("list")[0]
    assert listed["unread"] == 1
    assert listed["items"] == 2
    # a second markread is harmless, and the article is still readable
    run("markread", "u", "one")
    article = run("article", "u", "one")
    assert article["title"] == "First & best"
    assert "Hello world" in article["text"]


def test_a_broken_feed_is_reported_not_raised(tmp_path, monkeypatch):
    f = load(tmp_path)
    f._save(f.CONF, {"feeds": [{"title": "Dead", "url": "http://127.0.0.1:1/nope"}]})

    def boom(url):
        raise OSError("connection refused")

    monkeypatch.setattr(f, "fetch", boom)
    c = f.cache()
    out = f.refresh_one({"title": "Dead", "url": "http://127.0.0.1:1/nope"}, c)
    assert out["error"], "a dead feed must say so"
    assert "connection refused" in out["error"]
