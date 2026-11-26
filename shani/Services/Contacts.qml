pragma Singleton
// Contacts: the address book, as vCard 4.0 files in
// ~/.local/share/shani-shell/contacts/ (one .vcf per contact, named by UID).
// bridge/contacts.py reads and writes them — the same files Phone
// (the phone app) uses, so a contact added here is there too. No Evolution
// Data Server, no CardDAV: just files on disk, synced by whatever the person
// already uses (Nextcloud, iCloud via vdirsyncer, Dropbox, …).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_CONTACTS_TOOL"), "contacts.py")
    property var contacts: []            // [{ uid, name, given, family, phone, email, phones, emails }]
    property string query: ""            // live search filter
    property string error: ""
    property bool busy: false
    property var selected: null          // the contact being viewed/edited
    // "name" (default), "given" or "family": passed to contacts.py list
    property string sortBy: Settings.data.contactsSortBy || "name"
    readonly property var favoriteContacts: contacts.filter(c => c.favorite)

    // "your own card": uid kept in Settings, flag written to the vCard as
    // X-SHANI-SELF:1 by bridge/contacts.py
    readonly property string myUid: Settings.data.myContactUid || ""
    readonly property var me: myUid ? (contacts.find(c => c.uid === myUid) || null) : null
    readonly property var allGroups: {
        const seen = {};
        for (const c of contacts)
            for (const g of (c.groups || []))
                seen[g] = true;
        return [Tr.t("All")].concat(Object.keys(seen).sort());
    }

    // GNOME Contacts' smart lists: views computed from the cards, not saved
    // groups, so they stay useful in an address book nobody has curated.
    readonly property var smartListNames: [Tr.t("Favourites"), Tr.t("No phone"), Tr.t("No email")]
    function isSmartList(name) { return smartListNames.indexOf(name) >= 0; }
    function contactsInList(name) {
        if (!name || name === Tr.t("All")) return contacts.slice();
        if (name === Tr.t("Favourites")) return favoriteContacts.slice();
        if (name === Tr.t("No phone"))
            return contacts.filter(c => !(c.phones || []).some(p => String(p.number || "").trim() !== ""));
        if (name === Tr.t("No email"))
            return contacts.filter(c => !(c.emails || []).some(e => String(e.address || "").trim() !== ""));
        return listContactsInGroup(name);
    }
    function countInList(name) { return contactsInList(name).length; }
    function groupCount(group) { return contacts.filter(c => (c.groups || []).indexOf(group) >= 0).length; }

    // A short-lived success line beside the error: an import that wrote zero
    // cards and one that wrote five used to look identical in the window.
    property string notice: ""
    Timer { id: noticeTimer; interval: 5000; onTriggered: root.notice = "" }
    function say(message) { root.notice = message || ""; if (root.notice) noticeTimer.restart(); }

    // the list, filtered by query (contacts.py does the matching)
    readonly property var shown: contacts

    function listContactsInGroup(group) {
        if (!group || group === Tr.t("All")) return contacts.slice();
        return contacts.filter(c => (c.groups || []).indexOf(group) >= 0);
    }
    function setGroups(uid, groups) {
        const c = contacts.find(x => x.uid === uid);
        if (!c) return;
        run(["edit", JSON.stringify({ uid: uid, name: c.name, given: c.given || "",
            family: c.family || "", phones: c.phones || [], emails: c.emails || [],
            groups: groups, self: !!c.self, favorite: !!c.favorite, avatar: c.avatar || "" })]);
    }
    function setSelf(uid, on) {
        const c = contacts.find(x => x.uid === uid);
        if (!c) return;
        run(["edit", JSON.stringify({ uid: uid, name: c.name, given: c.given || "",
            family: c.family || "", phones: c.phones || [], emails: c.emails || [],
            groups: c.groups || [], self: on, favorite: !!c.favorite,
            avatar: c.avatar || "" })]);
    }
    // the star is "This is me"; a favourite is a separate, ordinary flag
    function toggleFavorite(uid) {
        const c = contacts.find(x => x.uid === uid);
        if (!c) return;
        run(["edit", JSON.stringify({ uid: uid, name: c.name, given: c.given || "",
            family: c.family || "", phones: c.phones || [], emails: c.emails || [],
            groups: c.groups || [], self: !!c.self, favorite: !c.favorite,
            avatar: c.avatar || "" })]);
    }
    function setAvatar(uid, path) {
        const c = contacts.find(x => x.uid === uid);
        if (!c) return;
        run(["edit", JSON.stringify({ uid: uid, name: c.name, given: c.given || "",
            family: c.family || "", phones: c.phones || [], emails: c.emails || [],
            groups: c.groups || [], self: !!c.self, favorite: !!c.favorite,
            avatar: String(path || "") })]);
    }
    function toggleMe(uid) {
        const becoming = myUid !== uid;
        if (myUid && myUid !== uid) setSelf(myUid, false);
        setSelf(uid, becoming);
        Settings.data.myContactUid = becoming ? uid : "";
        Settings.save();
    }

    function refresh() {
        if (!reader.running) reader.running = true;
    }

    // one write at a time, then the list again (same pattern as Tasks.qml)
    property var _queue: []
    function run(args) { _queue = _queue.concat([args]); next(); }
    property string _lastAction: ""
    function next() {
        if (writer.running || _queue.length === 0)
            return;
        busy = true;
        const args = _queue[0];
        root._lastAction = args[0] || "";
        writer.command = ["python3", root.tool].concat(args);
        _queue = _queue.slice(1);
        writer.running = true;
    }

    function add(name, phone, email, groups, detail) {
        const d = detail || {};
        run(["add", JSON.stringify({ name: String(name || "").trim(), phone: String(phone || "").trim(), email: String(email || "").trim(),
            phones: d.phones || [], emails: d.emails || [], groups: groups || [],
            given: d.given || "", family: d.family || "", favorite: !!d.favorite, avatar: d.avatar || "" })]);
    }
    function edit(uid, name, phone, email, groups, detail) {
        const d = detail || {};
        run(["edit", JSON.stringify({ uid: uid, name: String(name || "").trim(), phone: String(phone || "").trim(), email: String(email || "").trim(),
            phones: d.phones || [], emails: d.emails || [], groups: groups || [],
            given: d.given || "", family: d.family || "", favorite: !!d.favorite, avatar: d.avatar || "" })]);
    }
    function remove(uid) { run(["delete", JSON.stringify({ uid: uid })]); }

    // raw vCard for a QR code (Qr.show takes arbitrary text)
    property string vcardText: ""
    signal vcardReady(string text, string name)
    function vcard(uid, name) {
        vcardProc.uid = uid || "";
        vcardProc.who = name || "";
        vcardProc.command = ["python3", root.tool, "vcard", uid];
        vcardProc.running = true;
    }
    Process {
        id: vcardProc
        property string uid: ""
        property string who: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root.vcardText = text;
                if (text.trim() !== "") root.vcardReady(text, vcardProc.who);
            }
        }
    }
    // export all cards as one .vcf, written through FileView (no shell quoting)
    property string exportPath: ""
    function exportAll(path) {
        if (!path) return;
        root.exportPath = path;
        exportProc.command = ["python3", root.tool, "export-all"];
        exportProc.running = true;
    }
    Process {
        id: exportProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "") {
                    root.error = Tr.t("There are no contacts to export");
                    return;
                }
                exportView.path = root.exportPath;
                exportView.setText(text);
            }
        }
    }
    FileView {
        id: exportView
        path: ""
        printErrors: false
        onSaved: root.say(Tr.t("Contacts exported"))
    }

    // import a .vcf file (drag onto the window, or a file picker)
    function importFile(path) {
        if (!path) { root.error = Tr.t("No file was chosen"); return; }
        run(["import", path]);
    }

    // find contacts that look like duplicates (same name or same phone/email)
    // returns pairs of uids that should be merged. Your own card is never a
    // candidate: folding it into somebody else changes who "me" is.
    function findDuplicates() {
        const seen = {};
        const dups = [];
        for (const c of contacts) {
            if (c.self) continue;
            const key = (c.name || "").toLowerCase().replace(/\s+/g, "");
            if (key && seen[key]) {
                dups.push([seen[key], c.uid]);
            } else if (key) {
                seen[key] = c.uid;
            }
            // also check phone/email
            for (const p of (c.phones || [])) {
                const pk = "p:" + String(p.number || "").replace(/\D/g, "");
                if (pk.length > 4 && seen[pk]) {
                    dups.push([seen[pk], c.uid]);
                } else if (pk.length > 4) {
                    seen[pk] = c.uid;
                }
            }
            for (const e of (c.emails || [])) {
                const ek = "e:" + String(e.address || "").toLowerCase();
                if (ek.length > 6 && seen[ek]) {
                    dups.push([seen[ek], c.uid]);
                } else if (ek.length > 6) {
                    seen[ek] = c.uid;
                }
            }
        }
        // deduplicate pairs
        const unique = [];
        const pairSet = new Set();
        for (const pair of dups) {
            const k = pair.slice().sort().join("|");
            if (!pairSet.has(k)) { pairSet.add(k); unique.push(pair); }
        }
        return unique;
    }

    // merge two contacts: keep the first's uid, add everything the second had,
    // delete the second. The old merge sent only a name/phones/emails payload,
    // so given/family, groups, favourite and photo were silently wiped.
    property var lastMerge: null   // { keeper, removed } — one-step unlink after a merge
    function merge(uidA, uidB) {
        if (!uidA || !uidB || uidA === uidB) return;
        const a = contacts.find(c => c.uid === uidA);
        const b = contacts.find(c => c.uid === uidB);
        if (!a || !b || a.self || b.self) return;
        const phones = (a.phones || []).slice();
        for (const p of (b.phones || [])) {
            if (!phones.some(x => x.number === p.number)) phones.push(p);
        }
        const emails = (a.emails || []).slice();
        for (const e of (b.emails || [])) {
            if (!emails.some(x => x.address === e.address)) emails.push(e);
        }
        const groups = (a.groups || []).slice();
        for (const g of (b.groups || [])) {
            if (groups.indexOf(g) < 0) groups.push(g);
        }
        root.lastMerge = { keeper: JSON.parse(JSON.stringify(a)), removed: JSON.parse(JSON.stringify(b)) };
        root.run(["edit", JSON.stringify({ uid: uidA, name: a.name || b.name,
            given: a.given || b.given || "", family: a.family || b.family || "",
            phones: phones, emails: emails, groups: groups,
            favorite: !!a.favorite || !!b.favorite, avatar: a.avatar || b.avatar || "" })]);
        root.run(["delete", JSON.stringify({ uid: uidB })]);
        root.say(Tr.t("Merged %1 into %2", b.name || "", a.name || ""));
    }

    // Undo / unlink: restore both cards exactly as they were. Only the last
    // merge is reversible; a self card is never merged in the first place.
    function undoMerge() {
        const m = root.lastMerge;
        if (!m) return;
        root.lastMerge = null;
        const k = m.keeper;
        const r = m.removed;
        root.run(["edit", JSON.stringify(k)]);
        root.run(["add", JSON.stringify({ name: r.name, given: r.given || "", family: r.family || "",
            phones: r.phones || [], emails: r.emails || [], groups: r.groups || [],
            favorite: !!r.favorite, avatar: r.avatar || "" })]);
        root.say(Tr.t("Merge undone — the cards are separate again"));
    }

    Process {
        id: reader
        command: ["python3", root.tool, "list", root.query, root.sortBy]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.contacts = JSON.parse(text) || []; } catch (e) { root.contacts = []; }
            }
        }
        onExited: code => { if (code !== 0) root.error = Tr.t("Could not read the address book"); }
    }
    // a changed sort choice must re-read, not just re-sort a cached list. It
    // belongs beside the Process, not inside it: a Process has no default
    // property to take an object, and the whole surface failed to load.
    Connections { target: root; function onSortByChanged() { if (!reader.running) reader.running = true; } }

    Process {
        id: writer
        stdout: StdioCollector { id: writeOut }
        stderr: StdioCollector { id: writeErr }
        onExited: code => {
            root.busy = false;
            root.error = code === 0 ? "" : (writeErr.text.trim().split("\n").pop() || Tr.t("Could not save the contact"));
            if (code === 0 && root._lastAction === "import") {
                let count = 0;
                try { count = Number(JSON.parse(writeOut.text.trim()).count) || 0; } catch (e) {}
                root.say(Tr.t("Imported %1 contact%2", count, count === 1 ? "" : "s"));
            }
            root.refresh();
            root.next();
        }
    }
}
