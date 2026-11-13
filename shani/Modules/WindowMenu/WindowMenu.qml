// The window menu: click the focused window's title in the bar. On top, the app's
// own menus (File, Edit, View ...), read from its accessibility tree
// (Services/AppMenu, bridge/appmenu.py) - niri has no app-menu protocol and GTK 4
// exports none over D-Bus, but GTK 3, Qt and XWayland apps show their menu bar
// to AT-SPI; an app that shows none gets its desktop actions ("New Window")
// instead. Below, niri's actions on the window (by id, so focus moving meanwhile
// does not redirect it), which work for every app.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.windowMenu && target !== null
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-window-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: visible && Settings.blurWanted ? menuRegion : null
    Region { id: menuRegion; item: card; radius: Theme.radius }

    property var target: null            // the window, captured when the menu opens
    // the app's desktop actions, when it shows no menu bar of its own
    readonly property var desktopEntry: target ? (DesktopEntries.byId(target.app_id || "") || DesktopEntries.heuristicLookup(target.app_id || "")) : null
    readonly property var appActions: AppMenu.loading || AppMenu.menus.length || !desktopEntry ? []
        : Array.from(desktopEntry.actions || []).slice(0, 6).map((a, i) => ({ id: "act" + i, label: a.name, icon: desktopEntry.icon || "application-x-executable",
                                                                           run: () => a.execute() }))
    readonly property var entries: target === null ? [] : [
        ...appActions,
        { id: "close", sep: appActions.length > 0, label: Tr.t("Close"), icon: "window-close", run: () => Niri.action("close-window", "--id", target.id) },
        { id: "minimise", label: Tr.t("Minimise"), icon: "window-minimize", run: () => Niri.minimise(target.id) },
        { id: "fullscreen", label: Tr.t("Fullscreen"), icon: "view-fullscreen", run: () => Niri.action("fullscreen-window", "--id", target.id) },
        { id: "pin", label: Niri.isPinned(target.id) ? Tr.t("Only on this workspace") : Tr.t("Show on all workspaces"), icon: "view-pin", run: () => Niri.togglePinned(target.id) },
        { id: "float", sep: true, label: target.is_floating ? "Tile" : "Float", icon: "window-restore", run: () => Niri.action("toggle-window-floating", "--id", target.id) },
        { id: "maximize", label: Tr.t("Maximize column"), icon: "window-maximize", run: () => { Niri.action("focus-window", "--id", target.id); Niri.action("maximize-column"); } },
        { id: "center", label: Tr.t("Center"), icon: "zoom-fit-best", run: () => { Niri.action("focus-window", "--id", target.id); Niri.action("center-column"); } },
        // snap layouts (after Windows): the column at a half, a third or two thirds of the screen
        { id: "half", label: Tr.t("Half the screen"), icon: "view-dual", run: () => { Niri.action("focus-window", "--id", target.id); Niri.action("set-column-width", "50%"); } },
        { id: "third", label: Tr.t("A third"), icon: "view-dual", run: () => { Niri.action("focus-window", "--id", target.id); Niri.action("set-column-width", "33.333%"); } },
        { id: "twothirds", label: Tr.t("Two thirds"), icon: "view-dual", run: () => { Niri.action("focus-window", "--id", target.id); Niri.action("set-column-width", "66.667%"); } },
        ...(Displays.outputs.length > 1 ? [{ id: "monitor", sep: true, label: Tr.t("Move to the other monitor"), icon: "video-display",
            run: () => { Niri.action("focus-window", "--id", target.id); Niri.action("move-column-to-monitor-next"); } }] : []),
        { id: "ws1", sep: Displays.outputs.length <= 1, label: Tr.t("Move to workspace 1"), icon: "go-next", run: () => Niri.action("move-window-to-workspace", "--window-id", target.id, "--focus", "false", "1") },
        { id: "ws2", label: Tr.t("Move to workspace 2"), icon: "go-next", run: () => Niri.action("move-window-to-workspace", "--window-id", target.id, "--focus", "false", "2") },
        { id: "ws3", label: Tr.t("Move to workspace 3"), icon: "go-next", run: () => Niri.action("move-window-to-workspace", "--window-id", target.id, "--focus", "false", "3") },
        { id: "ask", sep: true, label: Tr.t("Ask Chronoa about this window"), icon: "chat-message-new",
          run: () => Chronoa.ask("About the window “" + (target.title || target.app_id) + "” (" + target.app_id + ") on my screen: what can you help me do with it?") }
    ]
    property int sel: 0
    onEntriesChanged: Ui.windowMenuLabels = entries.map(e => e.label)
    // the app's menus: which one is open (-1: none), which submenus are unfolded in it
    property int openMenu: -1
    property var expanded: ({})
    function flatten(items, depth) {
        let out = [];
        for (const it of items || []) {
            out.push(Object.assign({ depth: depth }, it));
            if (it.items && expanded[it.path])
                out = out.concat(flatten(it.items, depth + 1));
        }
        return out;
    }
    readonly property var openItems: openMenu >= 0 && AppMenu.menus[openMenu] ? flatten(AppMenu.menus[openMenu].items, 0) : []
    function press(it) {
        if (it.items) {
            const e = Object.assign({}, expanded);
            e[it.path] = !e[it.path];
            expanded = e;
            return;
        }
        if (!it.enabled) return;
        Ui.windowMenu = false;
        AppMenu.activate(it.path);
    }

    function run(id) {
        const e = entries.find(x => x.id === id);
        Ui.windowMenu = false;
        if (e)
            e.run();
    }

    onVisibleChanged: if (visible) { sel = 0; keys.forceActiveFocus(); }
    // made on first use, when the menu is already open: the opening this missed
    Component.onCompleted: {
        if (Ui.windowMenu && target === null) {
            target = Niri.focusedWindow;
            AppMenu.load(target);
        }
        if (visible) { sel = 0; keys.forceActiveFocus(); }
    }
    Connections {
        target: Ui
        function onWindowMenuChanged() {
            win.openMenu = -1;
            win.expanded = ({});
            if (Ui.windowMenu) {
                win.target = Niri.focusedWindow;
                AppMenu.load(win.target);
            }
        }
        function onWindowMenuAppRequested(index) { win.openMenu = index; win.expanded = ({}); }
        function onWindowMenuActionRequested(id) {
            win.target = win.target || Niri.focusedWindow;
            win.run(id);
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.windowMenu = false
        Keys.onDownPressed: win.sel = Math.min(win.sel + 1, win.entries.length - 1)
        Keys.onUpPressed: win.sel = Math.max(win.sel - 1, 0)
        Keys.onReturnPressed: win.run(win.entries[win.sel].id)
    }
    MouseArea { anchors.fill: parent; onClicked: Ui.windowMenu = false }

    Glass {
        id: menuCard
        strong: true
        solid: true             // it lies over the app's own window: nothing blurs what is behind it
        visible: win.openItems.length > 0
        x: card.x + card.width + 8
        y: card.y
        width: 300
        height: menuCol.implicitHeight + 16
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: menuCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 1
            Repeater {
                model: win.openItems
                Item {
                    id: mi
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: modelData.separator ? 9 : 32
                    Rectangle {
                        visible: !!mi.modelData.separator
                        anchors.verticalCenter: parent.verticalCenter
                        x: 10; width: parent.width - 20; height: 1
                        color: Theme.alpha(Theme.text, 0.1)
                    }
                    Rectangle {
                        visible: !mi.modelData.separator
                        anchors.fill: parent
                        radius: Theme.radiusSmall
                        color: miMouse.containsMouse && mi.modelData.enabled !== false ? Theme.hover : "transparent"
                        Accessible.role: mi.modelData.items ? Accessible.ButtonMenu : Accessible.MenuItem
                        Accessible.name: mi.modelData.label || ""
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10 + (mi.modelData.depth || 0) * 16
                            anchors.rightMargin: 10
                            spacing: 8
                            Text {
                                text: mi.modelData.checked ? "✓" : ""
                                Layout.preferredWidth: 12
                                color: Theme.accent
                                font.pixelSize: 12 * Theme.fontScale
                            }
                            Text {
                                Layout.fillWidth: true
                                text: mi.modelData.label || ""
                                elide: Text.ElideRight
                                color: mi.modelData.enabled === false ? Theme.faint : Theme.text
                                font.family: Theme.font
                                font.pixelSize: 12 * Theme.fontScale
                            }
                            Text {
                                text: mi.modelData.items ? (win.expanded[mi.modelData.path] ? "▾" : "▸") : (mi.modelData.shortcut || "")
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 11 * Theme.fontScale
                            }
                        }
                        MouseArea {
                            id: miMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: win.press(mi.modelData)
                        }
                        KeyFocus { onActivated: win.press(mi.modelData) }
                    }
                }
            }
        }
    }

    Glass {
        id: card
        strong: true
        x: Math.max(10, Ui.windowMenuX)
        y: Theme.barHeight + 14
        width: 280
        height: col.implicitHeight + 16
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2
            Text {
                Layout.fillWidth: true
                Layout.margins: 6
                text: win.target ? ((Niri.windows[win.target.id] || win.target).title || win.target.app_id) : ""
                color: Theme.dim
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
            // the app's own menus: File, Edit, View ... (one opens beside the card)
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                visible: AppMenu.menus.length > 0 || AppMenu.loading
                spacing: 4
                Text {
                    visible: AppMenu.loading
                    text: Tr.t("Reading the app's menus…")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                    padding: 6
                }
                Repeater {
                    model: AppMenu.menus
                    Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property bool on: win.openMenu === index
                        width: chipText.implicitWidth + 18
                        height: 28
                        radius: Theme.radiusSmall
                        color: on ? Theme.accent : (chipMouse.containsMouse ? Theme.hover : "transparent")
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.modelData.label
                            color: chip.on ? Theme.accentInk : Theme.text
                            font.family: Theme.font
                            font.pixelSize: 12 * Theme.fontScale
                        }
                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { win.openMenu = chip.on ? -1 : chip.index; win.expanded = ({}); }
                        }
                        KeyFocus { onActivated: { win.openMenu = chip.on ? -1 : chip.index; win.expanded = ({}); } }
                    }
                }
            }
            Rectangle {
                visible: AppMenu.menus.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                implicitHeight: 1
                color: Theme.alpha(Theme.text, 0.1)
            }
            // in groups: the window, its size, where it goes, Chronoa
            Repeater {
                model: win.entries
                ColumnLayout {
                    id: entryRow
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0
                    Rectangle {
                        visible: !!entryRow.modelData.sep
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Layout.bottomMargin: 4
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        implicitHeight: 1
                        color: Theme.alpha(Theme.text, 0.1)
                    }
                    ListRow {
                        Layout.fillWidth: true
                        icon: entryRow.modelData.icon
                        title: entryRow.modelData.label
                        selected: win.sel === entryRow.index
                        onClicked: win.run(entryRow.modelData.id)
                    }
                }
            }
        }
    }
}
