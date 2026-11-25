// The left rail: a slim vertical list of this output's workspaces, using the
// vertical middle of the left edge (the top bar, right sidebar and bottom dock
// own the other three). niri's columns flow left to right, so the left edge is
// the natural "start of the row" place to put workspace navigation. It is
// pointer-only: Super+Left/Right and the Overview keep working unchanged.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: rail
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true }
    margins { top: barReserve; bottom: dockReserve }
    implicitWidth: Theme.px(48)
    color: "transparent"
    WlrLayershell.namespace: "shani-left-rail"
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: Settings.data.leftRail

    readonly property int barReserve: Theme.px(72)
    readonly property int dockReserve: Theme.px(96)
    readonly property var workspaces: Niri.workspacesOn(screen ? screen.name : "")
    readonly property var activeWorkspace: Niri.workspaces.find(x => x.is_focused) || null

    // column of workspace buttons, with the active one highlighted; a wheel
    // over the rail cycles workspaces like the dock/switcher do
    Rectangle {
        id: card
        anchors { fill: parent; margins: Theme.px(4) }
        radius: Theme.radiusLarge
        color: Settings.blurWanted ? Theme.alpha(Theme.bg, 0.82) : Theme.bg
        Accessible.role: Accessible.Pane
        Accessible.name: Tr.t("Workspaces")
        MouseArea {
            anchors.fill: parent
            onWheel: w => {
                const list = rail.workspaces;
                if (!list.length) return;
                const at = list.findIndex(x => x.is_active || x.is_focused);
                const next = at < 0 ? 0 : (at + (w.angleDelta.y < 0 ? 1 : -1) + list.length) % list.length;
                Niri.focusWorkspace(list[next]);
            }
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(6)
            spacing: Theme.px(6)
            Repeater {
                model: rail.workspaces
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(36)
                    readonly property var ws: modelData
                    readonly property bool active: ws.is_active || ws.is_focused
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusSmall
                        color: active ? Theme.accentSoft : (area.containsMouse ? Theme.hover : "transparent")
                    }
                    Text {
                        anchors.centerIn: parent
                        text: ws.name === "" ? String(ws.idx) : String(ws.name).substring(0, 1).toUpperCase()
                        color: active ? Theme.accent : Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(13) * Theme.fontScale
                        font.weight: active ? Font.DemiBold : Font.Normal
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: Tr.t("Workspace %1", ws.name || String(ws.idx))
                    Accessible.selected: active
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Niri.focusWorkspace(ws)
                    }
                    KeyFocus { onActivated: Niri.focusWorkspace(ws) }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

}
