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
            // no fallback (false): with true, iconPath always answers with the
            // theme's missing-icon placeholder, the || chain never runs, and a
            // name the theme lacks paints as an empty white square
            const sym = root.name.endsWith("-symbolic") ? root.name : root.name + "-symbolic";
            return Quickshell.iconPath(sym, false) || Quickshell.iconPath(root.name.replace(/-symbolic$/, ""), false)
                || Quickshell.iconPath("preferences-system-symbolic", false);
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
