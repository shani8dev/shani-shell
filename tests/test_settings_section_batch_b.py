"""Settings batch B: Boot, Chronoa, Components, Controllers, DateLanguage, DefaultApps
adopt SettingsSection/SettingRow where shape fits, keeping labels/actions/keys."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_boot_uses_settings_section_and_keeps_content():
    s = read("shani/Modules/Settings/SettingsBoot.qml")
    assert "SettingsSection {" in s
    assert 'title: Tr.t("Boot & Recovery")' in s
    assert "This computer keeps two systems, blue and green." in s
    assert "BootInfo.refresh()" in s
    assert "BootInfo.rows" in s
    assert 'Tr.t("Needs attention")' in s
    assert 'Tr.t("Pending")' in s
    assert "Rolling back is shani-deploy's job" in s


def test_chronoa_uses_settings_sections_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsChronoa.qml")
    assert s.count("SettingsSection {") >= 2
    assert 'title: Tr.t("Chronoa")' in s
    assert 'title: Tr.t("The Island")' in s
    assert "Chronoa is running." in s
    assert "Chronoa is not running" in s
    assert 'text: Tr.t("Enable Chronoa")' in s
    assert "Settings.data.chronoaEnabled = on" in s
    assert 'Quickshell.execDetached(["shani-chronoa"])' in s
    assert 'Quickshell.execDetached(["pkill", "-f", "shani-chronoa"])' in s
    assert "Chronoa's settings — model, voice, wake word, permissions" in s
    assert "dev.shani.chronoa open-settings" in s
    assert 'text: Tr.t("Show what is going on")' in s
    assert "page.d.islandActivities = on" in s
    assert "Super+A opens Chronoa" in s


def test_components_uses_settings_section_and_keeps_preview():
    s = read("shani/Modules/Settings/SettingsComponents.qml")
    assert "SettingsSection {" in s
    assert 'title: Tr.t("Components")' in s
    assert 'Tr.t("UI component preview")' in s
    assert 'text: Tr.t("Primary")' in s
    assert 'text: Tr.t("Secondary")' in s
    assert 'title: Tr.t("List row")' in s
    assert 'text: Tr.t("Switch row")' in s
    assert 'text: Tr.t("Choice")' in s


def test_controllers_uses_settings_section_and_setting_row():
    s = read("shani/Modules/Settings/SettingsControllers.qml")
    assert s.count("SettingsSection {") >= 3
    assert "SettingRow {" in s
    assert 'title: Tr.t("Game controllers")' in s
    assert 'title: Tr.t("Lights")' in s
    assert 'title: Tr.t("In games")' in s
    assert 'objectName: "in-games"' in s
    assert "InputPlumber.running" in s
    assert "page.lights.length > 0" in s
    assert 'text: Tr.t("Move around the desktop with a controller")' in s
    assert "Settings.data.gamepadNav = on" in s
    assert 'text: Tr.t("Manage every controller")' in s
    assert "InputPlumber.setManageAll(on)" in s
    assert "page.setLight(light.modelData.led" in s
    assert "InputPlumber.setTargets(" in s


def test_date_language_uses_settings_sections_and_keeps_keys():
    s = read("shani/Modules/Settings/SettingsDateLanguage.qml")
    assert s.count("SettingsSection {") >= 3
    assert 'title: Tr.t("Date & time")' in s
    assert 'title: Tr.t("Language & region")' in s
    assert 'title: Tr.t("Calendar")' in s
    # key actions/labels preserved
    assert 'Tr.t("Set the time automatically")' in s
    assert 'page.timedatectl(["set-ntp", String(on)])' in s
    assert 'Tr.t("Save NTP servers")' in s
    assert "page.saveNtp()" in s
    assert 'Tr.t("24-hour clock")' in s
    assert "page.d.use24h = on" in s
    assert 'Tr.t("The first city\'s time in the bar")' in s
    assert "page.d.barWorldClock = on" in s
    assert 'Tr.t("Change language")' in s
    assert 'Tr.t("Change formats")' in s
    assert "page.writeConf(" in s
    assert 'Tr.t("Log out now, to finish")' in s
    assert "Power.logout()" in s
    assert 'Tr.t("Week numbers")' in s
    assert "page.d.weekNumbers = on" in s
    assert 'Tr.t("Show events in the sidebar calendar")' in s
    assert "page.d.showCalendarEvents = on" in s


def test_default_apps_uses_settings_sections_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsDefaultApps.qml")
    assert s.count("SettingsSection {") >= 3
    assert 'title: Tr.t("Default apps")' in s
    assert 'title: Tr.t("Removable media")' in s
    assert 'title: Tr.t("How an app starts")' in s
    assert "page.choose(kindRow.modelData, modelData)" in s
    assert "page.choose(mediaRow.modelData, modelData)" in s
    assert "page.setLaunch(" in s
    assert "Launch.setOptions(page.launchApp, null)" in s
    assert "Launch.app(page.launchApp)" in s
    assert 'Tr.t("Start it now")' in s
    assert 'Tr.t("Back to how it came")' in s
