"""Settings batch D: LiveWallpaper, Look, MatchList, Modules, PowerKeys, Printers
adopt SettingsSection/SettingRow where shape fits, keeping labels/actions/keys."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_live_wallpaper_uses_settings_section_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsLiveWallpaper.qml")
    assert "SettingsSection {" in s
    assert 'title: Tr.t("Live wallpaper")' in s
    # key content/actions preserved
    assert "page.d.wallpaperVideo" in s
    assert "page.d.wallpaperVideoOnBattery" in s
    assert 'Tr.t("None")' in s
    assert 'Tr.t("Choose a video…")' in s
    assert 'Tr.t("Keep playing on battery")' in s
    assert 'FilePicker.open(' in s
    assert "finder.running = true" in s


def test_look_uses_settings_sections_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsLook.qml")
    assert s.count("SettingsSection {") >= 2
    assert 'title: Tr.t("Icons, fonts & cursor")' in s
    assert 'title: Tr.t("Corner radius")' in s
    assert "page.d.iconTheme" in s
    assert "page.d.cursorTheme" in s
    assert "page.d.cursorSize" in s
    assert "page.d.cornerRadius" in s
    assert '"uiFont"' in s
    assert '"monoFont"' in s
    assert "Appearance.restartShell()" in s
    assert 'Tr.t("Restart the shell")' in s
    assert "page.picking" in s


def test_match_list_keeps_structure_and_actions():
    s = read("shani/Modules/Settings/SettingsMatchList.qml")
    # MatchList is a search-results component, not SectionTitle scaffolding;
    # keep labels/behavior intact.
    assert 'Tr.t("Settings")' in s
    assert "root.activated(modelData)" in s
    assert "SettingsIndex.valueSummary" in s
    assert "root.modifiedKey(" in s
    assert "HighlightText {" in s
    assert "KeyFocus { onActivated: root.activated(matchRow.modelData) }" in s


def test_modules_uses_settings_sections_and_setting_rows_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsModules.qml")
    assert s.count("SettingsSection {") >= 4
    assert s.count("SettingRow {") >= 1
    assert 'title: Tr.t("Blacklisted modules")' in s
    assert 'title: Tr.t("Load at boot")' in s
    assert 'title: Tr.t("Kernel tuning (sysctl)")' in s
    assert 'title: Tr.t("Loaded modules")' in s
    assert 'page.saveManaged("modprobe-blacklist-set"' in s
    assert 'page.saveManaged("modules-load-set"' in s
    assert "page.saveSysctl(" in s
    assert "KernelModules.refresh()" in s
    assert "page.loadManaged()" in s
    assert 'Tr.t("Add")' in s
    assert 'Tr.t("Remove")' in s
    assert 'Tr.t("Save")' in s


def test_power_keys_uses_settings_sections_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsPowerKeys.qml")
    assert s.count("SettingsSection {") >= 3
    assert 'title: Tr.t("Lid, power button and battery")' in s
    assert 'title: Tr.t("What can wake this computer")' in s
    assert 'title: Tr.t("Lid & idle (logind)")' in s
    assert 'title: Tr.t("Sleep (systemd-sleep)")' in s
    assert "page.save(" in s
    assert "page.saveLimit(" in s
    assert "page.savePowerLimit(" in s
    assert "page.saveWake(" in s
    assert "page.saveLogind(" in s
    assert "page.saveSleep(" in s
    assert "Power.sleepVerb" in s


def test_printers_uses_settings_section_and_keeps_actions():
    s = read("shani/Modules/Settings/SettingsPrinters.qml")
    assert "SettingsSection {" in s
    assert 'title: Tr.t("Printers")' in s
    assert "page.startAdding()" in s
    assert "page.add(" in s
    assert "page.setOpt(" in s
    assert "page.run(" in s
    assert 'Tr.t("Add a printer…")' in s
    assert 'Tr.t("Refresh")' in s
    assert "cups-browsed-set" in s
    assert "ConfirmButton {" in s
