"""Static checks for the password-manager UX fixes from the pass-19 research:

duplicate detection on add, an open-in-browser action for stored site/URLs, and
a save-picker (with a friendly collision note) for GPG export.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(p):
    return (ROOT / p).read_text()


def test_add_detects_duplicates_and_offers_replace_or_copy():
    s = read("shani/Modules/Passwords/PasswordsWindow.qml")
    # the add form asks before ever calling the existing "add" bridge command
    assert "function duplicateFor(label)" in s
    assert "win.items.find(" in s
    assert "onClicked: win.saveNew()" in s
    assert "function doAdd(onDone)" in s
    assert 'win.run(["add", win.defaultCollection, label]' in s
    assert "function replaceDuplicate()" in s
    # add succeeds before the old entry is deleted — no window where a failed
    # add leaves the user with no entry at all
    assert 'win.doAdd(() => win.run(["delete", dup.path]' in s
    assert "Qt.callLater(win.doAdd)" not in s
    assert 'Tr.t("Save a copy")' in s
    assert 'Tr.t("Replace")' in s


def test_stored_url_gets_a_safe_open_action():
    s = read("shani/Modules/Passwords/PasswordsWindow.qml")
    assert "function siteUrl(i)" in s
    assert r"/^https?:\/\/\S+$/i.test(v)" in s  # only http(s), never file:/javascript:
    assert 'icon: "web-browser"' in s
    assert 'visible: win.siteUrl(prow.modelData) !== ""' in s
    assert "Qt.openUrlExternally(win.siteUrl(prow.modelData))" in s
    assert (
        'tip: Tr.t("Open site in browser")' in s
    )  # fixed, not built from untrusted text


def test_gpg_export_uses_save_picker_and_friendly_collision():
    s = read("shani/Modules/Passwords/PasswordsWindow.qml")
    p = read("bridge/passwords.py")
    assert 'mode: "save"' in s
    assert 'win.run(["gpg-export", krow.modelData.id, paths[0]]' in s
    assert 'Quickshell.env("HOME") + "/"' not in s  # no guessed path written into $HOME
    assert 'r.code === "exists"' in s
    assert 'win.error = ""' in s
    assert 'Tr.t("A file with that name already exists. Choose a different name.")' in s
    assert '"code": "exists"' in p
