// Passwords and Keys (Seahorse parity): the passwords apps saved in the keyring
// (oo7, through the Secret Service) - found, shown, copied, changed, deleted, or
// a new one added - and your GPG keys - made, imported, exported, deleted. SSH
// keys are Cassini's page. Everything goes through bridge/passwords.py; a secret is
// shown only when asked, hidden again after half a minute, and copied through
// wl-copy's stdin (never a command line); the clipboard is cleared after 45 s.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Passwords and Keys"
    visible: Ui.passwords
    onGone: Ui.passwords = false
    implicitWidth: Theme.px(640)
    implicitHeight: Theme.px(600)

    readonly property string tool: Quickshell.env("SHANI_PASSWORDS_TOOL") || "/usr/lib/shani-shell/passwords.py"
    property string tab: "passwords"
    property var items: []
    property string defaultCollection: ""
    property var keys: []
    property string error: ""
    property string note: ""
    property string shownPath: ""             // the item whose secret is on screen
    property string shownSecret: ""
    property string removing: ""              // asked once, gone on the second click
    property string changing: ""              // the item whose secret is being changed
    property bool adding: false
    property bool newKey: false
    readonly property var visibleItems: items.filter(i => !search.text.trim() || (i.label + " " + JSON.stringify(i.attributes)).toLowerCase().indexOf(search.text.trim().toLowerCase()) >= 0)

    function refresh() { lister.running = true; keyLister.running = true; }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()

    Process {
        id: lister
        command: ["python3", win.tool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() }; }
                win.error = r.error ? Tr.t("The keyring could not be reached: %1", r.error) : "";
                win.items = r.items || [];
                win.defaultCollection = r["default"] || "";
                Ui.passwordsItems = win.items.map(i => i.label);
            }
        }
    }
    Process {
        id: keyLister
        command: ["python3", win.tool, "gpg-list"]
        stdout: StdioCollector { onStreamFinished: { try { win.keys = JSON.parse(text) || []; } catch (e) { win.keys = []; } Ui.passwordsKeys = win.keys.map(k => k.uid); } }
    }
    // one action at a time; stdin carries any secret
    Process {
        id: act
        property string payload: ""
        property var after: null
        stdinEnabled: true
        onStarted: { if (payload !== "") write(payload); payload = ""; stdinEnabled = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() }; }
                if (r.error) win.error = r.error; else win.error = "";
                if (act.after) act.after(r);
                win.refresh();
            }
        }
    }
    function run(args, payload, after) {
        if (act.running) return;
        act.command = ["python3", win.tool].concat(args);
        act.payload = payload || "";
        act.stdinEnabled = true;
        act.after = after || null;
        act.running = true;
    }
    function reveal(i) {
        if (win.shownPath === i.path) { win.shownPath = ""; win.shownSecret = ""; return; }
        run(["reveal", i.path], "", r => { if (r.secret !== undefined) { win.shownPath = i.path; win.shownSecret = r.secret; Ui.passwordsRevealed = i.label; hideTimer.restart(); } });
    }
    Timer { id: hideTimer; interval: 30000; onTriggered: { win.shownPath = ""; win.shownSecret = ""; } }
    function copy(i) {
        run(["reveal", i.path], "", r => {
            if (r.secret === undefined) return;
            copier.payload = r.secret;
            copier.running = true;
            win.note = Tr.t("%1 copied - the clipboard forgets it in 45 s", i.label);
            clearTimer.restart();
        });
    }
    Process { id: copier; property string payload: ""; command: ["wl-copy"]; stdinEnabled: true; onStarted: { write(payload); payload = ""; stdinEnabled = false; } onExited: stdinEnabled = true }
    Timer { id: clearTimer; interval: 45000; onTriggered: Quickshell.execDetached(["wl-copy", "--clear"]) }
    // what an item is for, from its attributes (a website, a Wi-Fi, an app's account)
    function about(i) {
        const a = i.attributes || {};
        const parts = [a.username || a.user || a.account || "", a.server || a.host || a.site || a.url || a.ssid || a.service || a["xdg:schema"] || ""];
        return parts.filter(x => x).join("  ·  ");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(14)
        spacing: Theme.px(8)
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: [["passwords", Tr.t("Passwords")], ["gpg", Tr.t("GPG keys")]]
                Choice { required property var modelData; text: modelData[1]; selected: win.tab === modelData[0]; onClicked: win.tab = modelData[0] }
            }
            Choice { text: Tr.t("SSH keys…"); onClicked: Quickshell.execDetached(["shani-cassini", "--section=sshkeys"]) }
            Item { Layout.fillWidth: true }
            IconButton { icon: "view-refresh"; size: Theme.px(28); tip: Tr.t("Read again"); onClicked: win.refresh() }
        }
        Text {
            visible: win.error !== "" || win.note !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: win.error !== "" ? win.error : win.note
            color: win.error !== "" ? Theme.danger : Theme.dim
            font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }

        // ---- passwords ----
        RowLayout {
            visible: win.tab === "passwords"
            Layout.fillWidth: true
            TextField { id: search; Layout.fillWidth: true; placeholderText: Tr.t("Find a password") }
            Button { text: Tr.t("Add…"); onClicked: win.adding = !win.adding }
        }
        ColumnLayout {
            visible: win.tab === "passwords" && win.adding
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField { id: newLabel; Layout.fillWidth: true; placeholderText: Tr.t("What it is for, e.g. example.org") }
            TextField { id: newUser; Layout.fillWidth: true; placeholderText: Tr.t("User name (optional)") }
            TextField { id: newSecret; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Password") }
            RowLayout {
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: win.adding = false }
                Button {
                    kind: "primary"
                    text: Tr.t("Save")
                    enabled: newLabel.text.trim() !== "" && newSecret.text !== "" && win.defaultCollection !== ""
                    onClicked: {
                        const attrs = { site: newLabel.text.trim() };
                        if (newUser.text.trim()) attrs.username = newUser.text.trim();
                        win.run(["add", win.defaultCollection, newLabel.text.trim()], JSON.stringify({ attributes: attrs, secret: newSecret.text }),
                                r => { if (r.ok) { win.adding = false; newLabel.text = ""; newUser.text = ""; newSecret.text = ""; } });
                    }
                }
            }
        }
        Text {
            visible: win.tab === "passwords" && win.error === "" && win.visibleItems.length === 0
            text: win.items.length ? Tr.t("Nothing matches") : Tr.t("No passwords saved yet")
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        ListView {
            reuseItems: true
            cacheBuffer: 400
            id: plist
            visible: win.tab === "passwords"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: win.visibleItems
            delegate: ColumnLayout {
                id: prow
                required property var modelData
                width: plist.width
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Icon { name: "dialog-password"; size: Theme.px(20); color: Theme.dim }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: prow.modelData.label; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: win.shownPath === prow.modelData.path ? win.shownSecret : win.about(prow.modelData)
                            color: win.shownPath === prow.modelData.path ? Theme.accent : Theme.dim
                            font.family: win.shownPath === prow.modelData.path ? Theme.mono : Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                    }
                    IconButton { icon: win.shownPath === prow.modelData.path ? "view-conceal" : "view-reveal"; size: Theme.px(26); tip: win.shownPath === prow.modelData.path ? Tr.t("Hide %1", prow.modelData.label) : Tr.t("Show %1", prow.modelData.label); onClicked: win.reveal(prow.modelData) }
                    IconButton { icon: "edit-copy"; size: Theme.px(26); tip: Tr.t("Copy the password for %1", prow.modelData.label); onClicked: win.copy(prow.modelData) }
                    IconButton { icon: "document-edit"; size: Theme.px(26); tip: Tr.t("Change it"); onClicked: win.changing = win.changing === prow.modelData.path ? "" : prow.modelData.path }
                    IconButton {
                        icon: win.removing === prow.modelData.path ? "edit-delete" : "window-close"
                        size: Theme.px(26)
                        tip: win.removing === prow.modelData.path ? Tr.t("Click again: %1 is deleted", prow.modelData.label) : Tr.t("Delete")
                        onClicked: { if (win.removing === prow.modelData.path) { win.removing = ""; win.run(["delete", prow.modelData.path]); } else win.removing = prow.modelData.path; }
                    }
                }
                RowLayout {
                    visible: win.changing === prow.modelData.path
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(28)
                    TextField { id: changed; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("The new password") }
                    Button { text: Tr.t("Save"); enabled: changed.text !== ""; onClicked: { win.run(["set", prow.modelData.path], changed.text, r => { if (r.ok) { win.changing = ""; changed.text = ""; } }); } }
                }
            }
        }

        // ---- GPG keys ----
        RowLayout {
            visible: win.tab === "gpg"
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Button { text: Tr.t("Import…"); onClicked: FilePicker.open({ mode: "open", title: Tr.t("A key to import"), onPicked: paths => { if (paths.length) win.run(["gpg-import", paths[0]]); } }) }
            Button { text: Tr.t("New key…"); onClicked: win.newKey = !win.newKey }
        }
        ColumnLayout {
            visible: win.tab === "gpg" && win.newKey
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField { id: keyName; Layout.fillWidth: true; placeholderText: Tr.t("Your name") }
            TextField { id: keyMail; Layout.fillWidth: true; placeholderText: Tr.t("Your email address") }
            TextField { id: keyPass; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("A passphrase for it") }
            TextField { id: keyPass2; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("The passphrase again") }
            RowLayout {
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: win.newKey = false }
                Button {
                    kind: "primary"
                    text: act.running ? Tr.t("Making it…") : Tr.t("Make it")
                    enabled: !act.running && keyName.text.trim() !== "" && keyMail.text.indexOf("@") > 0 && keyPass.text !== "" && keyPass.text === keyPass2.text
                    onClicked: win.run(["gpg-new", keyName.text.trim(), keyMail.text.trim()], keyPass.text + "\n",
                                       r => { if (r.ok) { win.newKey = false; keyPass.text = ""; keyPass2.text = ""; } })
                }
            }
        }
        ListView {
            reuseItems: true
            cacheBuffer: 400
            id: klist
            visible: win.tab === "gpg"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: win.keys
            delegate: RowLayout {
                id: krow
                required property var modelData
                width: klist.width
                spacing: Theme.px(8)
                Icon { name: krow.modelData.secret ? "application-pgp-keys" : "contact-new"; size: Theme.px(20); color: Theme.dim }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: krow.modelData.uid || krow.modelData.id; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: [krow.modelData.secret ? Tr.t("yours") : Tr.t("someone else's"), krow.modelData.id,
                               krow.modelData.expires ? Tr.t("until %1", Qt.formatDate(new Date(krow.modelData.expires * 1000), "d MMM yyyy")) : Tr.t("no end date")].join("  ·  ")
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
                IconButton {
                    icon: "document-export"; size: Theme.px(26); tip: Tr.t("Save its public key in your home folder")
                    onClicked: win.run(["gpg-export", krow.modelData.id, Quickshell.env("HOME") + "/" + (krow.modelData.uid.split("<")[0].trim().replace(/[^\w.-]+/g, "_") || krow.modelData.id) + ".asc"],
                                       "", r => { if (r.path) win.note = Tr.t("Saved as %1", r.path.split("/").pop()); })
                }
                IconButton {
                    icon: win.removing === krow.modelData.id ? "edit-delete" : "window-close"
                    size: Theme.px(26)
                    tip: win.removing === krow.modelData.id ? Tr.t("Click again: the key is deleted") : Tr.t("Delete")
                    onClicked: { if (win.removing === krow.modelData.id) { win.removing = ""; win.run(["gpg-delete", krow.modelData.id]); } else win.removing = krow.modelData.id; }
                }
            }
        }
    }
}
