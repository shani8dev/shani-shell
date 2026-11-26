"""Round 2: list rows come from shani/Common/ListRow.qml.

Static wiring checks — QML needs a running shell, so each test pins the source.
Migrated: Backup snapshots, Contacts duplicates. Feeds already used ListRow.
Skipped on purpose: the Disks disk row (partition bar, mount toggles, action
buttons) and Photos' photo tiles/filmstrip (image thumbnails) need bespoke
layouts; they keep their own Accessible names and KeyFocus instead.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def section(text, start, stop):
    return text.split(start, 1)[1].split(stop, 1)[0]


BACKUP = "shani/Modules/Backup/BackupPanel.qml"
CONTACTS = "shani/Modules/Contacts/ContactsWindow.qml"
FEEDS = "shani/Modules/Feeds/FeedsWindow.qml"
DISKS = "shani/Modules/Disks/DisksWindow.qml"
PHOTOS = "shani/Modules/Photos/PhotosWindow.qml"


def test_listrow_gives_every_row_a_name_and_keyboard_activation():
    row = read("shani/Common/ListRow.qml")
    assert "default property alias extra: tail.data" in row
    assert "Accessible.role: Accessible.ListItem" in row
    assert "Accessible.name: root.title" in row
    assert "Accessible.description: root.subtitle" in row
    assert "Accessible.selected: root.selected" in row
    assert "Accessible.onPressAction: if (root.interactive) root.clicked()" in row
    assert (
        "KeyFocus { enabled: root.interactive; columns: root.columns; onActivated: root.clicked() }"
        in row
    )


def test_backup_snapshot_rows_use_listrow_and_keep_both_restore_actions():
    p = read(BACKUP)
    row = section(
        p,
        "delegate: ListRow {",
        "Text {\n                            Layout.fillWidth: true",
    )
    assert "delegate: Rectangle" not in p
    assert "rowArea" not in row
    assert 'icon: "document-open-recent"' in row
    assert "title: modelData.displayDate" in row
    assert "subtitle: modelData.subtitle" in row
    # restore is destructive: only the explicit buttons fire it
    assert "interactive: false" in row
    assert "Restore a file" in row
    assert "Restore a folder" in row


def test_contacts_duplicate_rows_use_listrow_and_merge_on_click():
    c = read(CONTACTS)
    row = section(c, "delegate: ListRow {", "EmptyState {")
    assert "rowArea" not in row
    assert 'icon: "contact-new"' in row
    assert (
        "title: (Contacts.contacts.find(c => c.uid === modelData[0]) || {}).name" in row
    )
    assert (
        "subtitle: (Contacts.contacts.find(c => c.uid === modelData[1]) || {}).name"
        in row
    )
    assert "onClicked: Contacts.merge(modelData[0], modelData[1])" in row
    assert 'text: Tr.t("Merge")' in row
    # the main contact list keeps its own a11y/keyboard wiring
    main = section(c, "onClicked: win.showContact(modelData)", "EmptyState {")
    assert "Accessible.role: Accessible.Button" in main
    assert 'Accessible.name: modelData.name || Tr.t("Unnamed")' in main
    assert "KeyFocus { onActivated: win.showContact(modelData) }" in main


def test_feeds_rows_already_come_from_listrow():
    f = read(FEEDS)
    assert f.count("delegate: ListRow {") == 2  # feeds and articles
    assert "delegate: Rectangle" not in f
    assert "Accessible.role: Accessible.List" in f


def test_disks_bespoke_row_is_named_keyboard_reachable_and_document():
    w = read(DISKS)
    assert "shortcut: a disk row owns a partition bar" in w
    row = section(w, "delegate: Rectangle {", "// ---- empty / error states")
    assert "Accessible.role: Accessible.ListItem" in row
    assert 'Accessible.name: (modelData.model || modelData.name || "")' in row
    assert (
        "KeyFocus { onActivated: win.selectedDisk = win.selectedDisk === modelData ? null : modelData }"
        in row
    )


def test_photos_tiles_keep_their_keyboard_focus_and_filmstrip_gains_it():
    s = read(PHOTOS)
    assert "columns: monthCol.cols   // Up / Down jump a row of the grid" in s
    assert 'Accessible.name: tile.modelData.path.split("/").pop()' in s
    assert (
        "KeyFocus {\n"
        "                            name: Accessible.name\n"
        "                            onActivated: Viewer.open(modelData.path)\n"
        "                        }" in s
    )
    assert (
        'Accessible.name: Tr.t("Filmstrip photo %1", modelData.path.split("/").pop())'
        in s
    )
