"""Settings batch A: About, Account, AppPermissions, Automations, Backup, Battery
adopt SettingsSection/SettingRow where shape fits, keeping labels/actions/keys."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_about_uses_settings_sections_and_keeps_content():
    s = read("shani/Modules/Settings/SettingsAbout.qml")
    assert s.count("SettingsSection {") >= 4
    assert 'title: Tr.t("This computer")' in s
    assert 'title: Tr.t("System health")' in s
    assert 'title: Tr.t("What changed")' in s
    assert 'title: Tr.t("More settings")' in s
    assert 'Tr.t("Copy details")' in s
    assert 'Tr.t("Problem report…")' in s
    assert 'Tr.t("Save report…")' in s
    assert 'Tr.t("Run check again")' in s
    assert "SettingsReleaseNotes" in s
    assert "hostnamectl" in s
    assert "facts.running = true" in s
    assert "healthProc.running = true" in s
    assert "reportProc.running = true" in s
    assert "Ui.settingsCat = modelData.cat" in s
    assert "Ui.models = true" in s
    assert "Ui.servicesApp = true" in s


def test_account_uses_settings_sections_setting_row_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsAccount.qml")
    assert s.count("SettingsSection {") >= 3
    assert "SettingRow {" in s
    assert 'title: Tr.t("Your account")' in s
    assert 'title: Tr.t("Sign in faster")' in s
    assert 'title: Tr.t("SSH keys")' in s
    assert "page.setPicture" in s
    assert "page.setName" in s
    assert 'Tr.t("Change password…")' in s
    assert "SshKeys.add(" in s
    assert "SshKeys.remove(index)" in s
    assert 'Tr.t("Add a key…")' in s
    assert "page.faceService(" in s
    assert "page.faceStart(" in s
    assert "page.faceForget()" in s
    assert "page.startEnroll()" in s
    assert "page.forgetFinger(" in s
    assert 'page.u2fDo("register")' in s
    assert 'page.u2fDo("remove")' in s


def test_app_permissions_uses_settings_section_and_setting_row_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsAppPermissions.qml")
    assert "SettingsSection {" in s
    assert "SettingRow {" in s
    assert 'title: Tr.t("App permissions")' in s
    assert "page.openApp(arow.modelData.id)" in s
    assert "page.flip(" in s
    assert "page.call(" in s
    assert "page.busNoFlag(" in s
    assert 'Tr.t("Back to what the app asked for")' in s
    assert 'Tr.t("No Flatpak apps installed.")' in s


def test_automations_uses_settings_sections_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsAutomations.qml")
    assert s.count("SettingsSection {") >= 3
    assert 'title: Tr.t("When this happens, do that")' in s
    assert 'title: Tr.t("Run a command when…")' in s
    assert 'Tr.t("Edit automation")' in s
    assert 'Tr.t("Add an automation")' in s
    assert "page.setRules(" in s
    assert "page.setHook(" in s
    assert "page.loadRule(" in s
    assert "page.resetForm()" in s
    assert "page.saveRule()" in s
    assert "page.commitRule()" in s
    assert 'Tr.t("Run my commands")' in s
    assert 'Tr.t("Add")' in s
    assert 'Tr.t("Save")' in s
    assert 'Tr.t("Cancel")' in s


def test_backup_uses_settings_section_and_setting_row_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsBackup.qml")
    assert "SettingsSection {" in s
    assert "SettingRow {" in s
    assert 'title: Tr.t("Your files")' in s
    assert 'Tr.t("Earlier versions")' in s
    assert 'Tr.t("Backups to another drive")' in s
    assert 'Tr.t("Shani Backup is not installed.")' in s
    assert "Backup.refresh()" in s
    assert "Backup.open(modelData.tab)" in s
    assert "Ui.closeAll()" in s


def test_battery_uses_settings_section_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsBattery.qml")
    assert "SettingsSection {" in s
    assert 'title: Tr.t("Battery")' in s
    assert "page.refresh()" in s
    assert "infoProc.running = true" in s
    assert "histProc.running = true" in s
    assert "hungryProc.running = true" in s
    assert 'Tr.t("Charge")' in s
    assert 'Tr.t("24 hours")' in s
    assert 'Tr.t("7 days")' in s
