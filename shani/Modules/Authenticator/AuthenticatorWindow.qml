// Authenticator: the six-digit codes websites and apps ask for after the
// password (two-factor, TOTP). A click copies one. Adding one is pointing at
// the QR code the website shows - on this screen - or typing its setup key.
// The secrets are the keyring's (bridge/otp.py); the shell never keeps them.
// Codes for signing in to this computer itself are Cassini's (Security).
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Authenticator"
    visible: Ui.authenticator
    onGone: Ui.authenticator = false
    implicitWidth: 520
    implicitHeight: 470

    readonly property string tool: Quickshell.env("SHANI_OTP_TOOL") || "/usr/lib/shani-shell/otp.py"
    property var accounts: []
    property bool available: true
    property string note: ""
    property bool adding: false
    property string removing: ""                // an id asked once, removed on the second
    property string copied: ""

    function refresh() { if (!lister.running) lister.running = true; }
    function run(args) { writer.command = ["python3", win.tool].concat(args); writer.running = true; }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()
    // the codes turn over every period: read again on the turn (and once a second, the time left)
    property int tick: 0
    Timer { interval: 1000; running: win.visible; repeat: true; onTriggered: { win.tick++; if (win.accounts.some(a => (Math.floor(Date.now() / 1000) % a.period) === 0)) win.refresh(); } }
    Process {
        id: lister
        command: ["python3", win.tool, "list"]
        stdout: StdioCollector { onStreamFinished: { try { win.accounts = JSON.parse(text); win.available = true; } catch (e) {} } }
        onExited: code => { if (code === 2) win.available = false; }
    }
    Process {
        id: writer
        stdout: StdioCollector { id: wrote }
        stderr: StdioCollector { id: wroteErr }
        onExited: code => {
            if (code === 0) {
                try { const r = JSON.parse(wrote.text); win.note = r.issuer !== undefined ? Tr.t("Added: %1").arg([r.issuer, r.account].filter(x => x).join(" · ")) : ""; } catch (e) {}
                win.adding = false;
            } else
                win.note = (wroteErr.text.trim().split("\n").pop() || "").replace(/^otp: /, "");
            win.refresh();
        }
    }
    // a code on a YubiKey that wants a touch: asked for, and copied when the key gives it
    property string touching: ""
    Process {
        id: keyCode
        stdout: StdioCollector {
            onStreamFinished: {
                try { const r = JSON.parse(text); Quickshell.clipboardText = r.code; win.copied = win.touching; copiedTimer.restart(); } catch (e) {}
                win.touching = "";
            }
        }
    }
    function copy(a) {
        // the key's codes behind a password: ykman asks for it in a terminal (never on a
        // command line) and remembers it, so the codes read from then on
        if (a.locked) {
            Quickshell.execDetached([Settings.data.terminal || "footclient", "-e", "sh", "-c",
                'ykman oath access remember; echo; read -p "Done - press Enter to close." x']);
            return;
        }
        if (a.touch) {
            win.touching = a.id;
            keyCode.command = ["python3", win.tool, "key-code", a.name];
            keyCode.running = true;
            return;
        }
        Quickshell.clipboardText = a.code;
        win.copied = a.id;
        copiedTimer.restart();
    }
    Timer { id: copiedTimer; interval: 1500; onTriggered: win.copied = "" }
    Timer { id: removeTimer; interval: 4000; onTriggered: win.removing = "" }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.authenticator = false

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button { kind: "primary"; text: Tr.t("Scan a QR code on the screen"); enabled: win.available && !writer.running; onClicked: { win.note = Tr.t("Draw a box round the QR code…"); win.run(["scan-screen"]); } }
                Button { text: win.adding ? Tr.t("Cancel") : Tr.t("Enter a setup key"); flat: true; onClicked: win.adding = !win.adding }
                Item { Layout.fillWidth: true }
            }
            Text {
                Layout.fillWidth: true
                visible: win.note !== ""
                text: win.note
                color: Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
            }

            // ---- by hand: where the website offers "can't scan it?" ----
            ColumnLayout {
                Layout.fillWidth: true
                visible: win.adding
                spacing: 6
                TextField { id: issuer; Layout.fillWidth: true; placeholder: Tr.t("The website or app — GitHub, Google…"); label: Tr.t("Issuer") }
                TextField { id: account; Layout.fillWidth: true; placeholder: Tr.t("Your account there — you@example.com"); label: Tr.t("Account") }
                TextField { id: key; Layout.fillWidth: true; placeholder: Tr.t("The setup key it shows (letters and digits)"); label: Tr.t("Setup key"); secret: true }
                Button {
                    Layout.alignment: Qt.AlignRight
                    kind: "primary"
                    text: Tr.t("Add")
                    enabled: key.text.trim() !== "" && (issuer.text.trim() !== "" || account.text.trim() !== "")
                    onClicked: { win.run(["add", JSON.stringify({ issuer: issuer.text, account: account.text, secret: key.text })]); key.text = ""; }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: win.accounts
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property int secondsLeft: { win.tick; return modelData.period - (Math.floor(Date.now() / 1000) % modelData.period); }
                    width: list.width
                    height: 72
                    radius: Theme.radiusSmall
                    color: rowArea.containsMouse ? Theme.hover : Theme.surface1
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.copy(row.modelData) }
                    KeyFocus { name: (row.modelData.issuer || row.modelData.account) + ", " + row.modelData.code; onActivated: win.copy(row.modelData) }
                    Accessible.role: Accessible.Button
                    Accessible.name: (row.modelData.issuer || row.modelData.account) + ": " + row.modelData.code.split("").join(" ")
                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 8 }
                        spacing: 12
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { Layout.fillWidth: true; text: row.modelData.locked ? Tr.t("Your security key - click to unlock its codes") : (row.modelData.issuer || row.modelData.account) + (row.modelData.fromKey ? "  ·  " + Tr.t("on your security key") : ""); color: Theme.dim; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                            Text {
                                text: win.copied === row.modelData.id ? Tr.t("Copied")
                                      : row.modelData.locked ? Tr.t("Locked with a password")
                                      : row.modelData.touch ? (win.touching === row.modelData.id ? Tr.t("Touch your key now") : Tr.t("Touch your key"))
                                      : row.modelData.code.replace(/^(\d{3})(\d+)$/, "$1 $2")
                                color: row.secondsLeft <= 5 ? Theme.danger : Theme.text
                                font.family: Theme.mono
                                font.pixelSize: 26 * Theme.fontScale
                                font.weight: Font.DemiBold
                                font.letterSpacing: 2
                            }
                            Text { visible: !!row.modelData.issuer && !!row.modelData.account; text: row.modelData.account; color: Theme.faint; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
                        }
                        // the time left on this code
                        Item {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            Rectangle { anchors.fill: parent; radius: 15; color: "transparent"; border.width: 3; border.color: Theme.surface3 }
                            Text { anchors.centerIn: parent; text: row.secondsLeft; color: row.secondsLeft <= 5 ? Theme.danger : Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale; font.features: { "tnum": 1 } }
                        }
                        IconButton {
                            visible: !row.modelData.fromKey          // the key's codes are the key's to remove
                            size: 30
                            icon: win.removing === row.modelData.id ? "dialog-warning" : "user-trash"
                            on: win.removing === row.modelData.id
                            tip: win.removing === row.modelData.id ? Tr.t("Click again to remove - the website will still ask for a code") : Tr.t("Remove")
                            onClicked: {
                                if (win.removing !== row.modelData.id) { win.removing = row.modelData.id; removeTimer.restart(); return; }
                                win.removing = "";
                                win.run(["remove", row.modelData.id]);
                            }
                        }
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    icon: "dialog-password"
                    title: win.available ? Tr.t("No codes yet") : Tr.t("The keyring is not running")
                    subtitle: win.available ? Tr.t("When a website offers two-factor sign-in, scan its QR code") : Tr.t("It starts when you sign in; the codes are kept there")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: Tr.t("A code to sign in to this computer itself is set up in Cassini."); color: Theme.faint; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
                Button { flat: true; text: Tr.t("Sign-in codes…"); onClicked: Quickshell.execDetached(["shani-cassini", "--section=totp"]) }
            }
        }
    }
}
