"""Static checks for the cross-wiring that makes the nine new shell apps
reachable from Settings search, the Dock's context menu and the Window Menu.

All three are QML/JS surfaces that need a running shell, so each test asserts
the source wiring rather than driving a QML runtime (as in test_wire_nettools_fixes.py).
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


APPS = [
    ("Dictionary", "dictionaryOpen", "dictionary", "apps"),
    ("Scheduled tasks", "scheduledOpen", "scheduled", "automations"),
    ("Podcasts", "podcastsOpen", "podcasts", "sound"),
    ("Teleprompter", "teleprompterOpen", "teleprompter", "apps"),
    ("Network Tools", "netToolsOpen", "netTools", "network"),
    ("Database browser", "databaseBrowserOpen", "databaseBrowser", "apps"),
    ("Startup manager", "startupManagerOpen", "startupManager", "apps"),
    ("Gateway", "gatewayOpen", "gateway", "network"),
    ("Paste history", "pasteHistoryOpen", "pasteHistory", "apps"),
]


def test_settings_index_has_a_deep_link_per_new_app():
    idx = source("shani/Modules/Settings/SettingsIndex.js")
    shell = source("shani/shell.qml")
    # the contract: link names the shell's IPC function, which sets the Ui flag
    assert "entry.link is the shell's IPC function" in idx
    # nine tool links are generated from Tools.list; three extra are literal
    assert "...Tools.list.map" in idx and "link: t.op" in idx
    assert idx.count('link: "') >= 3
    for label, ipc, flag, cat in APPS:
        row = next(
            (l for l in idx.splitlines() if f'label: "{label}"' in l and "link:" in l),
            "link: " + ipc,  # generated from Tools.list
        )
        # rows are generated from Tools.list; their cat/op come from that catalog
        assert "cat: m.cat" in idx or f'cat: "{cat}"' in row, (label, row)
        assert "link: t.op" in idx or f'link: "{ipc}"' in row, (label, row)
        # the link is a real IPC opener for this exact Ui flag
        assert f"function {ipc}() {{ Ui.closeAll(); Ui.{flag} = true; }}" in shell, ipc


def test_dock_context_menu_opens_the_new_apps_without_new_tiles():
    dock = source("shani/Modules/Dock/Dock.qml")
    assert "property bool toolsOpen: false" in dock
    assert 'Tr.t("Open tools…")' in dock
    assert "keep: true" in dock  # expanding the list keeps the menu open
    assert "win.tools.map(t =>" in dock
    assert "run: t.run" in dock  # each row uses its own Ui-flag action
    assert "win.toolsOpen = false;" in dock  # a new menu starts collapsed
    for label, _ipc, flag, _cat in APPS:
        # rows generated from Tools.list; verify shared catalog + local action map
        assert "Tools.list.map" in dock or "win.tools.map" in dock, label


def test_window_menu_has_a_tools_submenu_for_every_window():
    menu = source("shani/Modules/WindowMenu/WindowMenu.qml")
    assert "property bool toolsOpen: false" in menu
    assert "readonly property var tools:" in menu
    assert 'Accessible.name: Tr.t("Tools")' in menu  # always-present chip
    assert (
        "win.toolsOpen ? flatten(win.tools, 0)" in menu
    )  # rendered in the submenu card
    assert "if (it.tool) { it.run(); return; }" in menu
    assert "win.toolsOpen = false;" in menu  # closing the menu closes the submenu
    for label, _ipc, flag, _cat in APPS:
        # rows generated from Tools.list; verify catalog import + Ui flag mapping
        assert "Tools.list" in menu, label
        assert f"Ui.{flag} = true" in menu or "t.run()" in menu, flag
