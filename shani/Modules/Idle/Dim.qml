// The first idle stage: screens fade to dark a minute before the lock, so the
// lock never arrives unannounced. Any input wakes it (the idle monitor resets).
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Services

Variants {
    model: Quickshell.screens
    PanelWindow {
        required property var modelData
        screen: modelData
        visible: shade.opacity > 0
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "shani-dim"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}
        Rectangle {
            id: shade
            anchors.fill: parent
            color: "black"
            opacity: Idle.dimmed ? 0.55 : 0
            Behavior on opacity { NumberAnimation { duration: 1200 } }
        }
    }
}
