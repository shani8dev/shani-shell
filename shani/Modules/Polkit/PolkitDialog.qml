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
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (visible) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // the screen keyboard: by itself without a working keyboard (InputKinds), a tap away always
    property bool kb: false
    Binding { target: Ui; property: "promptKeyboard"; value: win.kb && win.visible; when: win.visible }
    onVisibleChanged: if (visible) { pass.input.forceActiveFocus(); kb = InputKinds.typesOnScreen; }

    // polkit can replace the flow while this window is still up: a password
    // typed for the previous action (or a field left unmasked) must never
    // carry into the next one
    Connections {
        target: Polkit
        function onFlowChanged() {
            pass.text = "";
            pass.revealed = false;
            pass.input.forceActiveFocus();
        }
    }
    function submitPass() {
        if (!win.flow)
            return;
        win.flow.submit(pass.text);
        pass.text = "";
        pass.revealed = false;
    }
    function cancelPass() {
        if (win.flow)
            win.flow.cancelAuthenticationRequest();
    }

    Glass {
        id: blurCard
        Keys.onEscapePressed: win.cancelPass()
        strong: true
        anchors.centerIn: parent
        anchors.verticalCenterOffset: win.kb ? -parent.height * 0.18 : 0
        width: Theme.px(440)
        height: form.implicitHeight + 44
        radius: Theme.radiusLarge

        ColumnLayout {
            id: form
            anchors.fill: parent
            anchors.margins: Theme.px(22)
            spacing: Theme.px(12)

            RowLayout {
                spacing: Theme.px(10)
                Icon { name: "dialog-password"; size: Theme.px(26); color: Theme.accent }
                Text {
                    text: Tr.t("Authentication required")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(16) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
            }
            Text {
                Layout.fillWidth: true
                text: win.flow ? win.flow.message : ""
                color: Theme.text
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
            }
            Text {
                Layout.fillWidth: true
                text: win.flow && win.flow.selectedIdentity ? "As " + win.flow.selectedIdentity.string : ""
                visible: text !== ""
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(8)
            visible: pass.visible
            TextField {
                id: pass
                Layout.fillWidth: true
                visible: win.flow && win.flow.isResponseRequired
                placeholder: win.flow ? (win.flow.inputPrompt || "Password").replace(/:\s*$/, "") : "Password"
                secret: win.flow ? !win.flow.responseVisible : true
                onAccepted: win.submitPass()
            }
            IconButton { icon: "input-keyboard"; size: Theme.px(32); on: win.kb; tip: win.kb ? Tr.t("Hide keyboard") : Tr.t("Screen keyboard"); onClicked: win.kb = !win.kb }
            }
            Text {
                Layout.fillWidth: true
                readonly property string msg: Polkit.error || (win.flow ? win.flow.supplementaryMessage : "")
                visible: msg !== ""
                text: msg
                color: Polkit.error || (win.flow && win.flow.supplementaryIsError) ? Theme.danger : Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Text {
                Layout.fillWidth: true
                text: win.flow ? win.flow.actionId : ""
                color: Theme.faint
                elide: Text.ElideMiddle
                font.family: Theme.mono
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); onClicked: win.cancelPass() }
                Button {
                    text: Tr.t("Authenticate")
                    kind: "primary"
                    onClicked: win.submitPass()
                }
            }
        }
    }
    ScreenKeyboard {
        visible: win.kb && pass.visible
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.px(18)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(900, parent.width - 36)
        target: pass.input
        onEntered: win.submitPass()
        onHideRequested: win.kb = false
    }
}
