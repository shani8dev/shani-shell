"""The large Feeds reader upgrade: reader modes, sort, keyboard reading,
scope-safe saved/read state, tag groups and accessibility.

Two levels of proof. The QML changes are pinned as static assertions on the
exact bindings and branches (no QML runtime exists in this container), and the
two bridge facts the view relies on — a scoped `markall`, and a saved row that
carries its feed URL — are driven through feeds.py's real argv dispatcher with
a private config and cache.
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICE = ROOT / "shani/Services/Feeds.qml"
WINDOW = ROOT / "shani/Modules/Feeds/FeedsWindow.qml"
BRIDGE = ROOT / "bridge/feeds.py"


def svc():
    return SERVICE.read_text(encoding="utf-8")


def win():
    return WINDOW.read_text(encoding="utf-8")


# ---- bridge helpers (same argv path the shell uses) -----------------------


def load(tmp):
    loader = importlib.machinery.SourceFileLoader(
        "feeds_reader_under_test", str(BRIDGE)
    )
    spec = importlib.util.spec_from_loader("feeds_reader_under_test", loader)
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


def item(ident, title):
    return {
        "id": ident,
        "title": title,
        "link": "https://example.test/" + ident,
        "date": "2026-11-22T10:00:00+00:00",
        "summary": "a summary",
        "enclosure": {},
    }


def seed_two(mod):
    """Two subscribed feeds, one unread article in each."""
    mod._save(
        mod.CONF,
        {
            "feeds": [{"title": "Alpha", "url": "u"}, {"title": "Beta", "url": "v"}],
            "interval": 0,
        },
    )
    mod.save_cache(
        {
            "feeds": {
                "u": {"title": "Alpha", "items": [item("a", "From Alpha")]},
                "v": {"title": "Beta", "items": [item("b", "From Beta")]},
            },
            "read": {},
            "saved": {},
        }
    )


# ---- 1. reader modes ------------------------------------------------------


def test_reader_modes_are_window_local_and_drive_article_typography():
    s, w = svc(), win()
    assert 'property string readerMode: "full"' in s
    assert (
        'function setReaderMode(mode) { root.readerMode = mode === "compact" ? "compact" : "full" }'
        in s
    )
    # the two choices and every typography branch are bound, not one-shot writes
    assert 'onClicked: Feeds.setReaderMode("compact")' in w
    assert 'onClicked: Feeds.setReaderMode("full")' in w
    assert 'selected: Feeds.readerMode === "compact"' in w
    assert 'selected: Feeds.readerMode === "full"' in w
    assert 'spacing: Theme.px(Feeds.readerMode === "compact" ? 6 : 10)' in w
    assert 'Theme.px(Feeds.readerMode === "compact" ? 16 : 20) * Theme.fontScale' in w
    assert 'Theme.px(Feeds.readerMode === "compact" ? 12 : 14) * Theme.fontScale' in w
    # mode is view state: no bridge command carries it
    assert 'run("readermode"' not in s


# ---- 2. sort control ------------------------------------------------------


def test_sort_control_orders_feed_saved_and_search_without_touching_the_cache():
    s, w = svc(), win()
    assert 'property string sortOrder: "newest"' in s
    assert (
        'function setSort(order) { root.sortOrder = order === "oldest" || order === "title" ? order : "newest" }'
        in s
    )
    # the three-way sort: title is A→Z, oldest is forward dates, newest is reversed
    assert (
        'root.sortOrder === "title" ? String(row.title || "") : String(row.date || "")'
        in s
    )
    assert 'return root.sortOrder === "newest" ? list.reverse() : list;' in s
    assert "const list = Array.isArray(items) ? items.slice() : [];" in s
    # all three models go through it, and the chips cover all three orders
    assert 'model: Feeds.query !== "" ? Feeds.sorted(Feeds.searchResults)' in w
    assert ": win.savedShown ? Feeds.sorted(Feeds.saved)" in w
    assert ": Feeds.sorted(Feeds.items.filter(i => Feeds.showRead || !i.read))" in w
    for label, order in (
        ("Newest", "newest"),
        ("Oldest", "oldest"),
        ("Title", "title"),
    ):
        assert '[Tr.t("%s"), "%s"]' % (label, order) in w
    assert "onClicked: Feeds.setSort(modelData[1])" in w
    # the auto-opened first article follows the same order as the visible list
    assert "const first = root.sorted(root.items)[0];" in s


# ---- 3. keyboard reading --------------------------------------------------


def test_keyboard_shortcuts_walk_the_visible_list_and_do_not_eat_typing():
    w = win()
    # single letters are only reading shortcuts when no field has focus
    assert "function isEditing()" in w
    for name in ("feedEdit", "articleSearch", "tagEdit"):
        assert 'f.objectName === "%s"' % name in w
    assert "if (win.isEditing()) return;" in w
    # j/n forward, k/p back, r read toggle, f save, Escape unwinds, Ctrl+F searches
    assert "if (e.key === Qt.Key_J || e.key === Qt.Key_N) win.step(1);" in w
    assert "else if (e.key === Qt.Key_K || e.key === Qt.Key_P) win.step(-1);" in w
    assert "else if (e.key === Qt.Key_R) win.toggleRead();" in w
    assert (
        "else if (e.key === Qt.Key_F) Feeds.toggleSave(Feeds.articleUrl || Feeds.current, Feeds.openId);"
        in w
    )
    assert 'if (Feeds.query !== "") win.leaveSearch();' in w
    assert "else if (win.savedShown) win.savedShown = false;" in w
    assert "if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_F)" in w
    assert "articleSearch.forceActiveFocus();" in w
    assert "if (handled) e.accepted = true;" in w
    # the focusable host exists, so keys reach it before any pane
    assert "focus: true" in w


def test_step_uses_the_articles_own_feed_and_wraps_in_both_directions():
    w = win()
    assert "function visibleArticles()" in w
    assert 'if (Feeds.query !== "") return Feeds.sorted(Feeds.searchResults);' in w
    assert "if (win.savedShown) return Feeds.sorted(Feeds.saved);" in w
    assert (
        "return Feeds.sorted(Feeds.items.filter(i => Feeds.showRead || !i.read));" in w
    )
    assert "if (!rows.length) return;" in w
    assert "(idx + delta + rows.length) % rows.length" in w
    assert "idx < 0 ? (delta > 0 ? 0 : rows.length - 1)" in w
    assert "Feeds.openArticleAt(row.url || Feeds.current, row.id);" in w
    assert "else Feeds.show(Feeds.current, row.id);" in w


def test_r_key_toggles_read_from_the_visible_row_not_from_a_stale_flag():
    w = win()
    assert "function toggleRead()" in w
    assert "if (!Feeds.openId) return;" in w
    assert "win.visibleArticles().filter(a => a.id === Feeds.openId)[0]" in w
    assert "if (row && row.read) Feeds.markUnread(url, Feeds.openId);" in w
    assert "else Feeds.markRead(url, Feeds.openId);" in w


# ---- 4. mark-all-read scope -----------------------------------------------


def test_mark_all_read_never_wipes_every_feed_on_an_empty_scope():
    s, w = svc(), win()
    assert "function markAll(url)" in s
    assert "const target = url || root.current;" in s
    assert 'if (!target) { root.note = Tr.t("Pick a feed first"); return; }' in s
    assert 'run("markall", [target], false);' in s
    # the bridge's no-argument form is no longer reachable from the header
    assert "onClicked: Feeds.markAll(Feeds.current)" in w
    assert 'enabled: Feeds.current !== "" && !win.savedShown && Feeds.query === ""' in w


def test_bridge_markall_scopes_to_one_feed_but_can_mark_all_when_asked(tmp_path):
    f = load(tmp_path)
    seed_two(f)
    rc, answer = run(f, "markall", "u")
    assert rc == 0 and answer["marked"] == 1
    _, rows = run(f, "list")
    assert [r["unread"] for r in rows] == [0, 1]
    # the global form still exists in the bridge — this is why the service
    # refuses to call it with an empty scope
    rc, answer = run(f, "markall")
    assert rc == 0 and answer["marked"] == 1
    _, rows = run(f, "list")
    assert [r["unread"] for r in rows] == [0, 0]


# ---- 5. saved / read-later scope ------------------------------------------


def test_save_and_read_actions_use_the_open_articles_own_feed():
    s, w = svc(), win()
    assert 'property string articleUrl: ""' in s
    assert (
        'function show(url, id) { articleUrl = url; openId = id; run("article", [url, id]) }'
        in s
    )
    assert "Feeds.toggleSave(Feeds.articleUrl || Feeds.current, Feeds.openId)" in w
    assert "Feeds.markUnread(Feeds.articleUrl || Feeds.current, Feeds.openId)" in w
    # a read or save change must refresh every view that can show the article
    assert "root.savedArticles();" in s
    assert "if (root.query) root.search(root.query);" in s


def test_bridge_saved_rows_and_markunread_carry_the_feed_url(tmp_path):
    f = load(tmp_path)
    seed_two(f)
    assert run(f, "save", "v", "b")[1]["saved"] is True
    _, rows = run(f, "saved")
    assert len(rows) == 1 and rows[0]["id"] == "b"
    assert rows[0]["url"] == "v" and rows[0]["feed"] == "Beta"
    _, answer = run(f, "markunread", "v", "b")
    assert answer["url"] == "v" and answer["id"] == "b"


# ---- 6. tag prefill / groups ----------------------------------------------


def test_tag_field_is_prefilled_for_the_feed_that_just_opened():
    s, w = svc(), win()
    assert "function tagsFor(url)" in s
    assert 'return f && f.tags ? f.tags.join(", ") : "";' in s
    assert "target: Feeds" in w
    assert "function onCurrentChanged()" in w
    assert (
        'if (tagField && Feeds.current !== "") tagField.text = Feeds.tagsFor(Feeds.current);'
        in w
    )
    assert 'objectName: "tagEdit"' in w


def test_tag_groups_show_how_many_feeds_they_hold():
    w = win()
    assert "function feedCount(tag)" in w
    assert 'f => tag === "" || (f.tags || []).indexOf(tag) >= 0' in w
    assert 'text: Tr.t("All") + "  " + win.feedCount("")' in w
    assert 'text: modelData + "  " + win.feedCount(modelData)' in w


# ---- 7. unread counts -----------------------------------------------------


def test_unread_counts_are_shown_in_the_header_and_beside_each_feed():
    s, w = svc(), win()
    assert "function unreadTotal()" in s
    assert "n + (f.unread || 0)" in s
    assert 'text: Tr.t("%1 unread", Feeds.unreadTotal())' in w
    assert "color: Feeds.unreadTotal() > 0 ? Theme.accent : Theme.faint" in w
    assert 'trailing: modelData.unread > 0 ? String(modelData.unread) : ""' in w


def test_opening_an_article_refreshes_the_unread_count_and_other_views():
    s = svc()
    assert '} else if (what === "markread") {' in s
    branch = s[
        s.index('} else if (what === "markread") {') : s.index(
            '} else if (what === "status") {'
        )
    ]
    assert "root.refresh();" in branch
    assert "root.savedArticles();" in branch
    assert "if (root.query) root.search(root.query);" in branch
    # the article handler is what triggers it
    assert "root.markRead(root.current, root.openId);" in s


# ---- 8. search ------------------------------------------------------------


def test_search_reports_its_result_count_and_is_a_steppable_scope():
    w = win()
    assert 'text: Tr.t("%1 results", itemList.count)' in w
    assert 'visible: Feeds.query !== "" && !Feeds.busy' in w
    # the old busy wording is kept while a search is in flight
    assert 'Feeds.busy ? Tr.t("Searching…") : Tr.t("Search results")' in w
    assert "visible: itemList.count === 0 && !Feeds.busy" in w
    assert 'Tr.t("No articles match that search")' in w


# ---- 9. empty / error / offline -------------------------------------------


def test_empty_error_and_offline_states_are_distinct():
    w = win()
    # error text is a named static text; offline is its own line in two panes
    assert 'visible: Feeds.note !== ""' in w
    assert "Accessible.role: Accessible.StaticText" in w
    assert "visible: !Net.online" in w
    assert 'Tr.t("Offline — showing cached articles")' in w
    assert 'text: Tr.t("Offline")' in w
    # the three empty lists still say three different things
    assert 'Tr.t("No feeds yet — add one above") : Tr.t("Nothing matches")' in w
    assert 'Tr.t("Nothing saved yet")' in w
    assert 'Tr.t("Nothing in this feed yet")' in w
    assert 'Tr.t("Pick a feed first")' in svc()


# ---- 10. accessibility names ----------------------------------------------


def test_reader_controls_and_lists_have_accessible_names_and_roles():
    w = win()
    assert w.count("Accessible.role: Accessible.List") == 2
    assert 'Accessible.name: Tr.t("Feeds")' in w
    assert 'Accessible.name: Tr.t("Articles")' in w
    assert "Accessible.role: Accessible.Heading" in w
    assert "Accessible.name: Feeds.articleTitle" in w
    assert 'accessibleName: Tr.t("Next unread article")' in w
    assert 'accessibleName: Tr.t("Mark this feed read")' in w
    assert 'accessibleName: Tr.t("Refresh feeds")' in w
    assert 'label: Tr.t("Feed address")' in w
    assert 'label: Tr.t("Search all articles")' in w
    assert 'label: Tr.t("Tags for this feed")' in w


# ---- 11. preserved contracts ---------------------------------------------


def test_earlier_feeds_contracts_still_hold_after_the_upgrade():
    w, s = win(), svc()
    assert "function leaveSearch()" in w
    assert "win.leaveSearch(); win.savedShown = false; Feeds.open(modelData.url)" in w
    assert "onClicked: { win.leaveSearch(); win.savedShown = !win.savedShown;" in w
    assert 'onClicked: { Feeds.remove(Feeds.current); Feeds.current = "" }' in w
    assert "function toggleSave(" in s and "Show read" in w
    assert "Save for later" in w and "Open episode" in w
