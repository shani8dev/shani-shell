// Authenticator: the six-digit codes websites and apps ask for after the
// password (two-factor, TOTP). A click copies one. Adding one is pointing at
// the QR code the website shows - on this screen - or typing its setup key.
// The secrets are the keyring's (bridge/otp.py); the shell never keeps them.
// Codes for signing in to this computer itself are managed in system sign-in settings.
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
    implicitWidth: Theme.px(520)
    implicitHeight: Theme.px(470)

    readonly property string tool: Quickshell.env("SHANI_OTP_TOOL") || "/usr/lib/shani-shell/otp.py"
    property var accounts: []
    property bool available: true
    property string note: ""
    readonly property string unlockNote: Tr.t("Unlock the key in the terminal…")
    property bool adding: false
    property string removing: ""                // an id asked once, removed on the second
    property string copied: ""
    // ---- finding and grouping codes ----
    property string searchText: ""              // mirrored from the search box
    property string groupFilter: ""             // "" all, else one issuer
    property bool grouped: false
    property int clipboardLeft: 0               // seconds until the copied code is wiped
    property string error: ""
    readonly property var issuers: {
        const out = [];
        win.accounts.forEach(a => {
            const name = a.issuer || Tr.t("Other");
            if (out.indexOf(name) < 0) out.push(name);
        });
        return out.sort((a, b) => String(a).localeCompare(String(b)));
    }
    readonly property var visibleAccounts: {
        const q = win.searchText.trim().toLowerCase();
        return win.accounts.filter(a => {
            if (win.groupFilter !== "" && (a.issuer || Tr.t("Other")) !== win.groupFilter) return false;
            if (q === "") return true;
            return [a.issuer, a.account].filter(x => x).join(" ").toLowerCase().indexOf(q) >= 0;
        });
    }

    function refresh() { if (!lister.running) lister.running = true; }
    function clearForm() { issuer.text = ""; account.text = ""; key.text = ""; }
    function run(args) {
        // `add` carries the shared secret: hand it over on stdin, never in argv
        writer.stdinEnabled = true;
        writer.payload = args[0] === "add" && args.length > 1 ? args[1] : "";
        writer.command = ["python3", win.tool].concat(writer.payload ? [args[0]] : args);
        writer.running = true;
    }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()
    // the codes turn over every period: read again just before the turn, not
    // only when a 1 s tick happens to land exactly on second zero
    property int tick: 0
    Timer {
        interval: 1000
        running: win.visible
        repeat: true
        onTriggered: {
            win.tick++;
            if (win.accounts.some(a => (Math.floor(Date.now() / 1000) % a.period) >= a.period - 1)) win.refresh();
            if (win.clipboardLeft > 0) win.clipboardLeft--;
        }
    }
    Process {
        id: lister
        command: ["python3", win.tool, "list"]
        stdout: StdioCollector { onStreamFinished: { try { win.accounts = JSON.parse(text); win.available = true; } catch (e) {} } }
        onExited: code => {
            if (code === 2) win.available = false;
            win.error = code === 0 ? "" : code === 2 ? Tr.t("The keyring is not running") : Tr.t("Could not read the codes");
        }
    }
    Process {
        id: writer
        property string payload: ""
        stdinEnabled: true
        onStarted: { if (payload) { write(payload + "\n"); payload = ""; stdinEnabled = false; } }
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
                try { const r = JSON.parse(text); win.copyClip(r.code); win.copied = win.touching; copiedTimer.restart(); } catch (e) {}
                win.touching = "";
            }
        }
    }
    function copy(a) {
        // the key's codes behind a password: ykman asks for it in a terminal (never on a
        // command line) and remembers it, so the codes read from then on
        if (a.locked) {
            win.note = win.unlockNote;
            unlockTimer.restart();
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
        win.copyClip(a.code);
        win.copied = a.id;
        copiedTimer.restart();
    }
    // A six-digit code slips past cliphist's "looks like a secret" filter, so
    // it would otherwise sit in clipboard history forever. Go through
    // wl-copy's stdin (never argv) and wipe on Passwords' own 45 s timer.
    function copyClip(text) {
        if (!text) return;
        if (clip.running) clip.running = false;
        clip.payload = text;
        clip.running = true;
        win.clipboardLeft = 45;
        clearTimer.restart();
    }
    Process {
        id: clip
        property string payload: ""
        command: ["wl-copy"]
        stdinEnabled: true
        onStarted: { write(payload); payload = ""; stdinEnabled = false; }
        onExited: stdinEnabled = true
    }
    Timer { id: clearTimer; interval: 45000; onTriggered: { Quickshell.execDetached(["wl-copy", "--clear"]); win.clipboardLeft = 0; } }
    // a locked screen must not leave a copied code in the clipboard history
    Connections {
        target: Lock
        function onLockedChanged() {
            if (Lock.locked) {
                Quickshell.execDetached(["wl-copy", "--clear"]);
                win.clipboardLeft = 0;
                win.copied = "";
            }
        }
    }
    Timer { id: copiedTimer; interval: 1500; onTriggered: win.copied = "" }
    Timer { id: removeTimer; interval: 4000; onTriggered: win.removing = "" }
    // the terminal opens on its own: don't leave "unlock the key" hanging forever
    Timer { id: unlockTimer; interval: 60000; onTriggered: { if (win.note === win.unlockNote) win.note = ""; } }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.authenticator = false
        Keys.onPressed: e => {
            if (!(e.modifiers & Qt.ControlModifier) || e.key !== Qt.Key_F) return;
            search.text = "";
            search.input.forceActiveFocus();
            e.accepted = true;
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(10)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button { kind: "primary"; text: Tr.t("Scan a QR code on the screen"); enabled: win.available && !writer.running; onClicked: { win.note = Tr.t("Draw a box round the QR code…"); win.run(["scan-screen"]); } }
                Button { text: win.adding ? Tr.t("Cancel") : Tr.t("Enter a setup key"); flat: true; onClicked: { win.adding = !win.adding; if (!win.adding) win.clearForm(); } }
                Item { Layout.fillWidth: true }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                TextField { id: search; Layout.fillWidth: true; placeholderText: Tr.t("Find a code"); label: Tr.t("Find a code"); onTextChanged: win.searchText = text }
                Text {
                    visible: win.searchText !== "" || win.groupFilter !== ""
                    text: win.visibleAccounts.length + " / " + win.accounts.length
                    color: Theme.faint
                    font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.role: Accessible.StatusBar
                    Accessible.name: text
                }
                IconButton {
                    visible: win.searchText !== ""
                    icon: "window-close"
                    size: Theme.px(24)
                    tip: Tr.t("Clear search")
                    onClicked: { search.text = ""; search.input.forceActiveFocus(); }
                }
                Button { text: win.grouped ? Tr.t("List") : Tr.t("Group by issuer"); flat: true; checked: win.grouped; onClicked: win.grouped = !win.grouped }
            }
            RowLayout {
                visible: win.issuers.length > 1
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Repeater {
                    model: [""].concat(win.issuers)
                    Choice {
                        required property string modelData
                        text: modelData === "" ? Tr.t("All") : modelData
                        selected: win.groupFilter === modelData
                        onClicked: win.groupFilter = win.groupFilter === modelData ? "" : modelData
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: win.note !== ""
                text: win.note
                color: Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
                Accessible.role: Accessible.StatusBar
                Accessible.name: text
            }
            Text {
                Layout.fillWidth: true
                visible: win.error !== ""
                text: win.error
                color: Theme.danger
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.Alert
                Accessible.name: text
            }
            Text {
                Layout.fillWidth: true
                visible: win.clipboardLeft > 0
                text: Tr.t("Code copied - clipboard clears in %1 s", win.clipboardLeft)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.StatusBar
                Accessible.name: text
            }

            // ---- by hand: where the website offers "can't scan it?" ----
            ColumnLayout {
                Layout.fillWidth: true
                visible: win.adding
                spacing: Theme.px(6)
                TextField { id: issuer; Layout.fillWidth: true; placeholder: Tr.t("The website or app — GitHub, Google…"); label: Tr.t("Issuer") }
                TextField { id: account; Layout.fillWidth: true; placeholder: Tr.t("Your account there — you@example.com"); label: Tr.t("Account") }
                TextField { id: key; Layout.fillWidth: true; placeholder: Tr.t("The setup key it shows (letters and digits)"); label: Tr.t("Setup key"); secret: true }
                Button {
                    Layout.alignment: Qt.AlignRight
                    kind: "primary"
                    text: Tr.t("Add")
                    enabled: key.text.trim() !== "" && (issuer.text.trim() !== "" || account.text.trim() !== "") && !writer.running
                    onClicked: { win.run(["add", JSON.stringify({ issuer: issuer.text, account: account.text, secret: key.text })]); win.clearForm(); }
                }
            }

            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.px(6)
                boundsBehavior: Flickable.StopAtBounds
                model: win.visibleAccounts
                section.property: win.grouped ? "issuer" : ""
                section.criteria: ViewSection.FullString
                section.labelPositioning: ViewSection.CurrentLabelAtStart | ViewSection.InlineLabels
                section.delegate: Rectangle {
                    width: list.width
                    height: Theme.px(26)
                    color: "transparent"
                    Text {
                        anchors { left: parent.left; leftMargin: Theme.px(14); verticalCenter: parent.verticalCenter }
                        text: section.label
                        color: Theme.faint
                        font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                        font.weight: Font.DemiBold
                        Accessible.role: Accessible.StaticText
                        Accessible.name: Tr.t("%1 codes", section.label)
                    }
                }
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property int secondsLeft: { win.tick; return modelData.period - (Math.floor(Date.now() / 1000) % modelData.period); }
                    width: list.width
                    height: Theme.px(72)
                    radius: Theme.radiusSmall
                    color: rowArea.containsMouse ? Theme.hover : Theme.surface1
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.copy(row.modelData) }
                    KeyFocus { name: (row.modelData.issuer || row.modelData.account) + ", " + row.modelData.code; onActivated: win.copy(row.modelData) }
                    Accessible.role: Accessible.Button
                    Accessible.name: (row.modelData.issuer || row.modelData.account) + ": " + row.modelData.code.split("").join(" ") + ", " + Tr.t("%1 seconds left").arg(row.secondsLeft)
                    RowLayout {
                        anchors { fill: parent; leftMargin: Theme.px(14); rightMargin: Theme.px(8) }
                        spacing: Theme.px(12)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { Layout.fillWidth: true; text: row.modelData.locked ? Tr.t("Your security key - click to unlock its codes") : (row.modelData.issuer || row.modelData.account) + (row.modelData.fromKey ? "  ·  " + Tr.t("on your security key") : ""); color: Theme.dim; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                            Text {
                                text: win.copied === row.modelData.id ? Tr.t("Copied")
                                      : row.modelData.locked ? Tr.t("Locked with a password")
                                      : row.modelData.touch ? (win.touching === row.modelData.id ? Tr.t("Touch your key now") : Tr.t("Touch your key"))
                                      : row.modelData.code.replace(/^(\d{3})(\d+)$/, "$1 $2")
                                color: row.secondsLeft <= 5 ? Theme.danger : Theme.text
                                font.family: Theme.mono
                                // "Touch your key" is a prompt, not a code —
                                // code-size type swamps the row
                                font.pixelSize: (row.modelData.touch || row.modelData.locked ? Theme.px(15) : Theme.px(26)) * Theme.fontScale
                                font.weight: Font.DemiBold
                                font.letterSpacing: row.modelData.touch || row.modelData.locked ? 0 : 2
                            }
                            Text { visible: !!row.modelData.issuer && !!row.modelData.account; text: row.modelData.account; color: Theme.faint; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                        }
                        // the time left on this code
                        StatusRing {
                            Layout.preferredWidth: Theme.px(30)
                            Layout.preferredHeight: Theme.px(30)
                            size: Theme.px(30)
                            thickness: Theme.px(3)
                            value: row.secondsLeft / row.modelData.period
                            color: row.secondsLeft <= 5 ? Theme.danger : Theme.accent
                            label: Tr.t("%1 seconds left").arg(row.secondsLeft)
                            Text { anchors.centerIn: parent; text: row.secondsLeft; color: row.secondsLeft <= 5 ? Theme.danger : Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.features: { "tnum": 1 } }
                        }
                        IconButton {
                            visible: !row.modelData.fromKey          // the key's codes are the key's to remove
                            enabled: !writer.running
                            size: Theme.px(30)
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
                    visible: list.count === 0 && !lister.running
                    icon: "dialog-password"
                    title: win.searchText !== "" || win.groupFilter !== "" ? Tr.t("Nothing matches") : win.available ? Tr.t("No codes yet") : Tr.t("The keyring is not running")
                    subtitle: win.available ? Tr.t("When a website offers two-factor sign-in, scan its QR code") : Tr.t("It starts when you sign in; the codes are kept there")
                    actionText: win.available ? "" : Tr.t("Try again")
                    action: win.refresh()
                }
            }
            RowLayout {
                Layout.fillWidth: true
    
            }
        }
    }
}
