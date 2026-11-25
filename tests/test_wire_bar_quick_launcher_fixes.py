"""Static regressions: the new apps must be reachable from the launcher,
quick panel and bar. These are QML panels that need a running shell, so each
test asserts the exact source wiring rather than driving a QML runtime.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAUNCHER_ACTIONS = (ROOT / "shani/Modules/Launcher/LauncherActions.qml").read_text(
    encoding="utf-8"
)
QUICK_PANEL = (ROOT / "shani/Modules/QuickPanel/QuickPanel.qml").read_text(
    encoding="utf-8"
)
BAR = (ROOT / "shani/Modules/Bar/Bar.qml").read_text(encoding="utf-8")

# nine new surfaces behind Ui flags, by the title an action must carry and the flag it opens
NEW_APPS = {
    "Dictionary": "dictionary",
    "Podcasts": "podcasts",
    "Teleprompter": "teleprompter",
    "Network Tools": "netTools",
    "Database browser": "databaseBrowser",
    "Startup manager": "startupManager",
    "Gateway": "gateway",
    "Paste history": "pasteHistory",
    "Scheduled tasks": "scheduled",
}


def new_tools_block():
    assert "// ---- new app tools:" in LAUNCHER_ACTIONS
    return LAUNCHER_ACTIONS.split("// ---- new app tools:", 1)[1].split(
        'Tr.t("Suspend")', 1
    )[0]


def test_launcher_actions_cover_all_nine_new_apps():
    block = new_tools_block()
    for title, flag in NEW_APPS.items():
        lines = [line for line in block.splitlines() if f'Tr.t("{title}")' in line]
        assert lines, f"no launcher action for {title}"
        assert any("tool" in line for line in lines), (
            f"{title} missing 'tool' discovery keyword"
        )
        assert any(f"Ui.closeAll(); Ui.{flag} = true;" in line for line in lines), (
            f"{title} does not open Ui.{flag}"
        )


def test_quickpanel_has_more_apps_row_for_four_tools():
    assert 'Tr.t("More apps")' in QUICK_PANEL
    more_apps = QUICK_PANEL.split('Tr.t("More apps")', 1)[1]
    for title, flag in {
        "Dictionary": "dictionary",
        "Podcasts": "podcasts",
        "Network tools": "netTools",
        "Gateway": "gateway",
    }.items():
        lines = [line for line in more_apps.splitlines() if f'Tr.t("{title}")' in line]
        assert lines, f"no quick-panel button for {title}"
        assert any(f"Ui.closeAll(); Ui.{flag} = true;" in line for line in lines), (
            f"{title} button does not open Ui.{flag}"
        )


def test_bar_has_one_tools_entry_into_the_launcher():
    assert 'name: Tr.t("Tools")' in BAR
    assert BAR.count('Ui.toggleLauncher("tool")') == 1
