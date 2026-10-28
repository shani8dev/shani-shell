// A symbolic theme icon (Adwaita, see shell.qml's IconTheme pragma), recoloured
// to any token: symbolic SVGs are single-colour, so colorization is exact.
import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects

Item {
    id: root
    property string name
    property color color: Theme.text
    property real size: 18

    implicitWidth: size
    implicitHeight: size

    IconImage {
        id: img
        anchors.fill: parent
        source: root.name === "" ? "" : Quickshell.iconPath(root.name.endsWith("-symbolic") ? root.name : root.name + "-symbolic", true)
        visible: false
    }

    MultiEffect {
        anchors.fill: img
        source: img
        colorization: 1.0
        colorizationColor: root.color
        brightness: 1.0
    }
}
