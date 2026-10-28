// The wallpaper, drawn by the shell on the background layer of every screen —
// so the settings page can change it live (with a cross-fade), and the lock
// screen and greeter show the same picture.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common

Variants {
    model: Quickshell.screens
    PanelWindow {
        required property var modelData
        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: Theme.bg
        WlrLayershell.namespace: "shani-wallpaper"
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // two images, so a change fades from the old picture to the new one
        property string shown: ""
        readonly property string wanted: Theme.wallpaper
        onWantedChanged: swap()
        Component.onCompleted: swap()
        function swap() {
            const next = a.opacity > 0.5 ? b : a;
            next.source = wanted ? "file://" + wanted : "";
        }

        Image {
            id: a
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(parent.width, parent.height)
            opacity: 0
            onStatusChanged: if (status === Image.Ready) { opacity = 1; b.opacity = 0; }
            Behavior on opacity { NumberAnimation { duration: Theme.anim * 4 } }
        }
        Image {
            id: b
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(parent.width, parent.height)
            opacity: 0
            onStatusChanged: if (status === Image.Ready) { opacity = 1; a.opacity = 0; }
            Behavior on opacity { NumberAnimation { duration: Theme.anim * 4 } }
        }
    }
}
