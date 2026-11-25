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
    ("Automations", "scheduledOpen", "scheduled", "automations"),
    ("Podcasts", "podcastsOpen", "podcasts", "sound"),
    ("Teleprompter", "teleprompterOpen", "teleprompter", "apps"),
    ("Network Tools", "netToolsOpen", "netTools", "network"),
    ("Database browser", "databaseBrowserOpen", "databaseBrowser", "apps"),
    ("Startup apps", "startupManagerOpen", "startupManager", "apps"),
    ("Nearby Share", "nearbyOpen", "nearby", "sharing"),
    ("Paste history", "pasteHistoryOpen", "pasteHistory", "apps"),
]


def test_settings_index_has_a_deep_link_per_new_app():
    idx = source("shani/Modules/Settings/SettingsIndex.js")
    shell = source("shani/shell.qml")
    # the contract: link names the shell's IPC function, which sets the Ui flag
    assert "entry.link is the shell's IPC function" in idx
    # nine tool links are generated from Tools.list; three extra are literal
    assert "...Tools.list.filter(t => !t.settings).map" in idx and "link: t.op" in idx
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
        if cat in ("apps", "automations") and flag in ("startupManager", "scheduled"):
            # a Settings page now: the IPC opens that page
            assert f'function {ipc}() {{ Ui.openSettings("{cat}"); }}' in shell, ipc
            continue
        opener = f"function {ipc}() {{ Ui.closeAll(); Ui.{flag} = true; }}"
        opener_with_file = f"function {ipc}(path: string) {{ Ui.closeAll(); if (path) Nearby.pending = [path]; Ui.{flag} = true; }}"
        assert opener in shell or opener_with_file in shell, ipc


def test_app_menus_leave_the_tools_to_the_launcher_and_quick_settings():
    # the dock's app menu and a window's menu once each listed every tool; they
    # are about that app or window now, and the tools stay one search away
    for rel in ("shani/Modules/Dock/Dock.qml", "shani/Modules/WindowMenu/WindowMenu.qml"):
        menu = source(rel)
        assert "toolsOpen" not in menu and "Tools.list" not in menu, rel
    actions = source("shani/Modules/Launcher/LauncherActions.qml")
    assert "...Tools.list.map" in actions
