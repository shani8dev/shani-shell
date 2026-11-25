"""Static checks for the shared SearchField and the four migrated search boxes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEARCH = (ROOT / "shani/Common/SearchField.qml").read_text()
AUTH = (ROOT / "shani/Modules/Authenticator/AuthenticatorWindow.qml").read_text()
PASS = (ROOT / "shani/Modules/Passwords/PasswordsWindow.qml").read_text()
TASKS = (ROOT / "shani/Modules/Tasks/TasksWindow.qml").read_text()
CAL = (ROOT / "shani/Modules/Calendar/CalendarPanel.qml").read_text()
WINDOWS = {"Authenticator": AUTH, "Passwords": PASS, "Tasks": TASKS, "Calendar": CAL}


def test_searchfield_wraps_textfield_with_additive_defaults():
    """The reusable field wraps Common/TextField; every new property has a
    default so a plain field is unaffected."""
    assert "TextField {" in SEARCH
    assert "property alias text: field.text" in SEARCH
    assert "property alias input: field.input" in SEARCH
    assert 'property string placeholder: ""' in SEARCH
    assert "property string label: root.placeholder" in SEARCH
    assert "property bool showClear: true" in SEARCH
    assert "signal cleared()" in SEARCH
    assert "placeholder: root.placeholder" in SEARCH and "label: root.label" in SEARCH


def test_searchfield_clear_button_has_icon_visibility_refocus_and_at_name():
    """Clearing is one click: edit-clear icon, shown only with text, focuses
    the field again, announces itself, and emits cleared()."""
    assert 'icon: "edit-clear"' in SEARCH
    assert 'visible: root.showClear && root.text !== ""' in SEARCH
    assert 'tip: Tr.t("Clear search")' in SEARCH
    assert 'accessibleName: Tr.t("Clear search")' in SEARCH
    assert 'field.text = ""; field.input.forceActiveFocus(); root.cleared();' in SEARCH
    assert "Accessible.name: root.label || root.placeholder" in SEARCH


def test_four_windows_use_the_shared_field_not_hand_rolled_pairs():
    """Each window uses SearchField; the old TextField+IconButton pairs are
    gone, though other (Cancel/Delete) icon buttons legitimately remain."""
    for name, text in WINDOWS.items():
        assert "SearchField {" in text, name
        assert "onTextChanged" in text, name
    assert (
        'onClicked: { search.text = ""; search.input.forceActiveFocus(); }' not in AUTH
    )
    assert (
        'onClicked: { search.text = ""; search.input.forceActiveFocus(); }' not in PASS
    )
    assert 'icon: "edit-clear"; tip: Tr.t("Clear search")' not in TASKS
    assert 'onClicked: { searchField.text = ""; Agenda.search = ""; }' not in CAL


def test_existing_handlers_and_search_functions_survive_migration():
    """Migration moved the view, not the logic: handlers, shortcuts and the
    search functions stay exactly as they were (input alias keeps Ctrl+F)."""
    assert "onTextChanged: win.searchText = text" in AUTH
    assert "search.input.forceActiveFocus();" in AUTH
    assert "search.input.forceActiveFocus();" in PASS
    assert "onTextChanged: win.search = text" in TASKS
    assert 'function clearSearch() { searchField.text = ""; win.search = ""; }' in TASKS
    assert "searchField.forceActiveFocus();" in TASKS
    assert "onTextChanged: { if (text !== Agenda.search) Agenda.search = text; }" in CAL


def test_stale_clear_button_pins_now_point_at_the_shared_component():
    """The AT name/tip once pinned on each window's clear button now belong to
    the one component, so updating it fixes all four at once."""
    assert SEARCH.count('icon: "edit-clear"') == 1
    assert 'tip: Tr.t("Clear search")' in SEARCH
    assert 'accessibleName: Tr.t("Clear search")' in SEARCH
    for name, text in WINDOWS.items():
        assert 'tip: Tr.t("Clear search")' not in text, name
