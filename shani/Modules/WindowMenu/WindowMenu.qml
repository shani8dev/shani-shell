// The window menu: click the focused window's title in the bar. Everything in
// it is a niri action on that window (by id, so focus moving meanwhile does
// not redirect it) — it works for every app, unlike a global menu, which on
// niri would be empty: GTK 4 apps export none, and the appmenu protocol is
// KWin's alone.
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
    BackgroundEffect.blurRegion: visible && Settings.data.blur ? menuRegion : null
    Region { id: menuRegion; item: card; radius: Theme.radius }

    property var target: null            // the window, captured when the menu opens
    readonly property var entries: target === null ? [] : [
        { id: "close", label: Tr.t("Close"), icon: "window-close", run: () => Niri.action("close-window", "--id", target.id) },
        { id: "fullscreen", label: Tr.t("Fullscreen"), icon: "view-fullscreen", run: () => Niri.action("fullscreen-window", "--id", target.id) },
        { id: "float", label: target.is_floating ? "Tile" : "Float", icon: "window-restore", run: () => Niri.action("toggle-window-floating", "--id", target.id) },
        { id: "maximize", label: Tr.t("Maximize column"), icon: "window-maximize", run: () => { Niri.action("focus-window", "--id", target.id); Niri.action("maximize-column"); } },
        { id: "center", label: Tr.t("Center"), icon: "zoom-fit-best", run: () => { Niri.action("focus-window", "--id", target.id); Niri.action("center-column"); } },
        // snap layouts (after Windows): the column at a half, a third or two thirds of the screen
        { id: "half", label: Tr.t("Half the screen"), icon: "view-dual", run: () => { Niri.action("focus-window", "--id", target.id); Niri.action("set-column-width", "50%"); } },
        { id: "third", label: Tr.t("A third"), icon: "view-column", run: () => { Niri.action("focus-window", "--id", target.id); Niri.action("set-column-width", "33.333%"); } },
        { id: "twothirds", label: Tr.t("Two thirds"), icon: "view-column", run: () => { Niri.action("focus-window", "--id", target.id); Niri.action("set-column-width", "66.667%"); } },
        ...(Displays.outputs.length > 1 ? [{ id: "monitor", label: Tr.t("Move to the other monitor"), icon: "video-display",
            run: () => { Niri.action("focus-window", "--id", target.id); Niri.action("move-column-to-monitor-next"); } }] : []),
        { id: "ws1", label: Tr.t("Move to workspace 1"), icon: "go-next", run: () => Niri.action("move-window-to-workspace", "--window-id", target.id, "--focus", "false", "1") },
        { id: "ws2", label: Tr.t("Move to workspace 2"), icon: "go-next", run: () => Niri.action("move-window-to-workspace", "--window-id", target.id, "--focus", "false", "2") },
        { id: "ws3", label: Tr.t("Move to workspace 3"), icon: "go-next", run: () => Niri.action("move-window-to-workspace", "--window-id", target.id, "--focus", "false", "3") },
        { id: "ask", label: Tr.t("Ask Chronoa about this window"), icon: "chat-message-new",
          run: () => Chronoa.ask("About the window “" + (target.title || target.app_id) + "” (" + target.app_id + ") on my screen: what can you help me do with it?") }
    ]
    property int sel: 0

    function run(id) {
        const e = entries.find(x => x.id === id);
        Ui.windowMenu = false;
        if (e)
            e.run();
    }

    onVisibleChanged: if (visible) { sel = 0; keys.forceActiveFocus(); }
    Connections {
        target: Ui
        function onWindowMenuChanged() {
            if (Ui.windowMenu)
                win.target = Niri.focusedWindow;
        }
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
                text: win.target ? (win.target.title || win.target.app_id) : ""
                color: Theme.dim
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
            Repeater {
                model: win.entries
                ListRow {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    icon: modelData.icon
                    title: modelData.label
                    selected: win.sel === index
                    onClicked: win.run(modelData.id)
                }
            }
        }
    }
}
