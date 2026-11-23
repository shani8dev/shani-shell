"""Ranking and timeout fixes in the mail and feeds bridges.

The bridges are loaded straight from source (no installed package), and the
network-facing parts are faked, so these pin the local ranking decisions:
subject/sender weight in mail, title/feed weight in feeds, and a bounded IMAP
connect so the caller's busy flag cannot stick forever.
"""

import importlib.machinery
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(name):
    path = ROOT / ("bridge/%s.py" % name)
    loader = importlib.machinery.SourceFileLoader("fixes_" + name, str(path))
    spec = importlib.util.spec_from_loader("fixes_" + name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def test_imap_constructors_get_the_timeout(monkeypatch):
    """A server that accepts a socket but never answers must not hang Mail."""
    m = load("mail")
    seen = {}

    class FakeBox:
        def login(self, user, pw):
            pass

        def logout(self):
            pass

    def fake_ssl(host, port, **kwargs):
        seen["ssl"] = kwargs
        return FakeBox()

    def fake_plain(host, port, **kwargs):
        seen["plain"] = kwargs
        return FakeBox()

    monkeypatch.setattr(m.imaplib, "IMAP4_SSL", fake_ssl)
    monkeypatch.setattr(m.imaplib, "IMAP4", fake_plain)
    monkeypatch.setattr(m, "password", lambda: "")

    m.imap_connect({"imap": {"host": "mail.example", "port": 993, "ssl": True}})
    assert seen["ssl"]["timeout"] == m.TIMEOUT
    # a local server skips STARTTLS, so the plain constructor is the other path
    m.imap_connect({"imap": {"host": "127.0.0.1", "port": 143, "ssl": False}})
    assert seen["plain"]["timeout"] == m.TIMEOUT


def test_mailhog_search_weights_subject_then_sorts_newest(monkeypatch):
    """A fresh body hit must not outrank an older subject match."""
    m = load("mail")
    rows = [
        {
            "uid": "old-subject",
            "from": "alice@example.com",
            "subject": "quarterly report",
            "date": "Wed, 01 Jan 2020 00:00:00 +0000",
            "snippet": "",
        },
        {
            "uid": "new-body",
            "from": "bob@example.com",
            "subject": "hello there",
            "date": "Sun, 22 Nov 2026 00:00:00 +0000",
            "snippet": "a report is attached",
        },
        {
            "uid": "new-subject",
            "from": "carol@example.com",
            "subject": "report now",
            "date": "Sun, 22 Nov 2026 00:00:00 +0000",
            "snippet": "",
        },
    ]
    monkeypatch.setattr(m, "mh_messages", lambda url, folder: rows)
    out = m.mh_search("http://mailhog", "report")
    # new-subject: score 3 + newer date; old-subject: score 3 but older;
    # new-body: score 1 despite being newest
    assert [r["uid"] for r in out] == ["new-subject", "old-subject", "new-body"]


def test_feeds_search_weights_title_and_feed(tmp_path):
    """A feed-name or title hit beats a deeper, newer body hit."""
    f = load("feeds")
    f.CONF = tmp_path / "feeds.json"
    f._save(
        f.CONF,
        {
            "feeds": [
                {"title": "Report Watch", "url": "u1"},
                {"title": "Daily News", "url": "u2"},
            ]
        },
    )
    c = {
        "feeds": {
            "u1": {
                "title": "Report Watch",
                "items": [
                    {
                        "id": "feed-only",
                        "title": "Misc",
                        "summary": "nothing here",
                        "date": "2020-01-01T00:00:00+00:00",
                    }
                ],
            },
            "u2": {
                "title": "Daily News",
                "items": [
                    {
                        "id": "title-new",
                        "title": "A report today",
                        "summary": "",
                        "date": "2026-11-22T00:00:00+00:00",
                    },
                    {
                        "id": "body-new",
                        "title": "Other",
                        "summary": "mentions report deep down",
                        "date": "2026-11-22T00:00:00+00:00",
                    },
                ],
            },
        },
        "read": {},
    }
    out = f.cmd_search(c, "report")
    assert [r["id"] for r in out] == ["title-new", "feed-only", "body-new"]
    # output schema unchanged - the internal score must not leak into rows
    assert "_score" not in out[0]
    assert {"url", "feed", "id", "title", "date", "read"} <= set(out[0])
