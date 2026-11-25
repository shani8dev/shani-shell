"""Settings batch E: ReleaseNotes, ScreenTime, Search, Security, Sharing, Shortcuts
adopt SettingsSection/SettingRow where shape fits, keeping labels/actions/keys."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_release_notes_keeps_reader_and_actions():
    s = read("shani/Modules/Settings/SettingsReleaseNotes.qml")
    # custom reader, no SectionTitle scaffolding to replace
    assert "Services.ReleaseNotes" in s
    assert 'Tr.t("Loading…")' in s
    assert 'Tr.t("Release notes are not installed on this computer.")' in s
    assert 'Tr.t("No release notes yet.")' in s
    assert 'Tr.t("Retry")' in s
    assert "Services.ReleaseNotes.reload()" in s
    assert 'Tr.t("What changed")' in s
    assert 'Tr.t("Show only the latest notes")' in s
    assert 'Tr.t("See all past notes")' in s
    assert "page.showPast = !page.showPast" in s
    assert "notesFlick.forceActiveFocus()" in s


def test_screen_time_uses_settings_sections_and_keeps_behavior():
    s = read("shani/Modules/Settings/SettingsScreenTime.qml")
    assert s.count("SettingsSection {") >= 2
    assert 'title: Tr.t("Today, by app")' in s
    assert 'title: Tr.t("Reminders")' in s
    assert 'text: Tr.t("Screen time")' in s
    assert "page.d.screenTime = on" in s
    assert "ScreenTime.todayByApp" in s
    assert "ScreenTime.label(ScreenTime.todayTotal)" in s
    assert 'Tr.t("Remind me to take a break")' in s
    assert 'Tr.t("Daily screen time reminder")' in s
    assert "page.d.breakEveryMinutes = modelData" in s
    assert "page.d.screenLimitMinutes = modelData" in s
    assert 'visible: page.d.screenTime && page.byApp.length > 0' in s
    assert 'visible: page.d.screenTime' in s


def test_search_uses_settings_sections_and_setting_row():
    s = read("shani/Modules/Settings/SettingsSearch.qml")
    assert s.count("SettingsSection {") >= 2
    assert "SettingRow {" in s
    assert 'title: Tr.t("Search")' in s
    assert 'title: Tr.t("Launcher")' in s
    assert 'text: Tr.t("File names")' in s
    assert 'text: Tr.t("Inside documents")' in s
    assert 'text: Tr.t("By meaning")' in s
    assert 'text: Tr.t("Results from apps")' in s
    assert 'text: Tr.t("Sums and conversions")' in s
    assert 'text: Tr.t("Ignore the pointer")' in s
    assert 'text: Tr.t("Hide the navigation hints")' in s
    assert "page.d.searchFiles = on" in s
    assert "page.d.searchMeaning = on" in s
    assert "page.d.launcherIgnoreMouse = on" in s
    assert "page.d.launcherHideNavLabels = on" in s
    assert 'Tr.t("Add a folder to search")' in s
    assert 'Accessible.name: "Stop searching " + folderRow.modelData' in s
    assert "Ui.webSearches" in s


def test_security_uses_settings_sections_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsSecurity.qml")
    assert s.count("SettingsSection {") >= 8
    for title in [
        "Security", "Kernel security (LSM)", "AppArmor", "Password policy",
        "Audit", "Coredumps", "Hosts", "Sudo rules",
        "Account lockout (faillock)", "Login defaults",
    ]:
        assert f'title: Tr.t("{title}")' in s
    # key actions/ids preserved
    assert "page.savePw()" in s
    assert "page.saveHosts()" in s
    assert "page.saveSudoers()" in s
    assert "page.saveFaillock()" in s
    assert "page.saveLoginDefs()" in s
    assert "page.setAa(" in s
    assert "page.saveAuditProfile(" in s
    assert "page.saveCoredump(" in s
    assert 'Tr.t("Save policy")' in s
    assert 'Tr.t("Save hosts")' in s
    assert 'Tr.t("Save sudo rules")' in s
    assert 'Tr.t("Save faillock")' in s
    assert 'Tr.t("Save login defaults")' in s
    assert 'Tr.t("Tap again to remove rules")' in s
    assert "id: aaProfile" in s
    assert "id: hostsEdit" in s
    assert "id: sudoersEdit" in s


def test_sharing_uses_settings_sections_and_setting_row():
    s = read("shani/Modules/Settings/SettingsSharing.qml")
    assert s.count("SettingsSection {") >= 4
    assert "SettingRow {" in s
    for title in [
        "Nearby Share", "Share folders on this network", "Remote login",
        "Cast this screen", "Shared folders",
    ]:
        assert f'title: Tr.t("{title}")' in s
    assert "Nearby.setVisible(on)" in s
    assert 'Tr.t("Open Nearby Share")' in s
    assert 'Tr.t("File sharing")' in s
    assert 'Tr.t("Secure Shell (SSH)")' in s
    assert 'Tr.t("Remote desktop (Sunshine)")' in s
    assert 'Tr.t("Get pairing PIN")' in s
    assert 'Tr.t("Cast…")' in s
    assert 'Tr.t("Stop casting")' in s
    assert 'Tr.t("Stop sharing")' in s
    assert 'Accessible.name: Tr.t("Stop sharing %1", modelData.name)' in s
    assert 'page.run(["net", "usershare", "delete", modelData.name]' in s
    assert 'Tr.t("Folder to share")' in s
    assert "folderPicker.value" in s


def test_shortcuts_uses_settings_sections_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsShortcuts.qml")
    assert s.count("SettingsSection {") >= 2
    assert 'title: Tr.t("Keyboard shortcuts")' in s
    assert 'title: Tr.t("Your own shortcuts")' in s
    assert "page.favToggle(modelData)" in s
    assert "page.runNow(modelData)" in s
    assert "page.startReassign(modelData)" in s
    assert "page.removeBind(modelData)" in s
    assert "page.confirmReassign()" in s
    assert "page.cancelReassign()" in s
    assert "page.exportText()" in s
    assert "page.exportJson()" in s
    assert 'Tr.t("Copy all as text")' in s
    assert 'Tr.t("Copy all as JSON")' in s
    assert 'Tr.t("Add to your favourites")' in s
    assert 'Tr.t("Move it")' in s
