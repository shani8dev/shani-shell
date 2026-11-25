"""Settings batch F: Startup, SystemRestore, Ups, Users, WallpaperStyle, Windows
adopt SettingsSection/SettingRow where shape fits, keeping labels/actions/keys."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_startup_uses_settings_sections_and_setting_rows_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsStartup.qml")
    assert s.count("SettingsSection {") >= 3
    assert s.count("SettingRow {") >= 1
    assert 'title: Tr.t("Apps open when you signed out")' in s
    assert 'title: Tr.t("Sessions")' in s
    assert 'title: Tr.t("Startup apps")' in s
    assert "page.d.reopenApps" in s
    assert "Sessions.saveCurrent(sessionName.text)" in s
    assert "Sessions.restore(page.confirmName)" in s
    assert "Sessions.remove(page.confirmName)" in s
    assert "page.setOn(row.modelData, on)" in s
    assert "page.remove(row.modelData)" in s
    assert "page.add(modelData)" in s
    assert "find.text" in s
    assert "page.confirmName" in s
    assert "page.confirmAction" in s


def test_system_restore_uses_settings_section_and_keeps_actions_and_object_names():
    s = read("shani/Modules/Settings/SettingsSystemRestore.qml")
    assert "SettingsSection {" in s
    assert 'title: Tr.t("Roll back to the previous slot")' in s
    assert 'objectName: "system-restore-scope"' in s
    assert 'objectName: "system-restore-panel"' in s
    assert 'objectName: "system-restore-error"' in s
    assert 'objectName: "system-restore-offline"' in s
    assert 'objectName: "system-restore-empty"' in s
    assert 'objectName: "system-restore-note"' in s
    assert 'objectName: "system-restore-busy"' in s
    assert 'objectName: "system-restore-action-error"' in s
    assert 'objectName: "system-restore-no-dry-run"' in s
    assert 'objectName: "system-restore-go-back"' in s
    assert "SystemRestore.refresh()" in s
    assert "SystemRestore.switchSlot(slot.id)" in s
    assert "SystemRestore.restorePrevious()" in s
    assert "SystemRestore.preview()" in s
    assert "panel.arm(slot)" in s
    assert "panel.armPrevious()" in s
    assert 'Tr.t("Refresh slots")' in s
    assert 'Tr.t("Go back to previous system")' in s


def test_ups_keeps_labels_visibility_and_keys():
    s = read("shani/Modules/Settings/SettingsUps.qml")
    # custom layout; keep exact labels/keys/visibility
    assert 'text: Tr.t("UPS")' in s
    assert "visible: Ups.present" in s
    assert "Ups.refresh()" in s
    assert "Ups.onBattery" in s
    assert "Ups.low" in s
    assert "Ups.info" in s
    assert "Ups.says(Ups.info)" in s


def test_users_uses_settings_sections_and_setting_row_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsUsers.qml")
    assert s.count("SettingsSection {") >= 2
    assert s.count("SettingRow {") >= 1
    assert 'title: Tr.t("Users")' in s
    assert 'title: Tr.t("Groups")' in s
    assert 'Tr.t("Administrator")' in s
    assert 'Tr.t("Sign in automatically")' in s
    assert 'Tr.t("Guest")' in s
    assert 'Tr.t("Add a user…")' in s
    assert 'page.act("user-admin", { username: urow.modelData.name, admin: on })' in s
    assert 'page.act("autologin", { username: on ? urow.modelData.name : "" })' in s
    assert (
        'page.act("user-password", { username: urow.modelData.name, password: pw1.text })'
        in s
    )
    assert (
        'page.act("user-remove", { username: urow.modelData.name, deleteHome: false })'
        in s
    )
    assert (
        'page.act("user-remove", { username: urow.modelData.name, deleteHome: true })'
        in s
    )
    assert 'page.act("guest", { on: on })' in s
    assert (
        'page.act("user-add", { username: addForm.user, fullname: newName.text.trim(), password: newPw.text, admin: newAdmin.checked })'
        in s
    )
    assert (
        'page.act("user-group", { username: modelData, group: gcol.modelData.name, member: on })'
        in s
    )
    assert "page.iAmAdmin" in s


def test_wallpaper_style_uses_settings_sections_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsWallpaperStyle.qml")
    assert s.count("SettingsSection {") >= 2
    assert 'objectName: "section:colours"' in s
    assert 'title: Tr.t("Colours from a picture")' in s
    assert 'title: Tr.t("Dominant colours matugen derives")' in s
    assert "WallpaperStyle.open(" in s
    assert "WallpaperStyle.extract()" in s
    assert "WallpaperStyle.apply()" in s
    assert "WallpaperStyle.saveTheme(themeField.text)" in s
    assert "WallpaperStyle.loadTheme(index)" in s
    assert "Matugen.previewPalette" in s
    assert "page.shown" in s


def test_windows_uses_settings_sections_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsWindows.qml")
    assert s.count("SettingsSection {") >= 4
    assert 'title: Tr.t("Windows")' in s
    assert 'title: Tr.t("Look and motion")' in s
    assert 'title: Tr.t("Per-app rules")' in s
    assert 'title: Tr.t("Workspaces in the bar")' in s
    assert "page.d.winGaps" in s
    assert "page.d.windowRules" in s
    assert "page.setRule(index, patch)" not in s  # def exists, call shape differs
    assert "function setRule(i, patch)" in s
    assert "function popRule(i)" in s
    assert "page.setRule(index," in s
    assert "page.popRule(index)" in s
    assert 'Tr.t("Add a rule for an app")' in s
