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
    // the list as it is shown: everything, or what the search box matches on
    // the label, the collection or any of the item's attributes
    readonly property var visibleItems: {
        const q = search.text.trim().toLowerCase();
        if (q === "") return items;
        return items.filter(i => {
            const attrs = Object.values(i.attributes || {}).join(" ");
            return [i.label, i.collection, attrs].filter(x => x)
                .join(" ").toLowerCase().indexOf(q) >= 0;
        });
    }
    property string defaultCollection: ""
    property var keys: []
    property var passkeys: []             // [{ label, id, created }] — a metadata registry, not real credentials
    property bool addingPasskey: false
    property string removingPasskey: ""
    property string error: ""
    property string note: ""
    property string shownPath: ""             // the item whose secret is on screen
    property string shownSecret: ""
    property string removing: ""              // asked once, gone on the second click
    property string changing: ""              // the item whose secret is being changed
    property bool adding: false
    property var duplicate: null              // existing item found when adding the same site/label
    property bool newKey: false
    // password audit: computed in the bridge (which can reveal secrets) and
    // returned as counts/labels only. Computing it here from `items` always
    // reported zero because the list deliberately has no `secret` field.
    property var auditResults: ({ weak: [], reused: [], total: 0 })
    readonly property int weakCount: auditResults.weak.length
    readonly property int reusedCount: auditResults.reused.length
    readonly property bool hasIssues: weakCount > 0 || reusedCount > 0
    function runAudit() { auditProc.running = true; }
    Process {
        id: auditProc
        command: ["python3", win.tool, "audit"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    win.auditResults = r.weak ? r : { weak: [], reused: [], total: 0 };
                } catch (e) { win.auditResults = { weak: [], reused: [], total: 0 }; }
            }
        }
    }
    // the audit decrypts every keyring item: opt in, or use the explicit button
    function refresh() { lister.running = true; keyLister.running = true; passkeyLister.running = true; if (Settings.data.passwordAuditEnabled === true) runAudit(); }
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
    Process {
        id: passkeyLister
        command: ["python3", win.tool, "passkey-list"]
        stdout: StdioCollector { onStreamFinished: { try { const r = JSON.parse(text); win.passkeys = Array.isArray(r) ? r : []; } catch (e) { win.passkeys = []; } } }
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
    // a screen lock must conceal a revealed secret before the timer gets to it
    Connections {
        target: Lock
        function onLockedChanged() {
            if (Lock.locked) { win.shownPath = ""; win.shownSecret = ""; hideTimer.stop(); }
        }
    }
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
    // only a real web address is worth an "open in browser" action - never file:, javascript:, etc.
    function siteUrl(i) {
        const a = i.attributes || {};
        const v = a.url || a.site || "";
        return /^https?:\/\/\S+$/i.test(v) ? v : "";
    }
    // an entry with the same label or site is probably the password being added twice
    function duplicateFor(label) {
        const key = (label || "").trim().toLowerCase();
        if (key === "") return null;
        return win.items.find(i => {
            const a = i.attributes || {};
            return (i.label || "").trim().toLowerCase() === key
                || (a.site || "").trim().toLowerCase() === key
                || (a.url || "").trim().toLowerCase() === key;
        }) || null;
    }
    function doAdd(onDone) {
        const label = newLabel.text.trim();
        const attrs = { site: label };
        if (newUser.text.trim()) attrs.username = newUser.text.trim();
        const secret = newSecret.text;
        win.run(["add", win.defaultCollection, label], JSON.stringify({ attributes: attrs, secret: secret }),
                r => { if (r.ok) { win.adding = false; newLabel.text = ""; newUser.text = ""; newSecret.text = ""; win.duplicate = null; if (onDone) onDone(); } });
    }
    function saveNew() {
        const dup = duplicateFor(newLabel.text);
        if (dup) { win.duplicate = dup; return; }
        win.duplicate = null;
        win.doAdd();
    }
    function replaceDuplicate() {
        const dup = win.duplicate;
        win.duplicate = null;
        if (!dup) return;
        // add first, then remove the old entry: a failed add must never destroy it
        win.doAdd(() => win.run(["delete", dup.path], "", () => {}));
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(14)
        spacing: Theme.px(8)
        focus: true
        Keys.onEscapePressed: win.visible = false
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: [["passwords", Tr.t("Passwords")], ["gpg", Tr.t("GPG keys")], ["passkeys", Tr.t("Passkeys")]]
                Choice { required property var modelData; text: modelData[1]; selected: win.tab === modelData[0]; onClicked: win.tab = modelData[0] }
            }
            Choice { text: Tr.t("SSH keys…"); onClicked: Quickshell.execDetached(["shani-cassini", "--section=sshkeys"]) }
            Item { Layout.fillWidth: true }
            IconButton { icon: "view-refresh"; size: Theme.px(28); tip: Tr.t("Read again"); onClicked: win.refresh() }
        }
        // ---- password audit banner ----
        Rectangle {
            visible: win.hasIssues && win.tab === "passwords" && win.items.length > 0
            Layout.fillWidth: true
            implicitHeight: auditCol.implicitHeight + 16
            radius: Theme.radiusSmall
            color: Theme.alpha(Theme.amber, 0.12)
            border.width: 1
            border.color: Theme.alpha(Theme.amber, 0.3)
            ColumnLayout {
                id: auditCol
                anchors { fill: parent; margins: Theme.px(8) }
                spacing: Theme.px(2)
                RowLayout {
                    Layout.fillWidth: true
                    Icon { name: "dialog-warning"; size: Theme.px(16); color: Theme.amber }
                    Text {
                        text: win.weakCount > 0 && win.reusedCount > 0
                            ? Tr.t("%1 weak · %2 reused", win.weakCount, win.reusedCount)
                            : win.weakCount > 0 ? Tr.t("%1 weak password%2", win.weakCount, win.weakCount === 1 ? "" : "s")
                            : Tr.t("%1 reused password%2", win.reusedCount, win.reusedCount === 1 ? "" : "s")
                        color: Theme.amber
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                }
                Text {
                    visible: win.weakCount > 0
                    Layout.fillWidth: true
                    text: win.auditResults.weak.slice(0, 3).map(w => w.label).join(", ") + (win.weakCount > 3 ? "…" : "")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                    elide: Text.ElideRight
                }
                Text {
                    visible: win.reusedCount > 0
                    Layout.fillWidth: true
                    text: Tr.t("Reused: %1", win.auditResults.reused.slice(0, 2).map(r => r.items.join(", ")).join(" · "))
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                    elide: Text.ElideRight
                }
            }
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
            Button { text: Tr.t("Run security check"); tip: Tr.t("Reads every keyring item to find weak or reused passwords"); onClicked: win.runAudit(); }
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
                    onClicked: win.saveNew()
                }
            }
            ColumnLayout {
                visible: win.duplicate !== null
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Tr.t("You already have a password saved for %1.", win.duplicate ? win.duplicate.label : "")
                    color: Theme.amber
                    font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Button { text: Tr.t("Cancel"); flat: true; onClicked: win.duplicate = null }
                    Button { text: Tr.t("Save a copy"); flat: true; onClicked: { win.duplicate = null; win.doAdd(); } }
                    Button { kind: "primary"; text: Tr.t("Replace"); onClicked: win.replaceDuplicate() }
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
                    IconButton {
                        visible: win.siteUrl(prow.modelData) !== ""
                        icon: "web-browser"
                        size: Theme.px(26)
                        tip: Tr.t("Open site in browser")
                        onClicked: Qt.openUrlExternally(win.siteUrl(prow.modelData))
                    }
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
                    icon: "document-export"; size: Theme.px(26); tip: Tr.t("Export public key…")
                    onClicked: {
                        const uid = krow.modelData.uid || "";
                        const name = (uid.split("<")[0].trim().replace(/[^\w.-]+/g, "_") || krow.modelData.id) + ".asc";
                        FilePicker.open({ mode: "save", title: Tr.t("Export public key"), defaultName: name, filters: ["asc"],
                            onPicked: paths => {
                                if (!paths.length) return;
                                win.run(["gpg-export", krow.modelData.id, paths[0]], "", r => {
                                    if (r.path) win.note = Tr.t("Saved as %1", r.path.split("/").pop());
                                    else if (r.code === "exists") { win.error = ""; win.note = Tr.t("A file with that name already exists. Choose a different name."); }
                                });
                            }
                        });
                    }
                }
                IconButton {
                    icon: win.removing === krow.modelData.id ? "edit-delete" : "window-close"
                    size: Theme.px(26)
                    tip: win.removing === krow.modelData.id ? Tr.t("Click again: the key is deleted") : Tr.t("Delete")
                    onClicked: { if (win.removing === krow.modelData.id) { win.removing = ""; win.run(["gpg-delete", krow.modelData.id]); } else win.removing = krow.modelData.id; }
                }
            }
        }

        // ---- passkeys (a registry of references, not real WebAuthn credentials) ----
        Text {
            visible: win.tab === "passkeys"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Tr.t("Websites own real WebAuthn credentials; the shell keeps a keyring-protected REFERENCE to each (label, site, key-handle id), encrypted with your login. A site only accepts credentials registered through its own browser flow — the shell cannot mint one. When libfido2 tools are installed, genuinely local credentials can be created and used for challenge/response (not website logins).")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        RowLayout {
            visible: win.tab === "passkeys"
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Button { text: Tr.t("Add…"); onClicked: win.addingPasskey = !win.addingPasskey }
        }
        ColumnLayout {
            visible: win.tab === "passkeys" && win.addingPasskey
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField { id: newPasskeyLabel; Layout.fillWidth: true; placeholderText: Tr.t("What it is for, e.g. example.org") }
            TextField { id: newPasskeyRp; Layout.fillWidth: true; placeholderText: Tr.t("Site (RP id), e.g. example.org — optional") }
            RowLayout {
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: win.addingPasskey = false }
                Button {
                    kind: "primary"
                    text: Tr.t("Save")
                    enabled: newPasskeyLabel.text.trim() !== ""
                    onClicked: win.run(["passkey-add", newPasskeyLabel.text.trim()], JSON.stringify({ rp_id: newPasskeyRp.text.trim() }), r => {
                        if (r.ok) { win.addingPasskey = false; newPasskeyLabel.text = ""; newPasskeyRp.text = ""; }
                    })
                }
            }
        }
        ListView {
            reuseItems: true
            cacheBuffer: 400
            id: passkeyList
            visible: win.tab === "passkeys"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: win.passkeys
            delegate: RowLayout {
                id: prow
                required property var modelData
                width: passkeyList.width
                spacing: Theme.px(8)
                Icon { name: "dialog-password"; size: Theme.px(20); color: Theme.dim }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: prow.modelData.label || Tr.t("Unnamed"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: (prow.modelData.rp_id ? prow.modelData.rp_id + "  ·  " : "")
                            + (prow.modelData.source === "shell" ? Tr.t("Shell-created") : Tr.t("Browser reference"))
                            + (prow.modelData.created ? "  ·  " + Qt.formatDate(new Date(prow.modelData.created * 1000), "d MMM yyyy") : "")
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: prow.modelData.cred_id ? Tr.t("Key handle: %1", prow.modelData.cred_id.slice(0, 16)) : Tr.t("No local key handle")
                        color: Theme.faint; font.family: Theme.mono; font.pixelSize: Theme.px(9) * Theme.fontScale
                    }
                }
                IconButton { icon: "edit-copy"; size: Theme.px(26); tip: Tr.t("Copy the key-handle id"); onClicked: { Quickshell.clipboardText = prow.modelData.id; win.note = Tr.t("%1 id copied", prow.modelData.label) } }
                IconButton {
                    icon: win.removingPasskey === prow.modelData.id ? "edit-delete" : "window-close"
                    size: Theme.px(26)
                    tip: win.removingPasskey === prow.modelData.id ? Tr.t("Click again: the reference is deleted") : Tr.t("Delete")
                    onClicked: {
                        if (win.removingPasskey === prow.modelData.id) {
                            win.removingPasskey = "";
                            win.run(["passkey-delete", prow.modelData.id]);
                        } else win.removingPasskey = prow.modelData.id;
                    }
                }
            }
            EmptyState {
                anchors.centerIn: parent
                visible: passkeyList.count === 0
                icon: "dialog-password"
                title: Tr.t("No passkeys yet")
                subtitle: Tr.t("Add one to keep a reference to a passkey you use")
            }
        }
    }
}
