"""Static checks for Feeds/Passwords window fixes not covered elsewhere.

Both surfaces are QML, so these pin the source rather than drive a runtime:
a stale search must not outlive a feed selection, Remove must not strand a
selection, an empty tag filter must still say why the list is blank, a copied
passkey id must use the same 45 s clipboard timer, and list rows must have an
accessible name.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEEDS = ROOT / "shani/Modules/Feeds/FeedsWindow.qml"
PASSWORDS = ROOT / "shani/Modules/Passwords/PasswordsWindow.qml"


def test_selecting_a_feed_or_saved_leaves_the_global_search():
    t = FEEDS.read_text(encoding="utf-8")
    assert "function leaveSearch()" in t
    assert 'articleSearch.text = ""' in t
    assert 'Feeds.search("")' in t
    assert "win.leaveSearch(); win.savedShown = false; Feeds.open(modelData.url)" in t
    assert "onClicked: { win.leaveSearch(); win.savedShown = !win.savedShown;" in t


def test_remove_clears_stale_current_so_another_feed_is_opened():
    t = FEEDS.read_text(encoding="utf-8")
    assert 'onClicked: { Feeds.remove(Feeds.current); Feeds.current = "" }' in t
    # the service only auto-opens a feed when current is empty
    assert "the service auto-opens another feed only when current is empty" in t


def test_empty_tag_filter_shows_a_message_instead_of_a_blank_list():
    t = FEEDS.read_text(encoding="utf-8")
    assert "visible: feedList.count === 0 && !Feeds.busy" in t
    assert (
        'Feeds.feeds.length === 0 ? Tr.t("No feeds yet — add one above") : Tr.t("Nothing matches")'
        in t
    )


def test_passkey_copy_arms_the_clipboard_clear_timer():
    t = PASSWORDS.read_text(encoding="utf-8")
    line = next(l for l in t.splitlines() if "Copy the key-handle id" in l)
    assert "Quickshell.clipboardText = prow.modelData.id" in line
    assert "clearTimer.restart()" in line


def test_password_rows_have_accessible_names():
    t = PASSWORDS.read_text(encoding="utf-8")
    assert t.count("Accessible.role: Accessible.ListItem") == 3
    assert "Accessible.name: prow.modelData.label" in t
    assert "Accessible.description: win.about(prow.modelData)" in t
    assert "Accessible.name: krow.modelData.uid || krow.modelData.id" in t
    assert 'Accessible.name: prow.modelData.label || Tr.t("Unnamed")' in t
