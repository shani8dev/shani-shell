"""Static guards for the UX audit fixes in Settings / the control-centre sidebar.

These are QML/JS surfaces (no headless shell in CI), so each fix is pinned at
the source level: one test per fix.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


PANEL = "shani/Modules/Settings/SettingsSystemRestore.qml"
UPDATES = "shani/Modules/Settings/SettingsUpdates.qml"
PAGE = "shani/Modules/Settings/SettingsPage.qml"
INDEX = "shani/Modules/Settings/SettingsIndex.js"
ABOUT = "shani/Modules/Settings/SettingsAbout.qml"
SIDEBAR = "shani/Modules/ControlCenter/SidebarHeader.qml"
UI = "shani/Common/Ui.qml"
SHELL = "shani/shell.qml"


# 1. one owner of shani-deploy status: Updates shows it, System Restore owns rollback
def test_system_restore_does_not_repeat_update_status():
    panel = source(PANEL)
    assert "SystemRestore.rebootNeeded" not in panel
    assert "SystemRestore.upgradePending" not in panel
    assert 'Tr.t("Roll back to the previous slot")' in panel
    assert "SystemRestore.switchSlot(slot.id);" in panel
    assert "SystemRestore.restorePrevious();" in panel
    assert 'objectName: "system-restore-slot-" + modelData.id' in panel
    # the status the panel dropped is the one SettingsUpdates already shows
    assert "Updates.rebootNeeded" in source(UPDATES)


# 2. the sidebar's Open Updates row no longer closes itself into an empty view
def test_sidebar_updates_row_uses_open_settings():
    sidebar = source(SIDEBAR)
    assert 'onClicked: Ui.openSettings("updates")' in sidebar
    assert 'Ui.closeAll(); Ui.settingsCat = "updates"' not in sidebar


# 3. deep links point only at flags/IPCs that exist; dead ones fall through
def test_settings_index_links_are_live():
    idx = source(INDEX)
    shell, ui = source(SHELL), source(UI)
    assert 'link: "vpnOpen"' not in idx
    assert "function vpnOpen()" not in shell  # confirms the link really was dead
    assert "property bool vpn:" not in ui
    for label, ipc, flag in (
        ("IRC", "ircOpen", "irc"),
        ("Health", "healthOpen", "health"),
    ):
        row = next(l for l in idx.splitlines() if f'label: "{label}"' in l)
        assert f'link: "{ipc}"' in row
        assert f"function {ipc}() {{ Ui.closeAll(); Ui.{flag} = true; }}" in shell
        assert f"property bool {flag}: false" in ui


# 4. openSetting uses an explicit link→flag map and unknown links fall through
def test_open_setting_uses_explicit_link_map():
    page = source(PAGE)
    assert "readonly property var linkFlags: ({" in page
    for ipc, flag in (
        ("dictionaryOpen", "dictionary"),
        ("podcastsOpen", "podcasts"),
        ("scheduledOpen", "scheduled"),
        ("teleprompterOpen", "teleprompter"),
        ("netToolsOpen", "netTools"),
        ("startupManagerOpen", "startupManager"),
        ("gatewayOpen", "gateway"),
        ("databaseBrowserOpen", "databaseBrowser"),
        ("pasteHistoryOpen", "pasteHistory"),
        ("cloudSyncOpen", "cloudSync"),
        ("ircOpen", "irc"),
        ("healthOpen", "health"),
    ):
        assert f'{ipc}: "{flag}"' in page, ipc
    assert "replace(/([a-z])([A-Z])/g" not in page  # identity regex is gone
    assert "if (entry.link && page.linkFlags[entry.link] in Ui) {" in page
    # the category assignment below the link branch is reached on a miss
    assert page.index("if (entry.link &&") < page.index("Ui.settingsCat = entry.cat;")


# 5. the rollback panel is named the way search names it
def test_system_restore_accessible_name_matches_settings_index():
    panel = source(PANEL)
    assert 'objectName: "system-restore-panel"' in panel
    assert 'Accessible.name: Tr.t("System restore")' in panel
    assert 'label: "System restore"' in source(INDEX)


# 6. recently-changed rail holds 8 and refreshes while the sidebar shows it
def test_recent_changed_cap_and_timer():
    page = source(PAGE)
    assert "newRecent.slice(0, 8)" in page
    assert "newRecent.slice(0, 5)" not in page
    assert "running: page.visible || Ui.settingsOpen" in page
    assert "last 8 modified scalar settings" in page


# 7. one canonical label for the Updates destination
def test_updates_destination_has_one_label():
    assert 'key: "updates", label: "Updates", cat: "updates"' in source(INDEX)
    assert 'label: Tr.t("Updates"), cat: "updates"' in source(ABOUT)
    assert 'Tr.t("Updates")' in source(SIDEBAR)
    assert "Updates & going back" not in source(ABOUT)
    assert "Open Updates" not in source(SIDEBAR)
