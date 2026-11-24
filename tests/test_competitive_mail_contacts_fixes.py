"""Static checks for the competitive-research fixes in Mail and Contacts.

Competitors (Thunderbird, GNOME Evolution/Contacts, Apple Mail) all offer a
sortable message list, bulk mark-read, visible star state, a favourites view
and one-click copy of a phone number or email address. These tests pin the
QML wiring for those five low-risk gaps; no QML runtime is available here.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAIL = (ROOT / "shani/Modules/Mail/MailWindow.qml").read_text()
CONTACTS = (ROOT / "shani/Modules/Contacts/ContactsWindow.qml").read_text()


def test_mail_message_list_can_be_sorted_by_date_from_and_subject():
    """Thunderbird/Apple Mail let you sort the message list by any column."""
    assert 'property string sortField: "date"' in MAIL
    assert "property bool sortNewest: true" in MAIL
    assert "function visibleMessages()" in MAIL
    assert "model: win.visibleMessages()" in MAIL
    # a chip per sort column plus a direction toggle
    assert (
        '[["date", Tr.t("Date")], ["from", Tr.t("From")], ["subject", Tr.t("Subject")]]'
        in MAIL
    )
    assert "win.sortNewest = !win.sortNewest" in MAIL


def test_mail_mark_all_read_and_star_state_in_list():
    """Evolution has Mark All Read; Thunderbird shows a starred column."""
    assert "function markAllRead()" in MAIL
    assert "Mail.messages.forEach(m => { if (m.unread) Mail.markRead(m.uid); })" in MAIL
    assert 'text: Tr.t("Mark all read")' in MAIL
    assert "onClickeded: win.markAllRead()" not in MAIL  # no typo in the handler
    assert "onClicked: win.markAllRead()" in MAIL
    assert 'trailing: modelData.starred ? "★" : ""' in MAIL


def test_contacts_favourites_filter_uses_the_star_flag():
    """GNOME Contacts has a Favourites view; ours only had a star icon."""
    assert "function visibleContacts()" in CONTACTS
    assert "Contacts.favoriteContacts" in CONTACTS
    assert 'Tr.t("Favourites")' in CONTACTS
    assert "Contacts.allGroups.slice(1)" in CONTACTS
    assert "model: win.visibleContacts()" in CONTACTS


def test_contacts_detail_sheet_can_copy_number_and_address():
    """Evolution/Apple Contacts copy a number or address in one click."""
    assert "function copyText(value)" in CONTACTS
    assert "Quickshell.clipboardText = s" in CONTACTS
    assert 'tip: Tr.t("Copy number")' in CONTACTS
    assert "win.copyText(modelData.number)" in CONTACTS
    assert 'tip: Tr.t("Copy address")' in CONTACTS
    assert "win.copyText(modelData.address)" in CONTACTS
    assert 'text: Tr.t("Copy name")' in CONTACTS
    assert "win.copyText(detailCol.c.name)" in CONTACTS


def test_contacts_empty_state_explains_the_favourites_filter():
    """A filtered-to-empty view must say why, not just 'No contacts yet'."""
    assert (
        'win.groupFilter === Tr.t("Favourites") ? Tr.t("No favourites yet")' in CONTACTS
    )
    assert 'Tr.t("Star a contact to see it here")' in CONTACTS
