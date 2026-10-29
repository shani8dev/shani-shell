// The share sheet (Share): where a file can go, one click each.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Share.file !== "" && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-share"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property int sel: 0
    onVisibleChanged: sel = 0
    MouseArea { anchors.fill: parent; onClicked: Share.close() }
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Share.close()
        Keys.onDownPressed: win.sel = Math.min(win.sel + 1, Share.targets.length - 1)
        Keys.onUpPressed: win.sel = Math.max(win.sel - 1, 0)
        Keys.onReturnPressed: Share.choose(win.sel)
    }
    Glass {
        anchors.centerIn: parent
        width: 380
        implicitHeight: col.implicitHeight + 32
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }       // clicks inside do not close it
        ColumnLayout {
            id: col
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 4
            Text {
                Layout.fillWidth: true
                text: "Share “" + Share.name + "”"
                color: Theme.text
                elide: Text.ElideMiddle
                font.family: Theme.font
                font.pixelSize: 15 * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Item { implicitHeight: 4 }
            Repeater {
                model: Share.targets
                ListRow {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    icon: modelData.icon
                    title: modelData.label
                    selected: index === win.sel
                    onClicked: Share.choose(index)
                }
            }
        }
    }
}
