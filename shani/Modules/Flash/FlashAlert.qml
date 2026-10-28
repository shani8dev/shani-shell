// Flash for alerts (after Android's flash notifications and macOS's "flash the
// screen"): the screen's edge glows twice in the accent when a notification
// comes through — for those who do not hear the sound. Clicks pass through.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: glow.opacity > 0
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-flash"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Connections {
        target: Notifs
        function onAlerted(n) {
            if (!Settings.data.flashAlerts || Lock.locked)
                return;
            Ui.flashes++;
            pulse.restart();
        }
    }
    Rectangle {
        id: glow
        anchors.fill: parent
        color: "transparent"
        border.width: 14
        border.color: Theme.accent
        opacity: 0
        // a still glow under reduce motion: one long flash instead of two
        SequentialAnimation {
            id: pulse
            NumberAnimation { target: glow; property: "opacity"; to: 0.9; duration: Settings.data.reduceMotion ? 0 : 120 }
            NumberAnimation { target: glow; property: "opacity"; to: Settings.data.reduceMotion ? 0.9 : 0.15; duration: Settings.data.reduceMotion ? 900 : 220 }
            NumberAnimation { target: glow; property: "opacity"; to: 0.9; duration: Settings.data.reduceMotion ? 0 : 120 }
            NumberAnimation { target: glow; property: "opacity"; to: 0; duration: 400 }
        }
    }
}
