// The SIM's PIN, or a text to send (Modem) — a small card under the bar.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    readonly property string mode: Ui.modemDialog       // "pin" | "sms" | ""
    visible: mode !== "" && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors.top: true
    margins.top: 80
    implicitWidth: 400
    implicitHeight: card.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-modem"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.data.blur && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Ui.modemDialog = ""; Modem.error = ""; }
    Glass {
        id: card
        width: parent.width
        implicitHeight: col.implicitHeight + 36
        strong: true
        radius: Theme.radiusLarge
        Keys.onEscapePressed: win.close()
        ColumnLayout {
            id: col
            x: 18
            y: 18
            width: parent.width - 36
            spacing: 10
            RowLayout {
                spacing: 10
                Icon { name: win.mode === "pin" ? "network-cellular-offline" : "mail-send"; size: 22; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: win.mode === "pin" ? "Unlock the SIM card" : "New text message"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
            }
            TextField {
                id: pin
                Layout.fillWidth: true
                visible: win.mode === "pin"
                placeholder: Tr.t("PIN")
                secret: true
                onVisibleChanged: if (visible) { text = ""; input.forceActiveFocus(); }
                onAccepted: { Modem.unlock(text); text = ""; }
            }
            TextField {
                id: to
                Layout.fillWidth: true
                visible: win.mode === "sms"
                placeholder: Tr.t("To — +91 98…")
                onVisibleChanged: if (visible) { text = Ui.smsTo; (text ? body : to).input.forceActiveFocus(); }
                onAccepted: body.input.forceActiveFocus()
            }
            TextField {
                id: body
                Layout.fillWidth: true
                visible: win.mode === "sms"
                placeholder: Tr.t("Message")
                onVisibleChanged: if (visible) text = ""
                onAccepted: send.clicked()
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: Modem.error
                color: Theme.danger
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8
                Button { text: Tr.t("Cancel"); onClicked: win.close() }
                Button {
                    id: send
                    kind: "primary"
                    text: win.mode === "pin" ? "Unlock" : "Send"
                    onClicked: {
                        if (win.mode === "pin") {
                            Modem.unlock(pin.text);
                            pin.text = "";
                        } else if (to.text.trim() && body.text.trim()) {
                            Modem.text(to.text.trim(), body.text.trim());
                            win.close();
                        }
                    }
                }
            }
        }
    }
    // a PIN that worked closes the card
    Connections {
        target: Modem
        function onModemChanged() { if (win.mode === "pin" && Modem.modem && Modem.modem.locked === "") win.close(); }
    }
}
