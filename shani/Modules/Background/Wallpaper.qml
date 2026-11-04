// The wallpaper, drawn by the shell on the background layer of every screen —
// so the settings page can change it live (with a cross-fade), and the lock
// screen and greeter show the same picture.
//
// The overview's backdrop (behind the zoomed-out workspaces) gets its own copy,
// made only while the overview is open: niri's layer rule places the
// "shani-backdrop" surface there. The wallpaper itself is not moved there - a
// surface in the backdrop is hidden behind the workspaces the rest of the
// time, and niri then asks it for a frame every second, which redrew the whole
// picture once a second, idle.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services

Variants {
    model: Quickshell.screens
    Scope {
    id: scr
    required property var modelData
    LazyLoader {
        active: Niri.overviewOpen
        PanelWindow {
            screen: scr.modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.bg
            WlrLayershell.namespace: "shani-backdrop"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(parent.width, parent.height)
                source: Theme.wallpaper ? "file://" + Theme.wallpaper : ""
            }
        }
    }
    PanelWindow {
        screen: scr.modelData
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: Theme.bg
        WlrLayershell.namespace: "shani-wallpaper"
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // two images, so a change fades from the old picture to the new one
        property string shown: ""
        readonly property string wanted: {
            if (Settings.data.wallpaperPerMonitor) {
                const perMon = Settings.data.wallpapersByMonitor || {};
                const monWall = perMon[scr.modelData.name];
                if (monWall) return monWall;
            }
            return Theme.wallpaper;
        }
        onWantedChanged: swap()
        Component.onCompleted: swap()
        function swap() {
            const next = a.opacity > 0.5 ? b : a;
            const src = wanted ? "file://" + wanted : "";
            if (next.source == src) {
                // the hidden image already holds that exact file: assigning the
                // same source is a no-op and Ready never fires again — clear it
                // first so the toggle always completes (and fades)
                next.source = "";
                Qt.callLater(() => next.source = src);
            } else {
                next.source = src;
            }
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
}
