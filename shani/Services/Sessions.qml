pragma Singleton
// Named sessions (coresession's app+document sets, corebox's "Sessions"): save
// the apps and the folders/documents open now under a name, and bring that set
// back in one tap. One flat JSON object in the shell's state folder, like the
// playlists and the parked shelf; the pure rules live in Sessions.js so the
// tests run the same code without QuickShell. What is open is read from the
// shell's own services (niri windows, Files, TextDocs, PdfViewer) - never from
// a process's command line, which is only a guess at what an app was doing.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "Sessions.js" as Logic

Singleton {
    id: root
    property var sessions: ({})         // name -> { apps: [desktop ids], paths: [paths], savedAt: iso }
    property string error: ""
    property string lastRestored: ""
    property var pendingPaths: []

    FileView {
        id: store
        path: Quickshell.statePath("sessions.json")
        printErrors: false               // none saved yet
        onLoaded: {
            try { root.sessions = Logic.normalise(JSON.parse(text())); }
            catch (e) { root.sessions = {}; }
        }
        onLoadFailed: root.sessions = {}
        // A "session saved" note is a lie if the write never landed.
        onSaveFailed: root.error = Tr.t("Could not save the session")
    }

    function list() { return Logic.toList(root.sessions); }
    function validName(name) { return Logic.cleanName(name) !== ""; }
    function has(name) { return Object.prototype.hasOwnProperty.call(root.sessions, Logic.cleanName(name)); }

    function save(name, apps, paths) {
        const next = Logic.put(root.sessions, name, apps, paths, new Date().toISOString());
        if (!next) {
            root.error = Tr.t("Use a name of 1 to 60 characters, without / or \\");
            return false;
        }
        root.sessions = next;
        store.setText(JSON.stringify(next));
        root.error = "";
        return true;
    }
    function remove(name) {
        const n = Logic.cleanName(name);
        if (!root.has(n))
            return false;
        root.sessions = Logic.drop(root.sessions, n);
        store.setText(JSON.stringify(root.sessions));
        root.error = "";
        return true;
    }

    // what is on screen, in the form the session file keeps: desktop ids that
    // can be launched again, and paths that can be opened again.
    function captureCurrent() {
        const apps = [];
        for (const w of Object.values(Niri.windows)) {
            if (!w.app_id || w.app_id === "org.quickshell")
                continue;
            const e = DesktopEntries.byId(w.app_id) || DesktopEntries.heuristicLookup(w.app_id);
            if (e && !e.noDisplay && apps.indexOf(e.id) < 0)
                apps.push(e.id);
        }
        const paths = [];
        const add = p => {
            const s = String(p || "").trim();
            if (s && paths.indexOf(s) < 0)
                paths.push(s);
        };
        add(Files.path);
        if (Files.splitActive) add(Files.splitPath);
        for (const d of (TextDocs.docs || []))
            add(d && d.path);
        add(PdfViewer.file);
        return { apps: Logic.capped(apps), paths: Logic.capped(paths) };
    }
    function saveCurrent(name) {
        const now = root.captureCurrent();
        return root.save(name, now.apps, now.paths);
    }

    // Apps go through the same launcher the sign-in reopen uses. Paths are
    // classified once, with `test -d`, because a flat list does not say which
    // of them was a folder; known file kinds go to the shell's own viewers.
    function restore(name) {
        const n = Logic.cleanName(name);
        const s = root.sessions[n];
        if (!s) {
            root.error = Tr.t("No session called %1").arg(n);
            return false;
        }
        root.error = "";
        root.lastRestored = n;
        Reopen.reopen(s.apps);
        root.pendingPaths = s.paths.slice();
        root.openNext();
        return true;
    }
    function openNext() {
        if (root.error !== "" || !root.pendingPaths.length)
            return;
        const p = root.pendingPaths.shift();
        probe.attempted = p;
        probe.command = ["sh", "-c", '[ -d "$1" ] && echo dir || echo file', "sh", p];
        probe.running = true;
    }
    Process {
        id: probe
        property string attempted: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const p = probe.attempted;
                if (text.trim() === "dir")
                    Files.show(p);
                else {
                    const k = FileActions.kind(p);
                    if (k === "pdf") PdfViewer.open(p);
                    else if (k === "image") Viewer.open(p);
                    else if (k === "video" || k === "audio") PlayQueue.open(p);
                    else { Ui.textEditor = true; TextDocs.open(p); }
                }
                root.openNext();
            }
        }
        stderr: StdioCollector {}
        // Without this, a failed probe just stops the chain with no word to UI.
        onExited: code => {
            if (code === 0) return;
            root.pendingPaths = [];
            root.error = Tr.t("Could not open %1").arg(probe.attempted);
        }
    }
}
