// The way back to a hidden screen keyboard, on a computer that types on the screen
// (a touchscreen, or no keyboard at all - InputKinds): a small round button at
// the bottom-right edge. Only the button is on the surface (its own size, no
// exclusive zone), so nothing else is covered or pushed. Settings > Keyboard &
// input > "Keyboard button when hidden" takes it away; it also goes while a
// physical keyboard is in use on a convertible (tablet mode off).
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: !Osk.shown && !Lock.locked && Settings.data.oskButton && InputKinds.typesOnScreen
        && !(InputKinds.keyboard && TabletMode.known && !TabletMode.on)
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { bottom: true; right: true }
    margins { bottom: 18; right: 18 }
    implicitWidth: 52
    implicitHeight: 52
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "shani-osk-button"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    Glass {
        anchors.fill: parent
        radius: width / 2
        strong: true
        IconButton {
            anchors.centerIn: parent
            size: 46
            icon: "input-keyboard"
            tip: Tr.t("Show keyboard")
            onClicked: Osk.toggle()
        }
    }
}
