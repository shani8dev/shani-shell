"""Static checks for round 2 of the SearchField migration (Software, Feeds,
Mail, Photos, Contacts). Pins that once described each window's hand-rolled
clear IconButton now point at the shared component."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


SEARCH = read("shani/Common/SearchField.qml")
SOFTWARE = read("shani/Modules/Software/SoftwareWindow.qml")
FEEDS = read("shani/Modules/Feeds/FeedsWindow.qml")
MAIL = read("shani/Modules/Mail/MailWindow.qml")
PHOTOS = read("shani/Modules/Photos/PhotosWindow.qml")
CONTACTS = read("shani/Modules/Contacts/ContactsWindow.qml")
WINDOWS = {
    "Software": SOFTWARE,
    "Feeds": FEEDS,
    "Mail": MAIL,
    "Photos": PHOTOS,
    "Contacts": CONTACTS,
}


def test_shared_field_still_supplies_clear_and_at_name():
    """One clear affordance and one AT name live in the shared component."""
    assert 'icon: "edit-clear"' in SEARCH
    assert "Accessible.name: root.label || root.placeholder" in SEARCH
    assert SEARCH.count('icon: "edit-clear"') == 1
    assert 'tip: Tr.t("Clear search")' in SEARCH
    assert 'accessibleName: Tr.t("Clear search")' in SEARCH


def test_all_five_windows_use_searchfield_not_hand_rolled_pairs():
    """Every search box is a SearchField; no window keeps its own clear icon."""
    for name, text in WINDOWS.items():
        assert "SearchField {" in text, name
        assert "edit-clear" not in text, name
        assert 'tip: Tr.t("Clear the search")' not in text, name


def test_placeholders_and_accessible_names_survive():
    """Labels become the shared field's Accessible.name; placeholders stay."""
    assert 'label: Tr.t("Find apps on Flathub")' in SOFTWARE
    assert 'placeholder: Tr.t("Find apps on Flathub")' in SOFTWARE
    assert 'label: Tr.t("Find installed apps…")' in SOFTWARE
    assert 'placeholder: Tr.t("Find installed apps…")' in SOFTWARE
    assert 'label: Tr.t("Search all articles")' in FEEDS
    assert 'placeholder: Tr.t("Search all articles…")' in FEEDS
    assert 'label: Tr.t("Search mail")' in MAIL
    assert 'placeholder: Tr.t("Search the mail…")' in MAIL
    assert 'label: Tr.t("Search photos")' in PHOTOS
    assert 'placeholder: Tr.t("Search photos…")' in PHOTOS
    assert 'label: Tr.t("Search contacts")' in CONTACTS
    assert 'placeholder: Tr.t("Search name, phone, or email")' in CONTACTS


def test_search_handlers_survive_migration():
    """onTextChanged stays on the field; onAccepted follows the input alias."""
    assert "onTextChanged: liveSearch.restart()" in SOFTWARE
    assert "function onAccepted() { if (q.text.trim())" in SOFTWARE
    assert "onTextChanged: win.installedQuery = text" in SOFTWARE
    assert (
        'onTextChanged: if (text.trim() === "" && Feeds.query !== "") Feeds.search("")'
        in FEEDS
    )
    assert "function onAccepted() { Feeds.search(articleSearch.text.trim()) }" in FEEDS
    assert (
        'onTextChanged: if (text.trim() === "" && (Mail.query !== "" || win.filterText !== "")) win.clearFilters()'
        in MAIL
    )
    assert "function onAccepted() { win.applySearch(searchField.text) }" in MAIL
    assert "onTextChanged: win.searchText = text" in PHOTOS
    assert "onTextChanged: { Contacts.query = text; Contacts.refresh(); }" in CONTACTS


def test_software_clear_button_extra_logic_moved_to_cleared():
    """The old clear button emptied results too; onCleared keeps that."""
    assert (
        'onCleared: { liveSearch.stop(); win.results = []; win.showing = ""; }'
        in SOFTWARE
    )


def test_keyboard_focus_follows_the_input_alias():
    """Shortcuts focus the inner TextInput, and typing guards read it."""
    assert "q.input.forceActiveFocus()" in SOFTWARE
    assert "q.input.activeFocus" in SOFTWARE
    assert "installedSearch.input.activeFocus" in SOFTWARE
    assert "articleSearch.input.forceActiveFocus()" in FEEDS
    assert "f === articleSearch.input" in FEEDS
    assert "searchField.input.forceActiveFocus()" in MAIL
    assert "photoSearch.input.activeFocus" in PHOTOS
    assert "searchField.input.forceActiveFocus()" in CONTACTS


def test_stale_clear_button_pins_now_point_at_the_shared_component():
    """Old per-window clear-button pins are gone; the component owns them."""
    assert 'icon: "edit-clear-all"' not in SOFTWARE
    assert 'Accessible.name: Tr.t("Find apps on Flathub")' not in SOFTWARE
    assert 'objectName: "articleSearch"' not in FEEDS
    assert SEARCH.count('icon: "edit-clear"') == 1
