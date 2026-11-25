// The left rail: this screen's workspaces down the left edge (the top bar, the
// right sidebar and the bottom dock own the other three). niri's columns flow
// left to right, so the left edge is the natural "start of the row" place for
// them. On by default; the dock shows them instead when it is off.
//
// Each workspace shows the apps open on it (up to four, then +N), or its
// number when empty; the one in use is marked, and a click on it opens the
// Overview. "+" goes to the empty workspace niri keeps at the end. A wheel over
// the rail steps through them. It keeps its own strip of the screen, so a
// window is never tiled under it. A phone has no room for it, and a TV or a
// handheld is driven from across the room (FormFactor.hasRail).
// Super+Up/Down and the Overview keep working unchanged.
//
// Or, with railContent "apps", a launcher down the left as Unity's: the apps
// button at the top, then your pinned and running apps (Services/Taskbar).
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

Scope {
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: rail
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true }
            implicitWidth: Theme.px(56)
            color: "transparent"
            WlrLayershell.namespace: "shani-left-rail"
            WlrLayershell.layer: WlrLayer.Top
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: implicitWidth
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            visible: Settings.data.leftRail && !Lock.locked && FormFactor.hasRail(modelData.name)
            // only the card takes the pointer; the strip around it is wallpaper
            mask: Region { item: card }

            readonly property var workspaces: Niri.workspacesOn(modelData.name)
            readonly property var spaces: workspaces.filter(w => w.is_active || w.is_focused || Niri.windowsOn(w).length > 0)
            readonly property var entryOf: Taskbar.entryOf
            readonly property bool apps: Settings.data.railContent === "apps"

            Rectangle {
                id: card
                anchors { left: parent.left; leftMargin: Theme.px(6); verticalCenter: parent.verticalCenter }
                width: parent.width - Theme.px(12)
                height: Math.min(column.implicitHeight + Theme.px(12), rail.height - Theme.px(24))
                radius: Theme.radiusLarge
                color: Settings.blurWanted ? Theme.alpha(Theme.bg, 0.82) : Theme.bg
                border.width: 1
                border.color: Theme.stroke
                clip: true
                Accessible.role: Accessible.Pane
                Accessible.name: Tr.t("Workspaces")
                MouseArea {
                    anchors.fill: parent
                    onWheel: w => {
                        const list = rail.spaces;
                        if (!list.length) return;
                        const at = list.findIndex(x => x.is_active || x.is_focused);
                        const next = at < 0 ? 0 : (at + (w.angleDelta.y < 0 ? 1 : -1) + list.length) % list.length;
                        Niri.focusWorkspace(list[next]);
                    }
                }
                ColumnLayout {
                    id: column
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.px(6) }
                    spacing: Theme.px(6)
                    // ---- as a launcher (railContent "apps") ----
                    Item {
                        visible: rail.apps
                        Layout.fillWidth: true
                        Layout.preferredHeight: width
                        Rectangle { anchors.fill: parent; radius: Theme.radiusSmall; color: Ui.launcher ? Theme.accentSoft : (dashArea.containsMouse ? Theme.hover : "transparent") }
                        Icon { anchors.centerIn: parent; name: "view-app-grid"; size: parent.width * 0.5; color: Theme.accent }
                        MouseArea { id: dashArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Ui.toggleLauncher() }
                        KeyFocus { name: Tr.t("Apps"); onActivated: Ui.toggleLauncher() }
                        Accessible.role: Accessible.Button
                        Accessible.name: Tr.t("Apps")
                        Accessible.onPressAction: Ui.toggleLauncher()
                    }
                    Repeater {
                        model: rail.apps ? Taskbar.items : []
                        Item {
                            id: appCell
                            required property var modelData
                            readonly property bool open: modelData.windows.length > 0
                            readonly property bool front: modelData.windows.some(w => w.id === Niri.focusedWindowId)
                            readonly property string label: modelData.entry ? modelData.entry.name : modelData.id
                            Layout.fillWidth: true
                            Layout.preferredHeight: width
                            Rectangle { anchors.fill: parent; radius: Theme.radiusSmall; color: appCell.front ? Theme.accentSoft : (appArea.containsMouse ? Theme.hover : "transparent") }
                            Rectangle {
                                visible: appCell.open
                                anchors { left: parent.left; leftMargin: -Theme.px(5); verticalCenter: parent.verticalCenter }
                                width: Theme.px(3); height: appCell.front ? parent.height * 0.5 : Theme.px(6); radius: width / 2
                                color: appCell.front ? Theme.accent : Theme.dim
                            }
                            AppIcon { anchors.centerIn: parent; implicitSize: parent.width * 0.7; icon: appCell.modelData.entry ? appCell.modelData.entry.icon : appCell.modelData.id; name: appCell.label }
                            MouseArea { id: appArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Taskbar.activate(appCell.modelData) }
                            KeyFocus { name: appCell.label; onActivated: Taskbar.activate(appCell.modelData) }
                            Accessible.role: Accessible.Button
                            Accessible.name: appCell.label + (appCell.open ? ", " + Tr.t("open") : "")
                            Accessible.onPressAction: Taskbar.activate(appCell.modelData)
                        }
                    }
                    // ---- as the workspaces ----
                    Repeater {
                        model: rail.apps ? [] : rail.spaces.concat([null])
                        Item {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property var ws: modelData
                            readonly property bool plus: ws === null
                            readonly property bool active: !plus && (ws.is_active || ws.is_focused)
                            readonly property var wins: plus ? [] : Niri.windowsOn(ws)
                            Layout.fillWidth: true
                            Layout.preferredHeight: width
                            function activate() {
                                if (cell.plus) Niri.newWorkspaceOn(rail.modelData.name);
                                else if (cell.active) Niri.action("toggle-overview");
                                else Niri.focusWorkspace(ws);
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radiusSmall
                                color: cell.active ? Theme.accentSoft : (area.containsMouse ? Theme.hover : "transparent")
                            }
                            // the one in use: a mark on the edge, as the dock marks running apps
                            Rectangle {
                                visible: cell.active
                                anchors { left: parent.left; leftMargin: -Theme.px(5); verticalCenter: parent.verticalCenter }
                                width: Theme.px(3)
                                height: parent.height * 0.5
                                radius: width / 2
                                color: Theme.accent
                            }
                            Icon {
                                visible: cell.plus
                                anchors.centerIn: parent
                                name: "list-add"
                                size: parent.width * 0.42
                                color: Theme.dim
                            }
                            // nothing open there: its number
                            Text {
                                visible: !cell.plus && cell.wins.length === 0
                                anchors.centerIn: parent
                                text: cell.ws && cell.ws.name !== "" && cell.ws.name !== null && isNaN(Number(cell.ws.name))
                                    ? String(cell.ws.name).substring(0, 1).toUpperCase() : String(cell.index + 1)
                                color: cell.active ? Theme.accent : Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(13) * Theme.fontScale
                                font.weight: cell.active ? Font.DemiBold : Font.Normal
                            }
                            Grid {
                                visible: !cell.plus && cell.wins.length > 0
                                anchors.centerIn: parent
                                columns: cell.wins.length === 1 ? 1 : 2
                                spacing: Theme.px(2)
                                Repeater {
                                    model: cell.wins.slice(0, 4)
                                    AppIcon {
                                        required property var modelData
                                        readonly property var entry: rail.entryOf(modelData.app_id || "")
                                        implicitSize: cell.wins.length === 1 ? cell.width * 0.6 : cell.width * 0.36
                                        icon: entry ? entry.icon : (modelData.app_id || "")
                                        name: entry ? entry.name : (modelData.app_id || "")
                                    }
                                }
                            }
                            // a floating workspace (Super+Shift+Space): marked as the bar marked it
                            Text {
                                visible: !cell.plus && WorkspaceLayout.isFloating(cell.ws)
                                anchors { right: parent.right; top: parent.top; margins: Theme.px(1) }
                                text: "◇"
                                color: cell.active ? Theme.accent : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Math.max(7, cell.width * 0.22)
                            }
                            // more than the four shown: never hide windows silently
                            Text {
                                visible: cell.wins.length > 4
                                anchors { right: parent.right; bottom: parent.bottom; margins: Theme.px(1) }
                                text: "+" + (cell.wins.length - 4)
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: Math.max(7, cell.width * 0.2)
                                font.weight: Font.DemiBold
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: cell.plus ? Tr.t("New workspace")
                                : Tr.t("Workspace %1", cell.ws.name || String(cell.index + 1)) + ", "
                                  + (cell.wins.length === 1 ? Tr.t("1 window") : Tr.t("%1 windows", cell.wins.length))
                            Accessible.selected: cell.active
                            MouseArea {
                                id: area
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: cell.activate()
                            }
                            KeyFocus { onActivated: cell.activate() }
                        }
                    }
                }
            }
        }
    }
}
