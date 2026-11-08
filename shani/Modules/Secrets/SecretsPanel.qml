// Secrets (Secrets): native QML surface for password/key management.
// Replaces org.gnome.World.Secrets / org.gnome.seahorse.Application.
// Uses GPG for key management and launches seahorse for full GUI.
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services as Services

PanelWindow {
    id: win
    visible: Ui.secrets && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Services.Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-secrets"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property var keys: []
    property string status: ""
    property string generatedPassword: ""

    MouseArea { anchors.fill: parent; onClicked: Ui.secrets = false }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 600)
        height: Math.min(parent.height - 60, 550)
        radius: Theme.radiusLg

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Secrets & Keys"; font.bold: true; font.pixelSize: 18 }
                Button {
                    Layout.alignment: Qt.AlignRight
                    text: "✕"
                    flat: true
                    onClicked: Ui.secrets = false
                }
            }

            Label {
                text: win.status
                font.pixelSize: 11
                color: Theme.onSurfaceVariant
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            // GPG Keys section
            Label { text: "GPG Keys"; font.bold: true; font.pixelSize: 14 }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                clip: true
                model: win.keys
                delegate: ItemDelegate {
                    width: parent.width
                    text: modelData
                    font.pixelSize: 11
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    Layout.fillWidth: true
                    text: "Refresh keys"
                    onClicked: win.refreshKeys()
                }
                Button {
                    Layout.fillWidth: true
                    text: "Open Seahorse"
                    onClicked: { Quickshell.execDetached(["seahorse"]); Ui.secrets = false; }
                }
            }

            // Password generator
            Label { text: "Password Generator"; font.bold: true; font.pixelSize: 14 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    Layout.fillWidth: true
                    text: win.generatedPassword
                    readOnly: true
                    font.family: "monospace"
                }
                Button {
                    text: "Generate"
                    onClicked: win.generatePassword()
                }
                Button {
                    text: "Copy"
                    enabled: win.generatedPassword !== ""
                    onClicked: { Quickshell.clipboardText = win.generatedPassword; win.status = "Copied to clipboard"; }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: "Length:"; font.pixelSize: 12 }
                SpinBox {
                    from: 8; to: 64; value: 16
                    onValueChanged: win.pwLength = value
                }
                CheckBox { text: "Symbols"; checked: true; onToggled: win.pwSymbols = checked }
                CheckBox { text: "Numbers"; checked: true; onToggled: win.pwNumbers = checked }
            }

            Button { Layout.fillWidth: true; text: "Close"; onClicked: Ui.secrets = false }
        }
    }

    property int pwLength: 16
    property bool pwSymbols: true
    property bool pwNumbers: true

    Process {
        id: keyProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.trim());
                win.keys = lines;
                win.status = "Found " + lines.length + " key(s)";
            }
        }
    }

    function refreshKeys() {
        win.status = "Loading keys...";
        keyProc.command = ["gpg", "--list-keys", "--with-colons"];
        keyProc.running = true;
    }

    function generatePassword() {
        const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" +
            (win.pwNumbers ? "0123456789" : "") +
            (win.pwSymbols ? "!@#$%^&*()_+-=[]{}|;:,.<>?" : "");
        let pw = "";
        for (let i = 0; i < win.pwLength; i++) {
            pw += chars[Math.floor(Math.random() * chars.length)];
        }
        win.generatedPassword = pw;
        win.status = "Generated " + win.pwLength + "-char password";
    }

    Component.onCompleted: { win.refreshKeys(); }
    Keys.onEscapePressed: Ui.secrets = false
}