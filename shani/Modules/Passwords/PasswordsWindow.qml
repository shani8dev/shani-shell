// Passwords and Keys (Seahorse parity): the passwords apps saved in the keyring
// (oo7, through the Secret Service) - found, shown, copied, changed, deleted, or
// a new one added - and your GPG keys - made, imported, exported, deleted. SSH
// keys are managed by the system. Everything goes through bridge/passwords.py; a secret is
// shown only when asked, hidden again after half a minute, and copied through
// wl-copy's stdin (never a command line); the clipboard is cleared after 45 s.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Modules.Passwords   // PasswordGenerator: a file read on first open does not see its folder by itself

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
    property var passkeyCaps: ({})        // what the keyring and the FIDO2 tools can do here
    property bool addingPasskey: false
    property string removingPasskey: ""
    property string error: ""
    property string note: ""
    // ---- vault details: folders, favourites, recent picks and secure notes ----
    // One keyring item under a fixed id holds this small JSON map. The bridge's
    // put/lookup carry it over stdin, so no note lands in a cleartext file and
    // nothing is ever handed to a command line.
    property var meta: ({})
    property bool metaDirty: false        // don't let an older lookup undo our own write
    property string folderFilter: ""          // "" all | "favourites" | "recent" | a folder
    property string draftPassword: ""         // the add form, mirrored for the live strength meter
    property string shownNotePath: ""
    property string uiLockedReason: ""         // "screen" | "idle" | "" - local, not a fake keyring lock
    property int clipboardLeft: 0
    property var collections: []
    readonly property bool uiLocked: win.uiLockedReason !== ""
    readonly property bool keyringLocked: !!win.collections.find(c => c.path === win.defaultCollection && c.locked)
    function metaKey(i) {
        if (!i) return "";
        return i.path || ((i.label || "") + "|" + ((i.attributes || {}).site || ""));
    }
    function metaFor(i) { return win.meta[win.metaKey(i)] || {}; }
    function categoryOf(i) {
        const a = i.attributes || {};
        return win.metaFor(i).category || a.category || a.folder || Tr.t("Other");
    }
    function isFav(i) { return !!win.metaFor(i).favorite; }
    function noteOf(i) { return win.metaFor(i).note || ""; }
    function isRecent(i) {
        const m = win.metaFor(i);
        return !!m.opened && (win.meta.recent || []).indexOf(win.metaKey(i)) >= 0;
    }
    readonly property var folders: {
        const out = [];
        win.items.forEach(i => {
            const c = win.categoryOf(i);
            if (c !== Tr.t("Other") && out.indexOf(c) < 0) out.push(c);
        });
        Object.keys(win.meta).forEach(k => {
            const c = win.meta[k].category;
            if (c && out.indexOf(c) < 0) out.push(c);
        });
        return out.sort((a, b) => String(a).localeCompare(String(b)));
    }
    readonly property var shownItems: {
        let out = win.visibleItems;
        if (win.folderFilter === "favourites") out = out.filter(i => win.isFav(i));
        else if (win.folderFilter === "recent") out = out.filter(i => win.isRecent(i));
        else if (win.folderFilter !== "") out = out.filter(i => win.categoryOf(i) === win.folderFilter);
        if (win.folderFilter === "recent")
            out = out.slice().sort((a, b) => (win.metaFor(b).opened || b.modified || 0) - (win.metaFor(a).opened || a.modified || 0));
        return out;
    }
    function remember(i) {
        const key = win.metaKey(i);
        if (!key) return;
        const next = JSON.parse(JSON.stringify(win.meta));
        const e = next[key] || (next[key] = {});
        e.opened = Date.now();
        next.recent = [key].concat((next.recent || []).filter(k => k !== key)).slice(0, 8);
        win.saveMeta(next);
    }
    function saveMeta(next) {
        win.meta = next;
        win.metaDirty = true;
        const blob = JSON.stringify({ secret: JSON.stringify(next) });
        metaWriter.command = ["python3", win.tool, "put", "shani-vault-meta"];
        if (metaWriter.running) metaWriter.nextPayload = blob;   // keep the last edit
        else { metaWriter.payload = blob; metaWriter.stdinEnabled = true; metaWriter.running = true; }
    }
    function setMetaField(i, field, value) {
        const key = win.metaKey(i);
        if (!key) return;
        const next = JSON.parse(JSON.stringify(win.meta));
        const e = next[key] || (next[key] = {});
        if (value === "") delete e[field]; else e[field] = value;
        win.saveMeta(next);
        win.note = Tr.t("Vault details saved");
    }
    function toggleFavorite(i) { win.setMetaField(i, "favorite", !win.isFav(i)); }
    function toggleNote(i) { win.shownNotePath = win.shownNotePath === i.path ? "" : i.path; win.remember(i); }
    // A local nudge, not a promise: length, character classes and the common
    // weak picks. No password is sent anywhere to be scored.
    function strength(p) {
        const pw = p || "";
        if (!pw) return { score: 0, label: Tr.t("Empty"), tip: Tr.t("Use at least 12 characters") };
        let kinds = 0;
        if (/[a-z]/.test(pw)) kinds++;
        if (/[A-Z]/.test(pw)) kinds++;
        if (/\d/.test(pw)) kinds++;
        if (/[^A-Za-z0-9]/.test(pw)) kinds++;
        let score = (pw.length >= 12 ? 2 : pw.length >= 8 ? 1 : 0) + (kinds >= 3 ? 1 : 0);
        if (pw.length >= 16 && kinds >= 3) score++;
        if (/^(password|123456|qwerty|letmein|admin|welcome)$/i.test(pw) || /^(\d)\1+$/.test(pw)) score = 0;
        score = Math.min(4, score);
        const labels = [Tr.t("Very weak"), Tr.t("Weak"), Tr.t("Fair"), Tr.t("Strong"), Tr.t("Very strong")];
        return { score: score, label: labels[score], tip: score <= 1 ? Tr.t("Use 12+ characters with upper, lower, digit and symbol") : Tr.t("Good - keep it unique to this site") };
    }
    readonly property var newStrength: win.strength(win.draftPassword)
    function poke() { if (win.uiLockedReason === "") idleTimer.restart(); }
    function generateForForm() {
        // Python's secrets via the shared script (Services/PasswordGen); the made
        // password only travels from stdout into the form on its way to stdin
        gen.command = PasswordGen.command(20, true, true, false);
        gen.running = true;
    }
    // Export/import vault *details* only: labels, folders, favourites and notes.
    // Passwords themselves never leave the keyring in a portable file.
    function exportVault(path) {
        const entries = win.items.map(i => ({ label: i.label || "", username: win.username(i), site: (i.attributes || {}).site || "", category: win.categoryOf(i), favorite: win.isFav(i), note: win.noteOf(i) }));
        exporter.payload = JSON.stringify({ format: "shani-vault-1", entries: entries }, null, 2);
        exporter.command = ["python3", "-c", 'import sys\nwith open(sys.argv[1], "x", encoding="utf-8") as f: f.write(sys.stdin.read())', path];
        exporter.stdinEnabled = true;
        exporter.running = true;
    }
    function importVault(path) {
        importer.command = ["python3", "-c", "import sys\nprint(open(sys.argv[1], encoding='utf-8').read())", path];
        importer.running = true;
    }
    Process {
        id: metaReader
        command: ["python3", win.tool, "lookup", "shani-vault-meta"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (metaWriter.running || win.metaDirty) return;    // our write is newer than this read
                try {
                    const r = JSON.parse(text);
                    const m = r.secret ? JSON.parse(r.secret) : {};
                    win.meta = (m && typeof m === "object" && !Array.isArray(m)) ? m : {};
                } catch (e) { win.meta = {}; }
            }
        }
    }
    Process {
        id: metaWriter
        property string payload: ""
        property string nextPayload: ""
        stdinEnabled: true
        onStarted: { if (payload) { write(payload); payload = ""; stdinEnabled = false; } }
        stdout: StdioCollector {}
        onExited: code => {
            stdinEnabled = true;
            if (code !== 0) win.error = Tr.t("Vault details could not be saved");
            if (nextPayload !== "") {
                payload = nextPayload; nextPayload = "";
                stdinEnabled = true; running = true;
            } else win.metaDirty = false;
        }
    }
    Process {
        id: gen
        stdout: StdioCollector {
            onStreamFinished: {
                const pw = text.trim();
                if (pw !== "") {
                    newSecret.text = pw;
                    win.note = Tr.t("Generated a password - check its strength before saving");
                }
            }
        }
        onExited: code => { if (code !== 0) win.error = Tr.t("Could not generate a password"); }
    }
    Process {
        id: exporter
        property string payload: ""
        stdinEnabled: true
        onStarted: { if (payload) { write(payload); payload = ""; stdinEnabled = false; } }
        stdout: StdioCollector {}
        onExited: code => {
            stdinEnabled = true;
            if (code === 0) win.note = Tr.t("Exported details for %1 entries - passwords stay in the keyring", win.items.length);
            else win.error = Tr.t("Could not export the vault details");
        }
    }
    Process {
        id: importer
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const next = JSON.parse(JSON.stringify(win.meta));
                    let count = 0;
                    (data.entries || []).forEach(e => {
                        const it = win.items.find(x => (x.label || "") === (e.label || ""));
                        if (!it) return;
                        const m = next[win.metaKey(it)] || (next[win.metaKey(it)] = {});
                        if (e.category) m.category = e.category;
                        if (e.favorite) m.favorite = true;
                        if (e.note) m.note = e.note;
                        count++;
                    });
                    win.saveMeta(next);
                    win.note = Tr.t("Imported details for %1 entr%2", count, count === 1 ? "y" : "ies");
                } catch (e) { win.error = Tr.t("That file is not a Shani vault export"); }
            }
        }
        onExited: code => { if (code !== 0) win.error = Tr.t("Could not read that file"); }
    }
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
    function refresh() {
        lister.running = true;
        keyLister.running = true;
        passkeyLister.running = true;
        capsLister.running = true;
        metaReader.running = true;
        if (Settings.data.passwordAuditEnabled === true) runAudit();
    }
    onVisibleChanged: if (visible) { refresh(); takeTab(); }
    Component.onCompleted: { refresh(); takeTab(); }
    // a tab asked for from outside (the Password Generator's IPC and CLI open the Generator)
    function takeTab() { if (Ui.passwordsTab !== "") { win.tab = Ui.passwordsTab; Ui.passwordsTab = ""; } }
    Connections { target: Ui; function onPasswordsTabChanged() { if (win.visible) win.takeTab(); } }

    Process {
        id: lister
        command: ["python3", win.tool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() }; }
                win.error = r.error ? Tr.t("The keyring could not be reached: %1", r.error) : "";
                // the metadata item is ours, not a login: don't show it as a password
                win.items = (r.items || []).filter(i => (i.attributes || {})["shani-id"] !== "shani-vault-meta");
                win.collections = r.collections || [];
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
    Process {
        id: capsLister
        command: ["python3", win.tool, "passkey-capabilities"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.passkeyCaps = JSON.parse(text) || {}; }
                catch (e) { win.passkeyCaps = {}; }
            }
        }
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
        win.poke();
        act.command = ["python3", win.tool].concat(args);
        act.payload = payload || "";
        act.stdinEnabled = true;
        act.after = after || null;
        act.running = true;
    }
    function reveal(i) {
        if (win.shownPath === i.path) { win.shownPath = ""; win.shownSecret = ""; return; }
        run(["reveal", i.path], "", r => { if (r.secret !== undefined) { win.shownPath = i.path; win.shownSecret = r.secret; Ui.passwordsRevealed = i.label; win.remember(i); hideTimer.restart(); } });
    }
    Timer { id: hideTimer; interval: 30000; onTriggered: { win.shownPath = ""; win.shownSecret = ""; win.shownNotePath = ""; } }
    // five minutes of no action hides what is on screen and locks the local
    // vault view; it does not fight other apps over the system keyring
    Timer { id: idleTimer; interval: 300000; onTriggered: { win.uiLockedReason = "idle"; win.shownPath = ""; win.shownSecret = ""; win.shownNotePath = ""; hideTimer.stop(); } }
    Timer { id: clipTick; interval: 1000; repeat: true; running: win.clipboardLeft > 0; onTriggered: win.clipboardLeft-- }
    // a screen lock must conceal a revealed secret before the timer gets to it
    Connections {
        target: Lock
        function onLockedChanged() {
            if (Lock.locked) { win.shownPath = ""; win.shownSecret = ""; hideTimer.stop(); win.shownNotePath = ""; win.uiLockedReason = "screen"; }
        }
    }
    function copy(i) {
        run(["reveal", i.path], "", r => {
            if (r.secret === undefined) return;
            copier.payload = r.secret;
            copier.running = true;
            win.note = Tr.t("%1 copied - the clipboard forgets it in 45 s", i.label);
            win.clipboardLeft = 45;
            win.remember(i);
            clearTimer.restart();
        });
    }
    Process { id: copier; property string payload: ""; command: ["wl-copy"]; stdinEnabled: true; onStarted: { write(payload); payload = ""; stdinEnabled = false; } onExited: stdinEnabled = true }
    Timer { id: clearTimer; interval: 45000; onTriggered: { Quickshell.execDetached(["wl-copy", "--clear"]); win.clipboardLeft = 0; } }
    // what an item is for, from its attributes (a website, a Wi-Fi, an app's account)
    function about(i) {
        const a = i.attributes || {};
        const parts = [a.username || a.user || a.account || "", a.server || a.host || a.site || a.url || a.ssid || a.service || a["xdg:schema"] || ""];
        return parts.filter(x => x).join("  ·  ");
    }
    // the account name is a plain attribute: KeePassXC and 1Password let you
    // copy it on its own without uncovering the password beside it
    function username(i) {
        const a = i.attributes || {};
        return a.username || a.user || a.account || "";
    }
    function copyUser(i) {
        const u = win.username(i);
        if (u === "") return;
        copier.payload = u;
        copier.running = true;
        win.note = Tr.t("%1 username copied - the clipboard forgets it in 45 s", i.label);
        win.clipboardLeft = 45;
        clearTimer.restart();
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
        if (newCategory.text.trim()) attrs.category = newCategory.text.trim();
        const secret = newSecret.text;
        const note = newNote.text.trim();
        win.run(["add", win.defaultCollection, label], JSON.stringify({ attributes: attrs, secret: secret }),
                r => {
                    if (!r.ok) return;
                    win.adding = false;
                    newLabel.text = ""; newUser.text = ""; newSecret.text = "";
                    newCategory.text = ""; newNote.text = "";
                    win.duplicate = null;
                    if (note) {
                        const next = JSON.parse(JSON.stringify(win.meta));
                        const m = next[r.path || label] || (next[r.path || label] = {});
                        m.note = note;
                        win.saveMeta(next);
                    }
                    if (onDone) onDone();
                });
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
        Keys.onPressed: e => {
            if (!(e.modifiers & Qt.ControlModifier)) return;
            if (e.key === Qt.Key_F) { search.text = ""; search.input.forceActiveFocus(); e.accepted = true; }
            else if (e.key === Qt.Key_N) { win.adding = true; e.accepted = true; }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            ActionStrip {
                Layout.fillWidth: true
                Repeater {
                    model: [["passwords", Tr.t("Passwords")], ["gpg", Tr.t("GPG keys")], ["passkeys", Tr.t("Passkeys")], ["generator", Tr.t("Generator")]]
                    Choice { required property var modelData; text: modelData[1]; selected: win.tab === modelData[0]; onClicked: win.tab = modelData[0] }
                }
            }
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
                        font.pixelSize: Theme.type("small")
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
                    font.pixelSize: Theme.type("caption")
                    elide: Text.ElideRight
                }
                Text {
                    visible: win.reusedCount > 0
                    Layout.fillWidth: true
                    text: Tr.t("Reused: %1", win.auditResults.reused.slice(0, 2).map(r => r.items.join(", ")).join(" · "))
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("caption")
                    elide: Text.ElideRight
                }
            }
        }
        // folders / favourites / recent: all chips and the folders in the vault
        ActionStrip {
            visible: win.tab === "passwords"
            Layout.fillWidth: true
            Repeater {
                model: [["", Tr.t("All")], ["favourites", Tr.t("Favourites")], ["recent", Tr.t("Recent")]]
                Choice { required property var modelData; text: modelData[1]; selected: win.folderFilter === modelData[0]; onClicked: win.folderFilter = modelData[0] }
            }
            Repeater {
                model: win.folders
                Choice { required property string modelData; text: modelData; selected: win.folderFilter === modelData; onClicked: win.folderFilter = win.folderFilter === modelData ? "" : modelData }
            }
        }
        Text {
            visible: win.error !== "" || win.note !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: win.error !== "" ? win.error : win.note
            color: win.error !== "" ? Theme.danger : Theme.dim
            font.family: Theme.font; font.pixelSize: Theme.type("body")
            Accessible.role: Accessible.StatusBar
            Accessible.name: text
        }
        RowLayout {
            visible: win.error !== ""
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: Tr.t("Check the keyring and try again")
                color: Theme.dim
                font.family: Theme.font; font.pixelSize: Theme.type("small")
                Accessible.name: text
            }
            Button { text: Tr.t("Try again"); onClicked: win.refresh() }
        }
        Text {
            visible: win.clipboardLeft > 0
            Layout.fillWidth: true
            text: Tr.t("Clipboard clears in %1 s", win.clipboardLeft)
            color: Theme.dim
            font.family: Theme.font; font.pixelSize: Theme.type("small")
            Accessible.role: Accessible.StatusBar
            Accessible.name: text
        }

        // ---- passwords ----
        ColumnLayout {
            visible: win.tab === "passwords"
            Layout.fillWidth: true
            spacing: Theme.px(6)
            SearchField {
                id: search
                Layout.fillWidth: true
                placeholder: Tr.t("Find a password"); label: Tr.t("Find a password")
            }
            ActionStrip {
                Layout.fillWidth: true
                Button { text: Tr.t("Add…"); kind: "primary"; onClicked: win.adding = !win.adding }
                Text {
                    visible: search.text !== ""
                    text: win.visibleItems.length + " / " + win.items.length
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                    font.features: { "tnum": 1 }
                }
                Button { text: Tr.t("Run security check"); onClicked: win.runAudit(); }
                Button {
                    text: Tr.t("Import…")
                    onClicked: FilePicker.open({ mode: "open", title: Tr.t("A Shani vault export"), filters: ["json"], onPicked: paths => { if (paths.length) win.importVault(paths[0]); } })
                }
                Button {
                    text: Tr.t("Export…")
                    onClicked: FilePicker.open({ mode: "save", title: Tr.t("Export vault details"), defaultName: "shani-vault.json", filters: ["json"], onPicked: paths => { if (paths.length) win.exportVault(paths[0]); } })
                }
            }
        }
        ColumnLayout {
            visible: win.tab === "passwords" && win.adding
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField { id: newLabel; Layout.fillWidth: true; placeholderText: Tr.t("What it is for, e.g. example.org"); label: Tr.t("What it is for") }
            TextField { id: newUser; Layout.fillWidth: true; placeholderText: Tr.t("User name (optional)"); label: Tr.t("User name") }
            TextField { id: newCategory; Layout.fillWidth: true; placeholderText: Tr.t("Folder, e.g. Work"); label: Tr.t("Folder") }
            TextField { id: newSecret; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Password"); label: Tr.t("Password"); onTextChanged: win.draftPassword = text }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(4)
                        radius: 2
                        color: index < win.newStrength.score
                            ? (win.newStrength.score <= 1 ? Theme.danger : win.newStrength.score === 2 ? Theme.amber : Theme.accent)
                            : Theme.alpha(Theme.text, 0.12)
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: win.newStrength.label + " - " + win.newStrength.tip
                color: win.newStrength.score <= 1 ? Theme.danger : Theme.dim
                font.family: Theme.font; font.pixelSize: Theme.type("small")
                Accessible.role: Accessible.StatusBar
                Accessible.name: text
            }
            TextField { id: newNote; Layout.fillWidth: true; placeholderText: Tr.t("Secure note (kept in the keyring)"); label: Tr.t("Secure note") }
            RowLayout {
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Generate"); onClicked: win.generateForForm() }
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
                    font.family: Theme.font; font.pixelSize: Theme.type("small")
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
        EmptyState {
            visible: win.tab === "passwords" && win.error === "" && win.shownItems.length === 0 && !lister.running
            icon: "dialog-password"
            title: win.items.length ? Tr.t("Nothing matches") : Tr.t("No passwords saved yet")
            subtitle: win.items.length ? Tr.t("Try another word or clear the folder filter") : Tr.t("Use Add, or import details from another Shani vault")
        }
        ListView {
            reuseItems: true
            cacheBuffer: 400
            id: plist
            visible: win.tab === "passwords" && win.shownItems.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: win.shownItems
            delegate: ColumnLayout {
                id: prow
                required property var modelData
                width: plist.width
                height: Math.max(Theme.touchTarget, actions.implicitHeight + Theme.px(8))
                spacing: 2
                Accessible.role: Accessible.ListItem
                Accessible.name: prow.modelData.label
                Accessible.description: win.about(prow.modelData)
                KeyFocus { name: prow.modelData.label + ", " + Tr.t("Show password"); onActivated: win.reveal(prow.modelData) }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    MouseArea { anchors.fill: parent; onClicked: win.reveal(prow.modelData) }
                    Icon { name: "dialog-password"; size: Theme.px(20); color: Theme.dim }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: prow.modelData.label; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body") }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: win.shownPath === prow.modelData.path ? win.shownSecret : win.about(prow.modelData)
                            color: win.shownPath === prow.modelData.path ? Theme.accent : Theme.dim
                            font.family: win.shownPath === prow.modelData.path ? Theme.mono : Theme.font
                            font.pixelSize: Theme.type("small")
                        }
                        Text {
                            visible: win.categoryOf(prow.modelData) !== Tr.t("Other")
                            Layout.fillWidth: true
                            text: win.categoryOf(prow.modelData)
                            color: Theme.faint
                            font.family: Theme.font; font.pixelSize: Theme.type("caption")
                            Accessible.name: Tr.t("Folder: %1", win.categoryOf(prow.modelData))
                        }
                    }
                    Flow {
                        id: actions
                        Layout.minimumWidth: win.compact ? Theme.touchTarget * 3 : implicitWidth
                        Layout.preferredWidth: win.compact ? Theme.touchTarget * 3 : implicitWidth
                        spacing: Theme.px(4)
                        IconButton {
                            icon: win.isFav(prow.modelData) ? "starred" : "non-starred"
                            size: Theme.px(26)
                            on: win.isFav(prow.modelData)
                            tip: win.isFav(prow.modelData) ? Tr.t("Remove %1 from favourites", prow.modelData.label) : Tr.t("Add %1 to favourites", prow.modelData.label)
                            onClicked: win.toggleFavorite(prow.modelData)
                        }
                        IconButton {
                            visible: win.noteOf(prow.modelData) !== ""
                            icon: "text-x-generic"
                            size: Theme.px(26)
                            on: win.shownNotePath === prow.modelData.path
                            tip: win.shownNotePath === prow.modelData.path ? Tr.t("Hide the secure note for %1", prow.modelData.label) : Tr.t("Read the secure note for %1", prow.modelData.label)
                            onClicked: win.toggleNote(prow.modelData)
                        }
                        IconButton { icon: win.shownPath === prow.modelData.path ? "view-conceal" : "view-reveal"; size: Theme.px(26); tip: win.shownPath === prow.modelData.path ? Tr.t("Hide %1", prow.modelData.label) : Tr.t("Show %1", prow.modelData.label); onClicked: win.reveal(prow.modelData) }
                        IconButton { icon: "edit-copy"; size: Theme.px(26); tip: Tr.t("Copy the password for %1", prow.modelData.label); onClicked: win.copy(prow.modelData) }
                        IconButton {
                            visible: win.username(prow.modelData) !== ""
                            icon: "contact-new"
                            size: Theme.px(26)
                            tip: Tr.t("Copy the username for %1", prow.modelData.label)
                            onClicked: win.copyUser(prow.modelData)
                        }
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
                }
                RowLayout {
                    visible: win.changing === prow.modelData.path
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(28)
                    TextField { id: changed; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("The new password"); label: Tr.t("The new password") }
                    Button { text: Tr.t("Save"); enabled: changed.text !== ""; onClicked: { win.run(["set", prow.modelData.path], changed.text, r => { if (r.ok) { win.changing = ""; changed.text = ""; } }); } }
                }
                RowLayout {
                    visible: win.changing === prow.modelData.path
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(28)
                    TextField {
                        id: changedNote
                        Layout.fillWidth: true
                        placeholderText: Tr.t("Secure note (kept in the keyring)")
                        label: Tr.t("Secure note")
                        onVisibleChanged: if (visible) text = win.noteOf(prow.modelData)
                    }
                    Button {
                        text: Tr.t("Save note")
                        enabled: changedNote.text.trim() !== win.noteOf(prow.modelData)
                        onClicked: win.setMetaField(prow.modelData, "note", changedNote.text.trim())
                    }
                }
                Text {
                    visible: win.shownNotePath === prow.modelData.path && !win.uiLocked
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(28)
                    wrapMode: Text.WordWrap
                    text: win.noteOf(prow.modelData)
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: Theme.type("small")
                    Accessible.role: Accessible.StaticText
                    Accessible.name: Tr.t("Secure note for %1: %2", prow.modelData.label, win.noteOf(prow.modelData))
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
                Accessible.role: Accessible.ListItem
                Accessible.name: krow.modelData.uid || krow.modelData.id
                Icon { name: krow.modelData.secret ? "application-pgp-keys" : "contact-new"; size: Theme.px(20); color: Theme.dim }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: krow.modelData.uid || krow.modelData.id; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body") }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: [krow.modelData.secret ? Tr.t("yours") : Tr.t("someone else's"), krow.modelData.id,
                               krow.modelData.expires ? Tr.t("until %1", Qt.formatDate(new Date(krow.modelData.expires * 1000), "d MMM yyyy")) : Tr.t("no end date")].join("  ·  ")
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small")
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

        // ---- the generator (the Password Generator app, merged here) ----
        PasswordGenerator {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: win.tab === "generator"
        }

        // ---- passkeys (a registry of references, not real WebAuthn credentials) ----
        Text {
            visible: win.tab === "passkeys"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Tr.t("Websites own real WebAuthn credentials; the shell keeps a keyring-protected REFERENCE to each (label, site, key-handle id), encrypted with your login. A site only accepts credentials registered through its own browser flow — the shell cannot mint one. When libfido2 tools are installed, genuinely local credentials can be created and used for challenge/response (not website logins).")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.type("small")
        }
        SettingsSection {
            visible: win.tab === "passkeys"
            Layout.fillWidth: true
            title: Tr.t("What this computer supports")
            hint: Tr.t("A check of the keyring and the tools installed here")
            Repeater {
                model: [
                    [Tr.t("Keyring"), win.passkeyCaps.keyring],
                    [Tr.t("Security-key device"), win.passkeyCaps.fido2_token],
                    [Tr.t("Make a key here"), win.passkeyCaps.fido2_cred],
                    [Tr.t("Sign a challenge here"), win.passkeyCaps.fido2_assert]
                ]
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Text {
                        Layout.fillWidth: true
                        text: modelData[0]
                        Accessible.name: text
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.type("small")
                    }
                    Text {
                        text: modelData[1] ? Tr.t("Available") : Tr.t("Not available")
                        Accessible.name: text
                        color: modelData[1] ? Theme.accent : Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.type("small")
                    }
                }
            }
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
                Accessible.role: Accessible.ListItem
                Accessible.name: prow.modelData.label || Tr.t("Unnamed")
                Icon { name: "dialog-password"; size: Theme.px(20); color: Theme.dim }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: prow.modelData.label || Tr.t("Unnamed"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body") }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: (prow.modelData.rp_id ? prow.modelData.rp_id + "  ·  " : "")
                            + (prow.modelData.source === "shell" ? Tr.t("Shell-created") : Tr.t("Browser reference"))
                            + (prow.modelData.created ? "  ·  " + Qt.formatDate(new Date(prow.modelData.created * 1000), "d MMM yyyy") : "")
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("caption")
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: prow.modelData.cred_id ? Tr.t("Key handle: %1", prow.modelData.cred_id.slice(0, 16)) : Tr.t("No local key handle")
                        color: Theme.faint; font.family: Theme.mono; font.pixelSize: Theme.type("caption")
                    }
                }
                IconButton { icon: "edit-copy"; size: Theme.px(26); tip: Tr.t("Copy the key-handle id"); onClicked: { Quickshell.clipboardText = prow.modelData.id; clearTimer.restart(); win.clipboardLeft = 45; win.note = Tr.t("%1 id copied", prow.modelData.label) } }
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
    // A locked view is honest: nothing is revealed behind it, and unlocking it
    // only clears the local veil. The system keyring keeps its own lock.
    Rectangle {
        anchors.fill: parent
        z: 10
        visible: win.uiLocked || win.keyringLocked
        color: Qt.rgba(0, 0, 0, 0.72)
        MouseArea { anchors.fill: parent }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.px(40), Theme.px(380))
            implicitHeight: lockCol.implicitHeight + Theme.px(32)
            radius: Theme.radiusLarge
            color: Theme.surface1
            ColumnLayout {
                id: lockCol
                anchors.centerIn: parent
                spacing: Theme.px(10)
                Icon { Layout.alignment: Qt.AlignHCenter; name: "system-lock-screen"; size: Theme.px(36); color: Theme.dim }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: win.keyringLocked ? Tr.t("The system keyring is locked") : Tr.t("Vault locked")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: Theme.type("heading")
                    font.weight: Font.DemiBold
                    Accessible.role: Accessible.Alert
                    Accessible.name: text
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: win.keyringLocked ? Tr.t("Unlock it with your session password, then read again") : Tr.t("Revealed details were hidden on lock or after five minutes of idle time")
                    color: Theme.dim
                    font.family: Theme.font; font.pixelSize: Theme.type("small")
                }
                Button {
                    Layout.alignment: Qt.AlignHCenter
                    text: win.keyringLocked ? Tr.t("Read again") : Tr.t("Unlock vault")
                    onClicked: {
                        if (win.keyringLocked) win.refresh();
                        else { win.uiLockedReason = ""; idleTimer.restart(); }
                    }
                }
            }
        }
    }
}
