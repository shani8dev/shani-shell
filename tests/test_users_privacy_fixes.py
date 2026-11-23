"""Static checks for the Users / Account / Privacy safety fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_change_password_warns_about_keyring_relink():
    s = read("shani/Modules/Settings/SettingsAccount.qml")
    assert "keyring that keeps saved passwords" in s
    assert "Passwords and Keys and change the keyring password" in s
    assert s.index("does not change the keyring") < s.index('Tr.t("Change password…")')


def test_new_user_password_is_typed_twice_before_it_is_set():
    s = read("shani/Modules/Settings/SettingsUsers.qml")
    assert "id: pw1" in s and "id: pw2" in s
    assert s.count("secret: true") >= 2
    assert 'pw1.text !== "" && pw1.text === pw2.text' in s
    assert (
        'page.act("user-password", { username: urow.modelData.name, password: pw1.text })'
        in s
    )
    assert 'Tr.t("The two passwords do not match.")' in s


def test_guest_switch_warns_that_switching_off_deletes_the_account():
    s = read("shani/Modules/Settings/SettingsUsers.qml")
    assert "turning this off deletes the Guest account and its files" in s
    assert 'Tr.t("Guest")' in s


def test_privacy_has_a_location_master_switch_and_no_stale_claim():
    s = read("shani/Modules/Settings/SettingsPrivacy.qml")
    assert "the shell does not locate this computer" not in s
    assert 'Tr.t("Location services")' in s
    assert "checked: page.d.useLocation" in s
    assert "Location.refresh()" in s


def test_privacy_destructive_buttons_need_a_second_tap():
    s = read("shani/Modules/Settings/SettingsPrivacy.qml")
    assert "property string confirming" in s
    assert "function confirmThen" in s
    for kind, call in (
        ("recent", "Housekeeping.clearRecent()"),
        ("trash", "Housekeeping.emptyTrash()"),
        ("clipboard", "Clipboard.wipe()"),
    ):
        assert 'page.confirmThen("%s", () => %s)' % (kind, call) in s
        assert "onClicked: %s" % call not in s
