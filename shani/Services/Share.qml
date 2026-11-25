pragma Singleton
// One "Share…" for file(s) (after the share sheets of macOS and Windows): the
// phone (KDE Connect), a paired Bluetooth device, a device on the Wi-Fi with LocalSend
// (nearby devices of any kind — the image's AirDrop), a folder opened as a QR
// link on this network, email, or the clipboard — as the file itself
// (text/uri-list, so it pastes into Files or a chat) or its path.
// The sheet (Modules/Share/ShareSheet.qml) lists them, recents first.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property var files: []             // the file(s) being shared, while the sheet is open
    readonly property string file: files.length ? files[0] : ""   // the first, kept for callers that share one
    readonly property string name: files.length ? files[0].split("/").pop() : ""
    property string done: ""           // what happened last, for the tests
    property string lastError: ""      // the last failed target's message, for the sheet
    property var recent: []            // [label] of the targets chosen lately, newest first

    function open(paths) {
        files = (typeof paths === "string" ? [paths] : Array.from(paths || []).map(String))
            .filter(p => p !== "");
    }
    function close() { files = []; lastError = ""; }
    function noteRecent(label) {
        const l = String(label || "");
        if (!l) return;
        root.recent = [l].concat(root.recent.filter(x => x !== l)).slice(0, 6);
    }

    // theme icons, normalised: every target shows a name every icon theme has
    function iconFor(s) {
        const n = String(s || "").trim().toLowerCase().replace(/_/g, "-").replace(/-symbolic$/, "");
        return ["phone", "bluetooth-active", "network-wireless", "network-workgroup",
                "mail-send", "edit-copy", "document-open", "package-x-generic"].indexOf(n) >= 0
            ? n : "text-x-generic";
    }
    function targetStateText(state) {
        switch (state) {
            case "ready": return Tr.t("Ready");
            case "off": return Tr.t("Off");
            case "none": return Tr.t("No app");
            case "denied": return Tr.t("Access denied");
            default: return "";
        }
    }
    // run a target: one that reports failure answers with lastError for the sheet
    function run(fn, args) {
        root.lastError = "";
        try {
            if (fn.apply(null, args || []) === false)
                root.lastError = Tr.t("The target is not reachable");
        } catch (e) {
            root.lastError = String(e || "").trim() || Tr.t("The target is not reachable");
        }
    }

    readonly property var targets: root.files.length === 0 ? [] : (function() {
        const base = [
            // ---- people and devices -----------------------------------------
            ...(Phone.reachable ? [{
                icon: root.iconFor("phone"),
                label: "Send to " + Phone.name,
                state: "ready",
                run: () => Phone.send(root.files[0])
            }] : []),
            ...BtSend.devices.map(d => ({
                icon: root.iconFor(d.icon || "bluetooth-active"),
                label: Tr.t("Bluetooth: ") + (d.name || d.address),
                subtitle: d.online ? Tr.t("Paired") : Tr.t("Not online"),
                state: d.online ? "ready" : "off",
                run: () => { BtSend.pick(root.files[0]); BtSend.sendTo(d); }
            })),
            // LocalSend: devices on the Wi-Fi; "Off" until the Nearby app runs
            { icon: root.iconFor("network-wireless"), label: Tr.t("Nearby devices (LocalSend)"),
              state: (Nearby.running || Nearby.visible_ || Nearby.scanning) ? "ready" : "off",
              subtitle: Nearby.scanning ? Tr.t("Scanning…") : "",
              run: () => { Nearby.pending = root.files; Ui.closeAll(); Ui.nearby = true; } },
            { icon: root.iconFor("network-workgroup"), label: Tr.t("Share a folder by link (QR)"),
              run: () => {
                  Ui.closeAll();
                  FilePicker.open({ mode: "folder", title: Tr.t("A folder to share on this Wi-Fi"),
                                    onPicked: paths => { if (paths.length) { Files.serveFolder(paths[0], false); Files.show(paths[0]); } } });
              } },
            // ---- mail and clipboard -----------------------------------------
            { icon: root.iconFor("mail-send"), label: Tr.t("Email"),
              run: () => root.run(Quickshell.execDetached, ["xdg-email", "--attach"].concat(root.files)) },
            { icon: root.iconFor("edit-copy"), label: Tr.t("Copy the file"),
              run: () => { copyFile.command = ["sh", "-c", 'printf "file://%s\\r\\n" "$@" | wl-copy --type text/uri-list', "sh"].concat(root.files); copyFile.running = true; } },
            { icon: root.iconFor("edit-copy"), label: Tr.t("Copy its path"),
              run: () => { Quickshell.clipboardText = root.files.join("\n"); } },
            { icon: root.iconFor("document-open"), label: Tr.t("Open with…"),
              run: () => root.run(Quickshell.execDetached, ["gio", "open", root.files[0]]) },
            // ---- archive first ----------------------------------------------
            { icon: root.iconFor("package-x-generic"), label: Tr.t("Archive and share (zip)"),
              run: () => { root.archiveWait = true; root.archiveSeen = Archive.made; Archive.createAsk(root.files); } }
        ];
        // recents first, then the rest without their recents (each once)
        const seen = [], out = [];
        for (const r of root.recent) {
            const t = base.find(x => x.label === r);
            if (t && seen.indexOf(r) < 0) { seen.push(r); out.push(Object.assign({}, t, { recent: true })); }
        }
        return out.concat(base.filter(t => seen.indexOf(t.label) < 0));
    })()

    // "Archive and share (zip)": Archive.createAsk shows the archive window;
    // once a new archive is made, the sheet reopens on it (ShareSheet polls
    // Share.archiveWait while waiting)
    property string archiveSeen: ""
    property bool archiveWait: false
    function archiveChanged() {
        if (!root.archiveWait || Archive.creating || root.archiveSeen === Archive.made) return;
        root.archiveSeen = Archive.made;
        if (Archive.made !== "") root.open(Archive.made);
    }

    function choose(i) {
        const t = targets[i];
        if (!t)
            return;
        done = t.label;
        noteRecent(t.label);
        t.run();
        close();
    }
    // Cancel: close, and stop anything already running (a send to Bluetooth or
    // the LocalSend handoff)
    function cancel() {
        close();
        BtSend.file = "";
        Nearby.pending = [];
    }

    Process { id: copyFile; onExited: if (code !== 0) root.lastError = Tr.t("The copy to the clipboard failed"); }
}
