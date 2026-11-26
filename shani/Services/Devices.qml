pragma Singleton
// Devices: the phones and small gadgets this computer can reach. bridge/devices.py
// owns every read and every action, so the window cannot disagree with the
// daemon about what is connected or what a gadget answered. The window is a view.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_DEVICES_TOOL"), "devices.py")

    property var devices: []             // paired phones, for the window's list
    property var androidInfo: ({})       // the answer from `android info` (text or object)
    property var androidApps: []          // the apps `android app` listed
    property var battery: ({})           // the selected phone's battery
    property var storage: ({})           // the selected phone's storage
    property string screenState: ""      // "" | "on" | "off"
    property string fmState: ""          // "" | "on" | "off"
    property real fmFrequency: 0         // the radio's tuned frequency
    property string fmVolume: ""         // the last volume the radio accepted
    property string fmReport: ""         // the radio's own words: bands, volume, decode, scan
    property bool fmReportError: false
    property string nfcText: ""          // the last tag read
    property var irCodes: []             // remotes, or a remote's buttons
    property string irRemote: ""         // the remote whose buttons are listed
    property var callLines: []           // [{ id, name, ready, kind }], from `lines`
    property string note: ""
    property bool busy: false

    function refresh() {
        enqueue("android", ["info"]);
        enqueue("screen", ["state"]);
        enqueue("fm", ["state"]);
    }

    // `arg` is the serial; `value` is what to do with it (a link, an app, a path).
    // Both go as separate argv items, never through a shell string.
    function android(verb, arg, value) {
        const args = [String(verb || "")];
        if (arg !== undefined && arg !== null && String(arg) !== "") args.push(String(arg));
        if (value !== undefined && value !== null && String(value) !== "") args.push(String(value));
        enqueue("android", args);
    }
    function connect(kind, value, code) {
        const args = [String(kind || ""), String(value || "")];
        if (code !== undefined && code !== null && String(code) !== "") args.push(String(code));
        enqueue("connect", args);
    }
    function screen(action, mode, touch, type) {
        const args = [String(action || ""), String(mode || "")];
        if (touch !== undefined && touch !== null) args.push(touch ? "1" : "0");
        if (type !== undefined && type !== null) args.push(type ? "1" : "0");
        enqueue("screen", args);
    }
    function fm(action, value) { enqueue("fm", [String(action || ""), String(value === undefined || value === null ? "" : value)]) }
    function nfc(action, text) { enqueue("nfc", [String(action || ""), String(text || "")]) }
    function ir(action, code) { enqueue("ir", [String(action || ""), String(code || "")]) }
    function lines() { enqueue("lines", []) }
    function say(message) { root.note = message || ""; }

    // one Process, reused; `what` names the answer, `act` the verb inside it. A
    // call that arrives while the bridge is still answering is queued, not lost.
    function enqueue(what, args) {
        root.pending = root.pending.concat([{ what: what, args: args }]);
        root.pump();
    }
    function pump() {
        if (root.busy || job.running || !root.pending.length) return;
        const next = root.pending[0];
        root.pending = root.pending.slice(1);
        root.start(next.what, next.args);
    }
    function start(what, args) {
        root.busy = true;
        job.what = what;
        job.act = args.length ? String(args[0]) : "";
        job.arg1 = args.length > 1 ? String(args[1]) : "";
        job.arg2 = args.length > 2 ? String(args[2]) : "";
        job.command = ["python3", root.tool, what].concat(args);
        job.running = false;
        job.running = true;
    }
    property var pending: []

    function outText(data) {
        return data && typeof data.out === "string" ? data.out.trim() : "";
    }
    function objectOrText(value, fallbackKey) {
        if (value && typeof value === "object" && !Array.isArray(value)) return value;
        const o = {};
        o[fallbackKey] = typeof value === "string" ? value : String(value || "");
        return o;
    }

    function finished(what, text, code) {
        if (code === 127 || code === 126) {
            root.note = Tr.t("The devices service is not installed");
            return;
        }
        let data = null;
        try { data = JSON.parse(text); } catch (e) { root.note = Tr.t("Devices could not answer"); return; }
        const failed = data && data.error ? String(data.error)
            : (data && data.ok === false ? Tr.t("That did not work") : "");

        if (what === "android") {
            if (failed) { root.note = failed; return; }
            let out = data && data.out;
            if (typeof out === "string") {
                try { out = JSON.parse(out); } catch (e) { out = out; }
            }
            const verb = job.act;
            if (verb === "info") {
                // keep the whole answer: it names the handset and its serial,
                // while `out` is only the one-line description for people.
                root.androidInfo = data || {};
                if (Array.isArray(data && data.devices)) {
                    root.devices = data.devices;
                } else if (typeof out === "string") {
                    // `android info` is one sentence: "Google Pixel 7, Android …".
                    // The handset is a real device row even when no link service sees it.
                    const m = /(?:^|[\s,])([A-Za-z][\w-]*\s+\d+[A-Za-z0-9]*)\s*,?\s*Android\b/.exec(out);
                    root.devices = m ? [{ id: job.arg1 || m[1], name: m[1], paired: true, reachable: true, kind: "android" }] : [];
                }
                root.note = "";
            } else if (verb === "battery") {
                // the bridge sends parsed facts; keep the raw text only as a
                // fallback, never as the row's one-line summary
                root.battery = data && data.battery && typeof data.battery === "object"
                    ? data.battery : objectOrText(out, "text");
                root.note = "";
            } else if (verb === "storage") {
                root.storage = data && data.storage && typeof data.storage === "object"
                    ? data.storage : objectOrText(out, "text");
                root.note = "";
            } else if (verb === "screenshot") {
                root.note = outText(data) !== "" ? Tr.t("Screenshot saved to %1", outText(data)) : Tr.t("Screenshot taken");
            } else if (verb === "record") {
                root.note = outText(data) !== "" ? Tr.t("Recording saved to %1", outText(data)) : Tr.t("Recording saved");
            } else if (verb === "link") {
                root.note = Tr.t("Link opened on the phone");
            } else if (verb === "app") {
                if (job.arg2 !== "") {
                    root.note = Tr.t("App opened on the phone");
                } else {
                    // no app named: the bridge lists the installed ones, one per line
                    const said = outText(data);
                    if (/installed app|matching/.test(said))
                        root.androidApps = said.split("\n").map(l => l.trim().replace(/^-\s*/, ""))
                            .filter(l => l !== "" && l.indexOf("installed app") < 0);
                    root.note = Tr.t("App list read");
                }
            } else if (verb === "file") {
                root.note = Tr.t("File sent to the phone");
            } else {
                root.note = outText(data) || Tr.t("Done");
            }
        } else if (what === "connect") {
            root.note = failed || Tr.t("Connected");
            if (!failed) enqueue("android", ["info"]);
        } else if (what === "screen") {
            if (failed) { root.note = failed; root.screenState = String((data && data.state) || "off"); return; }
            root.screenState = String((data && data.state) || "off");
            root.note = job.act === "start" ? Tr.t("The phone is showing this screen")
                : job.act === "stop" ? Tr.t("Screen sharing stopped") : "";
        } else if (what === "fm") {
            const verb = job.act;
            // reports answer in the radio's own words; they never say whether
            // a station is playing, so they must not touch the tuner's state
            if (verb === "bands" || verb === "volume" || verb === "decode" || verb === "scan") {
                root.fmReport = String((data && data.text) || "");
                root.fmReportError = !!failed;
                if (!failed && verb === "volume") root.fmVolume = job.arg1;
                root.note = failed || Tr.t("Radio answered");
                return;
            }
            if (failed) { root.note = failed; root.fmState = String((data && data.state) || "off"); return; }
            root.fmState = String((data && data.state) || "off");
            const f = Number(data && data.frequency);
            if (f > 0) root.fmFrequency = f;
            root.note = job.act === "start" ? Tr.t("Radio playing")
                : job.act === "stop" ? Tr.t("Radio stopped")
                : job.act === "tune" ? Tr.t("Tuned to %1", root.fmFrequency) : "";
        } else if (what === "nfc") {
            if (failed) { root.note = failed; return; }
            if (job.act === "read") {
                root.nfcText = String((data && data.text) || "");
                root.note = root.nfcText !== "" ? Tr.t("Read: %1", root.nfcText) : Tr.t("No tag was read");
            } else {
                root.note = Tr.t("Written to the tag");
            }
        } else if (what === "ir") {
            if (failed) { root.note = failed; return; }
            if (job.act === "list") {
                root.irCodes = Array.isArray(data && data.codes) ? data.codes : [];
                root.irRemote = job.arg1;
                // a lone remote is not a code to send: fetch its buttons so the
                // chips say what can be pressed (and a send has a real code).
                if (!job.arg1 && root.irCodes.length === 1 && typeof root.irCodes[0] === "string")
                    enqueue("ir", ["list", root.irCodes[0]]);
            } else {
                root.note = Tr.t("Code sent");
            }
        } else if (what === "lines") {
            root.callLines = Array.isArray(data) ? data : [];
        }
    }

    Process {
        id: job
        property string what: ""
        property string act: ""
        property string arg1: ""
        property string arg2: ""
        stdout: StdioCollector { id: out }
        onExited: code => {
            root.finished(job.what, out.text, code);
            root.busy = false;
            root.pump();
        }
    }

    Component.onCompleted: refresh()
}
