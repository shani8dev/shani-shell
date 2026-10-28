// The polkit agent's dialog: what is asking, as whom, and the prompt PAM gives
// (usually the password; sometimes a fingerprint message with no field).
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    readonly property var flow: Polkit.flow
    visible: Polkit.active && flow !== null
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: if (visible) pass.input.forceActiveFocus()

    Glass {
        strong: true
        anchors.centerIn: parent
        width: 440
        height: form.implicitHeight + 44
        radius: Theme.radiusLarge

        ColumnLayout {
            id: form
            anchors.fill: parent
            anchors.margins: 22
            spacing: 12

            RowLayout {
                spacing: 10
                Icon { name: "dialog-password"; size: 26; color: Theme.accent }
                Text {
                    text: "Authentication required"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
            }
            Text {
                Layout.fillWidth: true
                text: win.flow ? win.flow.message : ""
                color: Theme.text
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: 13
            }
            Text {
                Layout.fillWidth: true
                text: win.flow && win.flow.selectedIdentity ? "As " + win.flow.selectedIdentity.string : ""
                visible: text !== ""
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 12
            }
            TextField {
                id: pass
                Layout.fillWidth: true
                visible: win.flow && win.flow.isResponseRequired
                placeholder: win.flow ? (win.flow.inputPrompt || "Password").replace(/:\s*$/, "") : "Password"
                secret: win.flow ? !win.flow.responseVisible : true
                onAccepted: {
                    win.flow.submit(text);
                    text = "";
                }
            }
            Text {
                Layout.fillWidth: true
                readonly property string msg: Polkit.error || (win.flow ? win.flow.supplementaryMessage : "")
                visible: msg !== ""
                text: msg
                color: Polkit.error || (win.flow && win.flow.supplementaryIsError) ? Theme.danger : Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: 12
            }
            Text {
                Layout.fillWidth: true
                text: win.flow ? win.flow.actionId : ""
                color: Theme.faint
                elide: Text.ElideMiddle
                font.family: Theme.mono
                font.pixelSize: 10
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancel"; onClicked: win.flow.cancelAuthenticationRequest() }
                Button {
                    text: "Authenticate"
                    kind: "primary"
                    onClicked: {
                        win.flow.submit(pass.text);
                        pass.text = "";
                    }
                }
            }
        }
    }
}
