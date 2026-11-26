// A phone's navigation bar: Back, Home and Recents along the bottom edge, as a
// phone has them (a phone has no keys to go back with), and the keyboard at its
// end. Only on a phone-sized screen, below its dock of favourites; a tablet, a
// board and a handheld keep Back and the keyboard in the dock (Modules/Dock).
// Settings > Personalisation > Back and keyboard buttons turns it off.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: nav
    required property var modelData
    screen: modelData
    anchors { left: true; right: true; bottom: true }
    implicitHeight: Theme.px(44)
    exclusiveZone: implicitHeight
    color: Theme.alpha(Theme.bg, 0.92)
    WlrLayershell.namespace: "shani-phone-nav"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: Settings.data.navButtons && !Lock.locked && FormFactor.of(modelData.name).profile === "phone"

    component NavKey: Item {
        id: key
        property string icon
        property string label
        property bool lit: false
        signal pressed()
        Layout.fillWidth: true
        Layout.fillHeight: true
        Rectangle {
            anchors.centerIn: parent
            width: Theme.px(56); height: Theme.px(34); radius: height / 2
            color: area.pressed ? Theme.hover : "transparent"
        }
        Icon { anchors.centerIn: parent; name: key.icon; size: Theme.px(20); color: key.lit ? Theme.accent : Theme.text }
        MouseArea { id: area; anchors.fill: parent; onClicked: key.pressed() }
        KeyFocus { name: key.label; onActivated: key.pressed() }
        Accessible.role: Accessible.Button
        Accessible.name: key.label
        Accessible.onPressAction: key.pressed()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        NavKey { icon: "go-previous"; label: Tr.t("Back"); onPressed: Ui.back() }
        NavKey { icon: "go-home"; label: Tr.t("Home"); lit: Niri.desktopShown.length > 0; onPressed: Niri.showDesktop() }
        NavKey { icon: "focus-windows"; label: Tr.t("Recent apps"); lit: Niri.overviewOpen; onPressed: Niri.action("toggle-overview") }
        // held another way with auto-rotate off: turn the screen to match (a few seconds)
        NavKey { visible: AutoRotate.suggest !== ""; Layout.fillWidth: false; Layout.preferredWidth: Theme.px(56); icon: "object-rotate-right"; label: Tr.t("Rotate the screen"); lit: true; onPressed: AutoRotate.rotateToHeld() }
        NavKey { Layout.fillWidth: false; Layout.preferredWidth: Theme.px(56); icon: "input-keyboard"; label: Osk.shown ? Tr.t("Hide the keyboard") : Tr.t("Show the keyboard"); lit: Osk.shown; onPressed: Osk.toggle() }
    }
}
