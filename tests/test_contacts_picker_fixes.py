"""Static checks for Contacts/FilePicker gaps not listed in docs/GAPS*.md.

Both surfaces are QML layer/window code that needs a running shell to drive, so
each test asserts the source carries the exact wiring rather than exercising QML.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTACTS = ROOT / "shani/Modules/Contacts/ContactsWindow.qml"
PICKER = ROOT / "shani/Modules/FilePicker/FilePickerPanel.qml"


def read(path):
    return path.read_text(encoding="utf-8")


def section(src, start, stop):
    """The text between two landmarks, so a change cannot hide elsewhere."""
    return src.split(start, 1)[1].split(stop, 1)[0]


def test_reopening_contacts_clears_the_armed_delete():
    t = read(CONTACTS)
    opening = [
        l
        for l in t.splitlines()
        if "onVisibleChanged:" in l and "Contacts.refresh()" in l
    ]
    assert len(opening) == 1
    # a two-tap delete armed before closing must not survive the reopen
    assert 'win.confirmDelete = ""' in opening[0]
    assert "Timer { id: deleteTimer; interval: 4000" in t


def test_vcard_import_consumes_every_picked_path():
    t = read(CONTACTS)
    pick = section(t, "function pickImport() {", "// Esc:")
    assert "multiple: true" in pick
    assert "paths.forEach(p => Contacts.importFile(p))" in pick
    # the old code dropped all but the first selection
    assert "paths[0]" not in pick


def test_contact_rows_are_reachable_by_keyboard_and_screen_reader():
    t = read(CONTACTS)
    row = section(t, "onClicked: win.showContact(modelData)", "EmptyState {")
    assert "Accessible.role: Accessible.Button" in row
    assert 'Accessible.name: modelData.name || Tr.t("Unnamed")' in row
    assert "Accessible.onPressAction: win.showContact(modelData)" in row
    assert "KeyFocus { onActivated: win.showContact(modelData) }" in row


def test_filtered_empty_folder_says_no_matches_not_empty():
    t = read(PICKER)
    assert (
        'title: FilePicker.filters.length > 0 ? Tr.t("No matching files") '
        ': Tr.t("This folder is empty")' in t
    )
    assert 'Tr.t("No %1 files here").arg(FilePicker.filters.join(", "))' in t


def test_multi_select_footer_reports_selection_count():
    t = read(PICKER)
    assert "FilePicker.multiple && FilePicker.selected.length > 0" in t
    assert (
        'Tr.t("%1 of %2 selected").arg(FilePicker.selected.length).arg(list.count)' in t
    )
