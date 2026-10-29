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
        implicitWidth: 420
        implicitHeight: card.implicitHeight
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "shani-display-confirm"
        // blur behind the card, as on every shell surface (ext-background-effect)
        BackgroundEffect.blurRegion: Settings.data.blur && visible ? blurArea : null
        Region { id: blurArea; item: card; radius: card.radius }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: modelData === Quickshell.screens[0] ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Glass {
            id: card
            width: parent.width
            implicitHeight: col.implicitHeight + 36
            strong: true
            radius: Theme.radiusLarge
            focus: true
            Keys.onEscapePressed: Displays.revert()
            Keys.onReturnPressed: Displays.keep()
            ColumnLayout {
                id: col
                x: 18
                y: 18
                width: parent.width - 36
                spacing: 10
                RowLayout {
                    spacing: 10
                    Icon { name: "video-display"; size: 22; color: Theme.accent }
                    Text { text: Tr.t("Keep these display settings?"); color: Theme.text; font.family: Theme.font; font.pixelSize: 15 * Theme.fontScale; font.weight: Font.DemiBold }
                }
                Text {
                    Layout.fillWidth: true
                    text: "Going back to the previous ones in " + Displays.countdown + " s."
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 8
                    Button { text: Tr.t("Revert"); onClicked: Displays.revert() }
                    Button { kind: "primary"; text: Tr.t("Keep"); onClicked: Displays.keep() }
                }
            }
        }
    }
}
