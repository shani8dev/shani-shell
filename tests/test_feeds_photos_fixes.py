"""Feeds search in-flight feedback and Photos text search / view-pref scope.

Both surfaces are QML, so these are static asserts over the source: the busy
guards must be on the exact bindings that showed stale results, and the Photos
filter must keep feeding the existing month grouping.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEEDS = ROOT / "shani/Modules/Feeds/FeedsWindow.qml"
PHOTOS = ROOT / "shani/Modules/Photos/PhotosWindow.qml"


def test_feeds_search_hides_empty_message_and_shows_searching_while_busy():
    t = FEEDS.read_text(encoding="utf-8")
    assert 'Feeds.busy ? Tr.t("Searching…") : Tr.t("Search results")' in t
    assert "visible: itemList.count === 0 && !Feeds.busy" in t
    assert 'Tr.t("No articles match that search")' in t


def test_photos_text_field_filters_path_and_tags_without_breaking_groups():
    t = PHOTOS.read_text(encoding="utf-8")
    assert 'property string searchText: ""' in t
    assert 'placeholder: Tr.t("Search photos…")' in t
    assert "text: win.searchText" in t and "onTextChanged: win.searchText = text" in t
    assert (
        "String(p.path).toLowerCase().indexOf(searchText.trim().toLowerCase()) >= 0"
        in t
    )
    assert (
        "tagsOf(p.path).toLowerCase().indexOf(searchText.trim().toLowerCase()) >= 0"
        in t
    )
    # the search narrows `shown`; the month grouping still reads that same list
    assert "model: win.groups" in t
    assert "const fmt = win.groupBy" in t and "group.items.push(p)" in t


def test_photos_view_prefs_limitation_is_documented_and_not_unsafely_persisted():
    t = PHOTOS.read_text(encoding="utf-8")
    for prop in (
        'property string filter: "all"',
        'property string groupBy: "month"',
        'property string sortOrder: "newest"',
    ):
        assert prop in t
    assert "window-local on purpose" in t
    assert "Common/Settings.qml's JsonAdapter" in t
    assert "reset each time Photos opens" in t
    # writing an undeclared Settings.data key is what can take the shell down
    assert "Settings.data.photos" not in t
