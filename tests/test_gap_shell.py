"""Static checks for the shell-surface gaps implemented in the module QML.

There is no QML runtime in the dev container, so these read the source the
same way the other gap tests do: each feature must be present in the file that
owns it, wired to the existing service calls rather than a stub.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return (ROOT / path).read_text()


def assert_balanced(path):
    """A brace/paren imbalance is the cheapest way to catch a broken edit."""
    s = read(path)
    assert s.count("{") == s.count("}"), f"unbalanced braces in {path}"
    assert s.count("(") == s.count(")"), f"unbalanced parens in {path}"
    return s


def test_edited_qml_is_balanced():
    for path in (
        "shani/Modules/Notifications/Popups.qml",
        "shani/Modules/Notifications/NotificationCard.qml",
        "shani/Modules/Switcher/Switcher.qml",
        "shani/Modules/Bar/Bar.qml",
        "shani/Modules/Dock/Dock.qml",
        "shani/Modules/Launcher/Launcher.qml",
    ):
        assert_balanced(path)


def test_grouped_notification_stacks():
    s = assert_balanced("shani/Modules/Notifications/Popups.qml")
    # the per-app key is the one Notifs.qml:30 builds for Notifs.perApp
    assert "function appKey(n)" in s
    assert "(n && n.desktopEntry) || (n && n.appName)" in s
    assert ".toLowerCase()" in s
    assert "function groupPopups()" in s
    assert "Notifs.popups.slice().reverse()" in s
    # a header counts them and expands on click
    assert "property var expanded" in s
    assert "function toggleGroup(key)" in s
    assert "stack.modelData.items.length" in s
    assert 'stack.open ? "▾" : "▸"' in s
    assert 'Tr.t("%1 notifications from %2"' in s
    # cards inside a stack do not repeat the app name; each keeps its timeout
    assert "component PopupCard: NotificationCard" in s
    assert "showApp: !pc.inGroup" in s
    assert "NumberAnimation on life" in s
    assert (
        "model: stack.multi ? (stack.open ? stack.modelData.items : []) : stack.modelData.items"
        in s
    )


def test_tray_overflow_drawer():
    s = assert_balanced("shani/Modules/Bar/Bar.qml")
    assert "readonly property int trayCap: 6" in s
    assert "trayShown: Array.from(SystemTray.items || []).slice(0, bar.trayCap)" in s
    assert "trayOverflow: Array.from(SystemTray.items || []).slice(bar.trayCap)" in s
    # the flat inline list is gone; the extra icons live in a popup drawer
    assert "model: SystemTray.items\n" not in s
    assert "PopupWindow {" in s and "id: trayDrawer" in s
    assert "visible: bar.trayOpen && bar.trayOverflow.length > 0" in s
    assert "model: bar.trayOverflow" in s
    assert "component TrayButton: Item" in s
    assert "property bool inDrawer" in s
    assert "QsMenuAnchor {" in s  # the drawer items keep their menus
    assert "More system tray icons" in s
    assert s.index("id: trayDrawer") < s.index("SystemClock {")


def test_switcher_groups_by_app_and_closes_a_whole_app():
    s = assert_balanced("shani/Modules/Switcher/Switcher.qml")
    assert "property bool grouped: true" in s
    assert "function buildGroups()" in s
    assert 'String((w && w.app_id) || "").toLowerCase()' in s
    assert "readonly property var groups: win.buildGroups()" in s
    assert "model: win.grouped ? win.groups : win.list" in s
    assert 'Tr.t("%1 windows", cell.windowCount)' in s
    # G toggles flat/grouped; Shift+Q closes every window of that app
    assert "e.key === Qt.Key_G" in s
    assert "e.key === Qt.Key_Q && (e.modifiers & Qt.ShiftModifier)" in s
    assert "function closeApp()" in s
    assert "for (const w of ws)" in s
    assert 'Niri.action("close-window", "--id", w.id)' in s
    # focus and the plain Q still work on the selected window
    assert "Niri.focusWin(ws[0])" in s
    assert "Shift+Q close app" in s


def test_workspace_map_drag_moves_windows():
    s = assert_balanced("shani/Modules/Bar/Bar.qml")
    # both the tiled and the floating rects start a drag carrying a window id
    assert (
        s.count('Drag.mimeData: ({ "text/plain": String(modelData.window.id) })') == 2
    )
    assert "Drag.dragType: Drag.Automatic" in s
    assert "drag.target: mapDragProxy" in s
    # a workspace button is the drop target and calls the existing Niri call
    assert "readonly property string moveTarget:" in s
    assert 'keys: ["text/plain"]' in s
    assert "Niri.moveWindowTo(Niri.windows[id] || { id: id }, parent.moveTarget)" in s
    assert 'd.getData("text/plain")' in s


def test_launcher_app_drag_pins_to_dock():
    launcher = assert_balanced("shani/Modules/Launcher/Launcher.qml")
    dock = assert_balanced("shani/Modules/Dock/Dock.qml")
    assert "did: a.id" in launcher
    assert '"shani-app:" + (tile.modelData.did || "")' in launcher
    assert "drag.target: appDragProxy" in launcher
    assert "function dropAppId(d)" in dock
    assert 't.indexOf("shani-app:") === 0' in dock
    assert "function pinApp(id)" in dock
    assert "Settings.data.dockPinned = list.concat([id])" in dock
    assert "win.pinApp(appId)" in dock
    # the file-drop path is still there: no regression for opening files with an app
    assert "Ui.openFilesWith(cell.modelData.entry.id, files)" in dock
    assert "AppFilter.allowed(id)" in dock  # validate before writing the setting


def test_full_app_menu_overflow():
    s = assert_balanced("shani/Modules/Bar/Bar.qml")
    assert "model: AppMenu.menus.slice(0, 5)" in s
    assert "readonly property int overflowMenuIndex: 9999" in s
    assert "readonly property var overflowMenus: AppMenu.menus.slice(5)" in s
    assert 'text: "⋯"' in s
    assert "bar.inlineFlatten(bar.inlineMenu === bar.overflowMenuIndex" in s
    assert "bar.inlineMenu === bar.overflowMenuIndex ? -1 : bar.overflowMenuIndex" in s
    assert "AppMenu.activate(it.path)" in s  # items still go through AppMenu


def test_run_as_administrator_uses_pkexec_argv():
    s = assert_balanced("shani/Modules/Launcher/Launcher.qml")
    assert (
        'function runAdmin(cmd) { Quickshell.execDetached(["pkexec", "sh", "-c", cmd]); }'
        in s
    )
    assert "Run as administrator" in s
    assert 'icon: "dialog-password"' in s
    assert 'q.startsWith(">")' in s
    # the command is its own argv element; never interpolated into a shell string
    assert '"pkexec", "sh", "-c", cmd' in s
    assert "win.runAdmin(cmd)" in s


def test_privacy_attribution_has_no_client_field():
    # Goal 8 is intentionally skipped: editing Services/ is out of scope and
    # Privacy.qml exposes only booleans (cameraInUse / micInUse), no client.
    p = read("shani/Services/Privacy.qml")
    assert "property bool cameraInUse" in p
    assert "micInUse" in p
    assert "client" not in p.lower()
