pragma Singleton
// The file-chooser portal's shell half: bridge/portal.py (org.freedesktop.impl.
// portal.FileChooser) asks for a file - a Flatpak's Open or Save dialog - with an
// id; the shell's own picker shows it; the bridge fetches the answer by that id.
// One picker at a time: a second ask while one is open waits (the bridge keeps
// asking until the picker is free).
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    property var answers: ({})            // id -> { paths } | { cancelled }
    property string current: ""           // the id the picker is showing
    function pick(id, optsJson) {
        if (!id || FilePicker.shown) return;
        // the options come base64-encoded JSON (qs ipc splits arguments at commas)
        let o = {};
        try { o = JSON.parse(decodeURIComponent(escape(Qt.atob(optsJson || "")))); } catch (e) { try { o = JSON.parse(optsJson || "{}"); } catch (e2) {} }
        root.current = id;
        // asked by another app's window: the picker comes up over everything (Ui.closeAll)
        Ui.closeAll();
        FilePicker.open({
            mode: o.mode === "save" ? "save" : o.directory ? "folder" : "open",
            title: o.title || "",
            multiple: !!o.multiple,
            filters: o.filters || [],
            defaultName: o.name || "",
            startPath: o.folder || "",
            onPicked: paths => { root._answer(id, { paths: paths }); },
            onCancelled: () => { root._answer(id, { cancelled: true }); }
        });
    }
    function _answer(id, a) {
        const m = Object.assign({}, root.answers); m[id] = a; root.answers = m;
        if (root.current === id) root.current = "";
    }
    // the answer, once; "" only while this id is the one being chosen. Any
    // other unanswered id is busy: another app's picker is up, and the bridge
    // must keep asking instead of waiting on an answer that will never come.
    function result(id) {
        const a = root.answers[id];
        if (!a) return root.current === id ? "" : JSON.stringify({ busy: true });
        const m = Object.assign({}, root.answers); delete m[id]; root.answers = m;
        return JSON.stringify(a);
    }
    function cancel(id) { if (root.current === id) FilePicker.cancel(); }
}
