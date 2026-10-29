// Bluetooth pairing, asked in the shell: confirm the code both screens show,
// type a PIN for an old device, or read the code to type on a keyboard.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    readonly property var ask: BtAgent.ask
    readonly property var show: BtAgent.show
    readonly property bool typed: ask !== null && (ask.ask === "pin" || ask.ask === "passkey")
    visible: (ask !== null || show !== null) && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors.top: true
    margins.top: 80
    implicitWidth: 380
    implicitHeight: card.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-pair"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.data.blur && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: typed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

    Glass {
        id: card
        width: parent.width
        implicitHeight: col.implicitHeight + 36
        strong: true
        radius: Theme.radiusLarge
        ColumnLayout {
            id: col
            x: 18
            y: 18
            width: parent.width - 36
            spacing: 10
            RowLayout {
                spacing: 10
                Icon { name: "bluetooth-active"; size: 22; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: win.show ? "Pairing with " + win.show.device
                        : win.ask ? (win.ask.ask === "authorize" ? win.ask.device + " wants to connect" : "Pair with " + win.ask.device + "?") : ""
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                }
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: win.show ? (win.show.show === "passkey" ? "Type this on it, then press Enter:" : "Enter this PIN on it:")
                    : win.ask && win.ask.ask === "confirm" ? "Pair only if it shows the same code:"
                    : win.typed ? "Type the " + (win.ask.ask === "pin" ? "PIN" : "code") + " it shows (often 0000 or 1234):" : ""
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
                wrapMode: Text.Wrap
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: text !== ""
                text: win.show ? (win.show.passkey || win.show.pin || "") : win.ask && win.ask.passkey ? win.ask.passkey : ""
                color: Theme.text
                font.family: Theme.mono
                font.pixelSize: 30 * Theme.fontScale
                font.letterSpacing: 6
                Accessible.name: "Pairing code " + text.split("").join(" ")
            }
            TextField {
                id: code
                Layout.fillWidth: true
                visible: win.typed
                placeholder: Tr.t("Code")
                onVisibleChanged: if (visible) { text = ""; input.forceActiveFocus(); }
                onAccepted: BtAgent.answer(true, text.trim())
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8
                Button {
                    text: win.show ? "Close" : "Cancel"
                    onClicked: win.show ? BtAgent.dismiss() : BtAgent.answer(false)
                }
                Button {
                    visible: win.ask !== null
                    kind: "primary"
                    text: win.ask && win.ask.ask === "authorize" ? "Allow" : "Pair"
                    onClicked: BtAgent.answer(true, code.text.trim())
                }
            }
        }
    }
}
