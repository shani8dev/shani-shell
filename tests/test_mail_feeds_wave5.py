"""Wave 5 deep pass: Mail and Feeds gaps that are *already wired*.

GAPS.md still marks Mail "Cc/Bcc; attachment preview" and Feeds "next-unread
navigation; tags/categories; search/filter" as open. Reading the current source
shows the safe subset is built: Cc/Bcc (window + Mail.qml + bridge argv), and
all four Feeds items (button/keyboard next-unread, tag chips, search, show-read)
with a single metadata store. Attachment preview is NOT here — see the report.

There is no QML runtime in this container, so the logic tests below extract the
verbatim `function ... { ... }` bodies from the two windows and run them in node
against stubbed singletons. That tests the real code: if someone edits a branch,
these fail instead of silently drifting the way a Python mirror would.

Bridge next-unread is exercised through feeds.py's real argv dispatcher with a
private cache (same trick as test_large_feeds_reader_fixes.py).
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
MAIL_WINDOW = ROOT / "shani/Modules/Mail/MailWindow.qml"
MAIL_SERVICE = ROOT / "shani/Services/Mail.qml"
FEEDS_WINDOW = ROOT / "shani/Modules/Feeds/FeedsWindow.qml"
FEEDS_SERVICE = ROOT / "shani/Services/Feeds.qml"
MAIL_BRIDGE = ROOT / "bridge/mail.py"
FEEDS_BRIDGE = ROOT / "bridge/feeds.py"

NODE = shutil.which("node")
needs_node = pytest.mark.skipif(NODE is None, reason="node is needed to run the QML JS")


def src(path):
    return path.read_text(encoding="utf-8")


def fn(source, name):
    """The verbatim `function name(...) { ... }` block, braces matched."""
    m = re.search(r"function\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{", source)
    assert m, f"no function {name}() in the QML source"
    open_brace = m.end() - 1
    depth = 0
    for k in range(open_brace, len(source)):
        if source[k] == "{":
            depth += 1
        elif source[k] == "}":
            depth -= 1
            if depth == 0:
                return source[m.start() : k + 1]
    raise AssertionError(f"unbalanced braces in {name}()")


def js(script):
    """Run a JS snippet in node and return its JSON stdout."""
    p = subprocess.run(
        [NODE, "-e", script], capture_output=True, text=True, timeout=30, check=False
    )
    assert p.returncode == 0, f"node failed:\n{p.stderr}\n--- script ---\n{script}"
    return json.loads(p.stdout)


# ---- 1. static hooks -------------------------------------------------------


def test_cc_bcc_are_wired_window_to_bridge():
    w, s, b = src(MAIL_WINDOW), src(MAIL_SERVICE), src(MAIL_BRIDGE)
    # compose shows the fields
    assert "id: ccBox" in w and "id: bccBox" in w
    assert 'label: Tr.t("Cc recipients")' in w
    assert 'label: Tr.t("Bcc recipients")' in w
    # every exit from compose carries them
    assert (
        "Mail.send(toBox.text.trim(), subBox.text, bodyBox.text, ccBox.text.trim(), bccBox.text.trim())"
        in w
    )
    assert "cc: ccBox.text.trim(), bcc: bccBox.text.trim()" in w
    assert 'ccBox.text = d.cc || "";' in w and 'bccBox.text = d.bcc || "";' in w
    # the singleton passes them as argv slots, never inside a shell string
    assert "function send(to, subject, body, cc, bcc)" in s
    assert 'if (cc || bcc) args.push(cc || "");' in s
    assert "if (bcc) args.push(bcc);" in s
    # and the bridge accepts those slots
    assert "send <to> <subject> <body> [cc] [bcc]" in b
    assert 'def send(c, to, subject, body, cc="", bcc=""):' in b
    assert 'msg["Cc"] = cc' in b


def test_feeds_next_unread_button_key_and_service_are_all_wired():
    w, s, b = src(FEEDS_WINDOW), src(FEEDS_SERVICE), src(FEEDS_BRIDGE)
    assert 'accessibleName: Tr.t("Next unread article")' in w
    assert "onClicked: Feeds.nextUnread()" in w
    assert "if (e.key === Qt.Key_J || e.key === Qt.Key_N) win.step(1);" in w
    assert (
        'function nextUnread() { if (current) run("nextunread", [current, openId]) }'
        in s
    )
    assert '} else if (what === "nextunread") {' in s
    assert 'run("nextunread", [current, openId])' in s
    assert "nextunread <url> [id]" in b
    # the button's enabled state comes from read state the bridge already sends
    assert "Feeds.feeds.some(f => f.unread > 0)" in w


def test_feeds_tag_filter_is_a_view_over_one_metadata_store():
    w, s = src(FEEDS_WINDOW), src(FEEDS_SERVICE)
    assert 'property string tagFilter: ""' in w
    assert "function feedCount(tag)" in w
    assert 'model: Feeds.feeds.filter(f => win.tagFilter === ""' in w
    # tags live on each feed and the chip list is loaded from the same bridge —
    # no second hand-written taxonomy in the window
    assert "property var feeds: []" in s  # [{ title, url, items, unread, tags }]
    assert "function tagsFor(url)" in s
    assert 'function loadTags() { run("tags", []) }' in s
    assert '} else if (what === "tags") {' in s
    assert "function onCurrentChanged()" in w
    assert "tagField.text = Feeds.tagsFor(Feeds.current);" in w


def test_wave5_controls_use_theme_tokens_and_have_names():
    w, m = src(FEEDS_WINDOW), src(MAIL_WINDOW)
    for text in (w, m):
        assert not re.search(r'color:\s*["\']?#[0-9a-fA-F]{3,8}', text)
    assert (
        "Theme.alpha(Theme.text, 0.035)" in w and "Theme.alpha(Theme.text, 0.035)" in m
    )
    assert "Theme.glassStrong" in m  # compose and source sheets are glass, not opaque
    assert "Theme.px(" in w and "Theme.px(" in m
    assert "Theme.fontScale" in w and "Theme.fontScale" in m
    # custom controls publish their own AT-SPI names; the icon buttons override
    # the tip with a real accessible name
    assert 'accessibleName: Tr.t("Next unread article")' in w
    assert 'accessibleName: Tr.t("Mark this feed read")' in w
    assert 'accessibleName: Tr.t("Refresh feeds")' in w
    assert 'Accessible.name: Tr.t("Feeds")' in w
    assert 'label: Tr.t("Search mail")' in m


# ---- 2. pure logic: Mail next-unread (the real function) -------------------


@needs_node
def test_mail_next_unread_wraps_and_skips_already_read_rows():
    body = fn(src(MAIL_WINDOW), "nextUnread")
    rows = [
        {"uid": "u1", "unread": False},
        {"uid": "u2", "unread": True},
        {"uid": "u3", "unread": False},
        {"uid": "u4", "unread": True},
    ]
    harness = f"""
var ROWS = __ROWS__;
var calls = [];
var Mail = {{ read: function(uid) {{ calls.push(uid); }} }};
var list = {{ currentIndex: __START__ }};
var win = {{ visibleMessages: function() {{ return ROWS; }} }};
{body}
nextUnread(__DIR__);
console.log(JSON.stringify({{ index: list.currentIndex, calls: calls }}));
"""

    def walk(start, direction, data=rows):
        return js(
            harness.replace("__ROWS__", json.dumps(data))
            .replace("__START__", str(start))
            .replace("__DIR__", str(direction))
        )

    # forward skips the read row; backward wraps round the end
    assert walk(0, 1) == {"index": 1, "calls": ["u2"]}
    assert walk(0, -1) == {"index": 3, "calls": ["u4"]}
    assert walk(2, 1) == {"index": 3, "calls": ["u4"]}
    # nothing unread, or no rows: no move and no read call
    all_read = [{"uid": "u1", "unread": False}, {"uid": "u2", "unread": False}]
    assert walk(0, 1, all_read) == {"index": 0, "calls": []}
    assert walk(0, 1, []) == {"index": 0, "calls": []}


# ---- 3. pure logic: Mail filter composition --------------------------------


@needs_node
def test_mail_filter_composition_keeps_operators_local_and_plain_words_server_side():
    s = src(MAIL_WINDOW)
    bodies = "\n".join(
        fn(s, name) for name in ("hasOperators", "matchesOperators", "passesFilters")
    )
    harness = f"""
var win = {{}};
{bodies}
win.hasOperators = hasOperators;
win.matchesOperators = matchesOperators;
win.passesFilters = passesFilters;
win.filterUnread = __UNREAD__;
win.filterStarred = __STARRED__;
win.filterText = __TEXT__;
console.log(JSON.stringify(win.passesFilters(__ROW__)));
"""
    row = {
        "from": "Alice <alice@example.com>",
        "subject": "Hello World",
        "snippet": "body text",
        "unread": True,
        "starred": False,
    }
    read_row = dict(row, unread=False)

    def passes(r, unread=False, starred=False, text=""):
        script = (
            harness.replace("__UNREAD__", str(unread).lower())
            .replace("__STARRED__", str(starred).lower())
            .replace("__TEXT__", json.dumps(text))
            .replace("__ROW__", json.dumps(r))
        )
        return js(script)

    assert passes(row) is True
    assert passes(read_row, unread=True) is False
    assert passes(row, starred=True) is False
    assert passes(row, text="from:alice subject:hello") is True
    assert passes(row, text="from:bob") is False
    assert passes(row, text="subject:hello from:bob") is False
    assert passes(row, text="is:unread") is True
    assert passes(read_row, text="is:unread") is False
    assert passes(row, text="is:starred") is False
    # plain words are handed to IMAP SEARCH, not re-filtered in the view
    assert passes(row, text="hello world") is True


# ---- 4. pure logic: Feeds step over the visible scope ----------------------


@needs_node
def test_feeds_step_walks_the_visible_scope_and_wraps_in_both_directions():
    s = src(FEEDS_WINDOW)
    bodies = fn(s, "visibleArticles") + "\n" + fn(s, "step")
    harness = f"""
var calls = [];
var Feeds = {{
  query: "", sorted: function(a) {{ return a; }}, searchResults: [], saved: [],
  items: [], showRead: false, current: "u", articleUrl: "", openId: "",
  openArticleAt: function(url, id) {{ calls.push(["open", url, id]); }},
  show: function(url, id) {{ calls.push(["show", url, id]); }}
}};
var win = {{ savedShown: false }};
win.visibleArticles = visibleArticles;
{bodies}
__SETUP__
step(__DIR__);
console.log(JSON.stringify(calls));
"""

    def run(setup, direction):
        return js(
            harness.replace("__SETUP__", setup).replace("__DIR__", str(direction))
        )

    feed = [{"id": "a"}, {"id": "b", "read": True}, {"id": "c"}]
    feed_setup = f'Feeds.items = {json.dumps(feed)}; Feeds.openId = "a";'
    # read rows are hidden (showRead is false), so b is skipped and c is next
    assert run(feed_setup, 1) == [["show", "u", "c"]]
    assert run(f'Feeds.items = {json.dumps(feed)}; Feeds.openId = "c";', 1) == [
        ["show", "u", "a"]
    ]
    # search has its own feed and its own rows
    search = [{"id": "x", "url": "u"}, {"id": "y", "url": "v"}]
    assert run(
        f'Feeds.query = "q"; Feeds.searchResults = {json.dumps(search)}; Feeds.openId = "x";',
        -1,
    ) == [["open", "v", "y"]]
    # the saved pile is its own scope too
    saved = [{"id": "s1", "url": "u"}, {"id": "s2", "url": "v"}]
    assert run(
        f'win.savedShown = true; Feeds.saved = {json.dumps(saved)}; Feeds.openId = "s2";',
        1,
    ) == [["open", "u", "s1"]]
    assert run("Feeds.items = [];", 1) == []


# ---- 5. pure logic: Feeds tag chips agree with the filtered list -----------


@needs_node
def test_feeds_tag_chips_count_exactly_the_rows_their_filter_shows():
    s = src(FEEDS_WINDOW)
    count = fn(s, "feedCount")
    line = re.search(r"Feeds\.feeds\.filter\((f => .*?)\)\s*$", s, re.MULTILINE)
    assert line, "the tag filter arrow is missing from the feed list model"
    arrow = line.group(1)
    feeds = [
        {"url": "a", "tags": ["tech", "news"]},
        {"url": "b", "tags": ["news"]},
        {"url": "c", "tags": []},
    ]
    harness = f"""
var Feeds = {{ feeds: {json.dumps(feeds)} }};
var win = {{ tagFilter: "" }};
{count}
var matches = {arrow};
console.log(JSON.stringify(["", "tech", "news", "sport"].map(function(t) {{
  win.tagFilter = t;
  return [t, feedCount(t), Feeds.feeds.filter(matches).length];
}})));
"""
    out = js(harness)
    assert out == [["", 3, 3], ["tech", 1, 1], ["news", 2, 2], ["sport", 0, 0]]


# ---- 6. pure logic: the bridge's next-unread uses persisted read state ----


def load(tmp):
    loader = importlib.machinery.SourceFileLoader("feeds_under_test", str(FEEDS_BRIDGE))
    spec = importlib.util.spec_from_loader("feeds_under_test", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    mod.CONF = tmp / "feeds.json"
    mod.CACHE = tmp / "cache.json"
    return mod


def run_bridge(mod, *args):
    buf = io.StringIO()
    old = sys.argv
    sys.argv = ["feeds.py"] + list(args)
    try:
        with contextlib.redirect_stdout(buf):
            rc = mod.main()
    finally:
        sys.argv = old
    return rc, json.loads(buf.getvalue() or "null")


def seed(mod, read):
    mod._save(mod.CONF, {"feeds": [{"title": "Alpha", "url": "u"}], "interval": 0})
    mod.save_cache(
        {
            "feeds": {
                "u": {
                    "title": "Alpha",
                    "items": [
                        {
                            "id": "a",
                            "title": "A",
                            "link": "https://e.test/a",
                            "date": "2026-11-22T10:00:00+00:00",
                            "summary": "",
                            "enclosure": {},
                        },
                        {
                            "id": "b",
                            "title": "B",
                            "link": "https://e.test/b",
                            "date": "2026-11-22T11:00:00+00:00",
                            "summary": "",
                            "enclosure": {},
                        },
                        {
                            "id": "c",
                            "title": "C",
                            "link": "https://e.test/c",
                            "date": "2026-11-22T12:00:00+00:00",
                            "summary": "",
                            "enclosure": {},
                        },
                    ],
                }
            },
            "read": read,
            "saved": {},
        }
    )


def test_bridge_next_unread_wraps_and_never_lands_back_on_the_current_article(tmp_path):
    f = load(tmp_path)
    seed(f, {"u|a": 1})
    # a is read: from a we get b, and from c we wrap past c and skip a to b
    assert run_bridge(f, "nextunread", "u", "a")[1]["id"] == "b"
    assert run_bridge(f, "nextunread", "u", "c")[1]["id"] == "b"
    # with b read too there is nothing left, even though c is unread (it is current)
    seed(f, {"u|a": 1, "u|b": 1})
    rc, answer = run_bridge(f, "nextunread", "u", "c")
    assert rc == 0 and answer["ok"] is False
