// An app's icon, or - for an app the icon theme does not know (a terminal app
// with its own app id, an Electron app whose id does not match its desktop
// file) - a tile with its initial, instead of the theme's generic executable.
import Quickshell
import Quickshell.Widgets
import QtQuick
import qs.Common

Item {
    id: root
    property string icon                 // an icon name or a path
    property string name                 // for the initial
    property real implicitSize: 32
    implicitWidth: implicitSize
    implicitHeight: implicitSize
    readonly property string path: !icon ? "" : icon.startsWith("/") ? "file://" + icon : Quickshell.iconPath(icon, true)

    IconImage {
        anchors.fill: parent
        visible: root.path !== ""
        source: root.path
        implicitSize: root.implicitSize
    }
    Rectangle {
        visible: root.path === ""
        anchors.fill: parent
        anchors.margins: parent.width * 0.06
        radius: width * 0.24
        color: Theme.accentSoft
        border.width: 1
        border.color: Theme.accentLine
        Text {
            anchors.centerIn: parent
            text: (root.name || root.icon || "?").replace(/^.*[./]/, "").charAt(0).toUpperCase()
            color: Theme.accent
            font.family: Theme.font
            font.pixelSize: parent.height * 0.5
            font.weight: Font.DemiBold
        }
    }
}
