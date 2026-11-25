"""Static regressions: the new apps must be reachable from the launcher,
quick panel and bar. These are QML panels that need a running shell, so each
test asserts the exact source wiring rather than driving a QML runtime.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAUNCHER_ACTIONS = (ROOT / "shani/Modules/Launcher/LauncherActions.qml").read_text(
    encoding="utf-8"
)
QUICK_PANEL = (ROOT / "shani/Modules/QuickPanel/QuickPanel.qml").read_text(
    encoding="utf-8"
)
BAR = (ROOT / "shani/Modules/Bar/Bar.qml").read_text(encoding="utf-8")
UI_SRC = (ROOT / "shani/Common/Ui.qml").read_text(encoding="utf-8")

# nine new surfaces behind Ui flags, by the title an action must carry and the flag it opens
NEW_APPS = {
    "Dictionary": "dictionary",
    "Podcasts": "podcasts",
    "Nearby Share": "nearby",
    "Network Tools": "netTools",
    "Database browser": "databaseBrowser",
    "Startup apps": "startupManager",
    "Nearby Share": "nearby",
    "Paste history": "pasteHistory",
    "Automations": "scheduled",
}


def new_tools_block():
    assert "// ---- new app tools:" in LAUNCHER_ACTIONS
    return LAUNCHER_ACTIONS.split("// ---- new app tools:", 1)[1].split(
        'Tr.t("Suspend")', 1
    )[0]


def test_launcher_actions_cover_all_nine_new_apps():
    catalog = (ROOT / "shani/Common/Tools.js").read_text()
    assert "Tools.list" in LAUNCHER_ACTIONS
    for flag in ("dictionary", "podcasts", "teleprompter", "netTools",
                 "databaseBrowser", "startupManager", "nearby", "pasteHistory", "scheduled"):
        assert f'flag: "{flag}"' in catalog
        if flag in ("startupManager", "scheduled"):
            continue                                   # Settings pages now (Tools.js `settings`)
        assert re.search(r"property bool %s\b" % flag, UI_SRC), flag
    assert "run: () => Ui.openTool(t.flag)" in LAUNCHER_ACTIONS


def test_quickpanel_has_more_apps_row_for_four_tools():
    assert 'Tr.t("More apps")' in QUICK_PANEL
    assert "Tools.list.slice(0, 4)" in QUICK_PANEL
    catalog = (ROOT / "shani/Common/Tools.js").read_text()
    for flag in ("dictionary", "podcasts", "teleprompter", "netTools"):
        assert f'flag: "{flag}"' in catalog


def test_bar_has_one_tools_entry_into_the_launcher():
    assert 'name: Tr.t("Tools")' in BAR
    assert BAR.count('Ui.toggleLauncher("tool")') == 1
