pragma Singleton
// One answer for "what is this file?": get(path, callback) hands back the
// bridge's JSON ({ type, size, modified, width, ... } with only present fields)
// and also stores it here for bindings. The bridge (bridge/filemeta.py) uses
// only declared tools and leaves a field out when the tool for it is absent,
// so the caller never has to know which packages are installed.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/Format.js" as Format

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_FILEMETA_TOOL") || "/usr/lib/shani-shell/filemeta.py"

    property string path: ""                  // the last path asked for
    property var info: ({})                   // the last answer
    property bool loading: false
    property string error: ""

    // the keys worth showing, in order; a value missing from the bridge is no row
    readonly property var fields: [
        ["type", "Type"], ["size", "Size"], ["modified", "Modified"],
        ["width", "Width"], ["height", "Height"], ["duration", "Duration"],
        ["codec", "Codec"], ["bitrate", "Bitrate"], ["pages", "Pages"],
        ["title", "Title"], ["author", "Author"], ["subject", "Subject"],
        ["camera", "Camera"], ["lens", "Lens"], ["taken", "Taken"]
    ]
    readonly property var rows: rowsFor(info)

    // get(path, callback): the callback receives the parsed object (also on
    // failure, as { error } or {}), and is never left waiting on a stale run.
    function get(path, callback) {
        const p = String(path || "");
        meta.running = false;
        meta.finished = true;
        meta.callback = null;
        root.path = p;
        root.info = ({});
        root.error = "";
        if (!p) {
            root.loading = false;
            if (typeof callback === "function") callback({});
            return;
        }
        root.loading = true;
        meta.callback = typeof callback === "function" ? callback : null;
        meta.want = p;
        meta.finished = false;
        meta.command = ["python3", root.tool, p];
        meta.running = true;
    }

    function finish(d) {
        if (meta.finished || root.path !== meta.want) return;   // a newer file won
        meta.finished = true;
        root.loading = false;
        root.info = d || ({});
        root.error = root.info.error || "";
        const cb = meta.callback;
        meta.callback = null;
        if (cb) cb(root.info);
    }

    function rowsFor(d) {
        const data = d || ({});
        const out = [];
        for (const f of root.fields) {
            const v = data[f[0]];
            if (v === undefined || v === null || v === "") continue;
            let shown = v;
            if (f[0] === "size") shown = humanSize(v);
            else if (f[0] === "duration") shown = clock(v);
            else if (f[0] === "bitrate") shown = rate(v);
            else if (f[0] === "width" || f[0] === "height") shown = v + " px";
            out.push({ label: Tr.t(f[1]), value: String(shown), key: f[0] });
        }
        return out;
    }

    function humanSize(b) { return Format.humanSize(b, "tb"); }

    function clock(s) {
        const t = Math.round(Number(s) || 0);
        const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), sec = t % 60;
        return (h ? h + ":" + String(m).padStart(2, "0") : String(m)) + ":" + String(sec).padStart(2, "0");
    }

    function rate(bps) {
        const bits = Number(bps) || 0;
        return bits >= 1000000 ? (Math.round(bits / 100000) / 10) + " Mb/s" : Math.round(bits / 1000) + " kb/s";
    }

    Process {
        id: meta
        property var callback: null
        property bool finished: true
        property string want: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = ({});
                try { d = JSON.parse(text) || ({}); }
                catch (e) { d = { error: Tr.t("Could not read this file's details") }; }
                root.finish(d);
            }
        }
        onExited: code => {
            if (code !== 0) root.finish({ error: Tr.t("Could not read this file's details") });
        }
    }
}
