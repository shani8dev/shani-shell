// The targets of a touchscreen's or a pen's calibration (Services/Calibrate),
// over the whole of its screen: touch the ring, and the next one comes. Only the
// device being calibrated is heard (a mouse click is not a touch); Escape stops.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services

PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => s.name === Calibrate.output) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.alpha(Theme.bg, 0.94)
    WlrLayershell.namespace: "shani-calibrate"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    readonly property var target: Calibrate.targets[Math.min(Calibrate.step, Calibrate.targets.length - 1)]

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Calibrate.cancel("cancelled")
    }
    Text {
        anchors.centerIn: parent
        width: parent.width * 0.6
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: (Calibrate.kind === "tablet" ? Tr.t("With the pen, touch the middle of the ring (%1 of 4)") : Tr.t("Touch the middle of the ring (%1 of 4)")).arg(Calibrate.step + 1)
              + "\n" + Tr.t("Escape stops, and keeps it as it was")
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.px(18) * Theme.fontScale
    }
    // the ring to touch
    Rectangle {
        x: win.target[0] * win.width - width / 2
        y: win.target[1] * win.height - height / 2
        width: Theme.px(56); height: width; radius: width / 2
        color: "transparent"
        border.width: 3
        border.color: Theme.accent
        Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Theme.accent }
    }
    TapHandler {
        acceptedDevices: Calibrate.kind === "tablet" ? PointerDevice.Stylus : PointerDevice.TouchScreen
        onTapped: p => Calibrate.touched(p.position.x / win.width, p.position.y / win.height)
    }
    // A way out for the finger or pen being calibrated: these devices often
    // have no keyboard, so Escape alone cannot cancel a bad first touch.
    // Declared after the full-screen handler so its own tap wins the grab.
    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: Theme.px(16) }
        width: Math.max(cancelLabel.implicitWidth + Theme.px(24), Theme.touchTarget)
        height: Math.max(Theme.px(36), Theme.touchTarget)
        radius: height / 2
        color: Theme.alpha(Theme.bg, 0.85)
        border.width: 1
        border.color: Theme.accent
        Accessible.role: Accessible.Button
        Accessible.name: Tr.t("Cancel")
        Text {
            id: cancelLabel
            anchors.centerIn: parent
            text: Tr.t("Cancel")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(14) * Theme.fontScale
        }
        TapHandler { onTapped: Calibrate.cancel("cancelled") }
    }
}
