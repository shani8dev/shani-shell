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
        // the symbolic form, else the name as given, else a neutral one: a name
        // the theme lacks (Papirus has more than Adwaita) must never paint as an
        // empty white square
        source: {
            if (root.name === "")
                return "";
            const sym = root.name.endsWith("-symbolic") ? root.name : root.name + "-symbolic";
            return Quickshell.iconPath(sym, true) || Quickshell.iconPath(root.name.replace(/-symbolic$/, ""), true)
                || Quickshell.iconPath("preferences-system-symbolic", true);
        }
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
