// "Keep these display settings?" — on every screen, so it is seen on whichever
// one still shows a picture. Not answered in 15 s: Displays goes back.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

Variants {
    model: Quickshell.screens
    PanelWindow {
        id: win
        required property var modelData
        screen: modelData
        visible: Displays.pending && !Lock.locked
        anchors.top: true
        margins.top: 120
        implicitWidth: Theme.px(420)
        implicitHeight: card.implicitHeight
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "shani-display-confirm"
        // blur behind the card, as on every shell surface (ext-background-effect)
        BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
        Region { id: blurArea; item: card; radius: card.radius }
        WlrLayershell.layer: WlrLayer.Overlay
        // the modal must be answerable without a click, on whichever screen is in use
        property bool keyScreen: modelData === (Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0])
        WlrLayershell.keyboardFocus: keyScreen && !Lock.locked ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Glass {
            id: card
            width: parent.width
            implicitHeight: col.implicitHeight + 36
            strong: true
            radius: Theme.radiusLarge
            focus: true
            onVisibleChanged: if (visible && win.keyScreen) forceActiveFocus()
            Accessible.role: Accessible.Dialog
            Accessible.name: Tr.t("Keep these display settings?")
            Keys.onEscapePressed: Displays.revert()
            Keys.onReturnPressed: Displays.keep()
            ColumnLayout {
                id: col
                x: 18
                y: 18
                width: parent.width - 36
                spacing: Theme.px(10)
                RowLayout {
                    spacing: Theme.px(10)
                    Icon { name: "video-display"; size: Theme.px(22); color: Theme.accent }
                    Text { text: Tr.t("Keep these display settings?"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(15) * Theme.fontScale; font.weight: Font.DemiBold }
                }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Going back to the previous ones in %1 s.").arg(Displays.countdown)
                    Accessible.name: text
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.px(3)
                    radius: Theme.px(2)
                    color: Theme.surface3
                    Rectangle {
                        width: parent.width * Math.min(1, Math.max(0, Displays.countdown / 15))
                        height: parent.height
                        radius: parent.radius
                        color: Theme.amber
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Theme.px(8)
                    Button { text: Tr.t("Revert"); onClicked: Displays.revert() }
                    Button { kind: "primary"; text: Tr.t("Keep"); onClicked: Displays.keep() }
                }
            }
        }
    }
}
