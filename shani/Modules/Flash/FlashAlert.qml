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

    // Rate guard: a burst of alerts must not strobe. Ignore restarts inside
    // one second, cap at 12 flashes/minute, and dim flashes after the first few.
    property int lastFlashAt: 0
    property int flashesThisMinute: 0
    Timer {
        id: minuteWindow
        interval: 60000
        onTriggered: win.flashesThisMinute = 0
    }
    Connections {
        target: Notifs
        function onAlerted(n) {
            if (!Settings.data.flashAlerts || Lock.locked)
                return;
            const now = Date.now();
            if (now - win.lastFlashAt < 1000 || win.flashesThisMinute >= 12)
                return;
            win.lastFlashAt = now;
            if (!minuteWindow.running) minuteWindow.restart();
            win.flashesThisMinute++;
            Ui.flashes++;
            Ui.lastFlash = n ? (n.summary || "") : "";
            glow.peak = win.flashesThisMinute > 3 ? 0.35 : 0.9;
            pulse.restart();
        }
    }
    Rectangle {
        id: glow
        anchors.fill: parent
        color: "transparent"
        border.width: Theme.px(14)
        border.color: Theme.accent
        opacity: 0
        property real peak: 0.9
        // a still glow under reduce motion: one long flash instead of two
        SequentialAnimation {
            id: pulse
            NumberAnimation { target: glow; property: "opacity"; to: glow.peak; duration: Settings.data.reduceMotion ? 0 : 120 }
            NumberAnimation { target: glow; property: "opacity"; to: Settings.data.reduceMotion ? glow.peak : 0.15; duration: Settings.data.reduceMotion ? 900 : 220 }
            NumberAnimation { target: glow; property: "opacity"; to: glow.peak; duration: Settings.data.reduceMotion ? 0 : 120 }
            NumberAnimation { target: glow; property: "opacity"; to: 0; duration: Theme.mot(400) }
        }
    }
}
