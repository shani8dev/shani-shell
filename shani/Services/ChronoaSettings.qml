pragma Singleton
// The engine's own settings, read and written through Agent.Settings*. All
// logic lives here; the settings page only draws rows and asks for consent.
// A secret value is never published to the shell or kept in a setting.
import Quickshell
import QtQuick
import qs.Common
import "../Modules/Settings/ChronoaSettings.js" as Words

Singleton {
    id: root
    property bool busy: false
    property bool ready: false
    property string error: ""
    property var rows: []
    property var described: []
    property int seq: 0
    property var pending: null          // { kind, name, value } awaiting a yes
    property string lastWrite: ""
    property var confirmations: []

    function publish() {
        const o = Object.assign({}, Ui.chronoaState || {});
        o.settings = {
            ready: root.ready,
            error: root.error,
            count: root.rows.length,
            names: root.rows.map(r => r.name),
            groups: root.described.map(d => d.group),
            secretsHidden: root.rows.every(r => !r.secret || r.value === ""),
            pending: root.pending ? root.pending.name : "",
            lastWrite: root.lastWrite,
            confirmations: root.confirmations.slice()
        };
        Ui.chronoaState = o;
    }

    function describe() {
        root.described = root.rows.map(Words.describe);
        root.publish();
    }

    function refresh() {
        root.seq += 1;
        root.busy = true;
        root.error = "";
        if (!Bridge.send({ op: "settings-list", id: "sl" + root.seq })) {
            root.busy = false;
            root.error = Tr.t("Could not reach the answer engine");
        }
        root.publish();
    }

    // A consent switch turned on and any API key need the person's yes first.
    // Everything else goes straight through, with confirm=false.
    function ask(name, value) {
        const row = root.rows.find(r => r.name === name);
        if (!row) return false;
        const needs = !!row.secret || (!!row.consent_key && Words.isOn(value));
        if (!needs) { root.commit(name, value, false); return false; }
        root.pending = { kind: "set", name: name, value: String(value) };
        root.publish();
        return true;
    }

    function askPreset(name) {
        root.pending = { kind: "preset", name: name, value: "" };
        root.publish();
        return true;
    }

    function cancel() { root.pending = null; root.publish(); }

    function confirm() {
        if (!root.pending) return;
        const p = root.pending;
        root.pending = null;
        root.confirmations = root.confirmations.concat([p.kind + ":" + p.name]).slice(-8);
        if (p.kind === "preset") {
            root.seq += 1;
            if (!Bridge.send({ op: "settings-preset", id: "sp" + root.seq,
                               name: p.name, confirm: true }))
                root.error = Tr.t("Could not reach the answer engine");
        } else {
            root.commit(p.name, p.value, true);
        }
        root.publish();
    }

    function commit(name, value, confirmed) {
        root.seq += 1;
        root.lastWrite = name;
        root.busy = true;
        if (!Bridge.send({ op: "settings-set", id: "ss" + root.seq, name: name,
                           value: String(value), confirm: confirmed })) {
            root.busy = false;
            root.error = Tr.t("Could not reach the answer engine");
        }
        root.publish();
    }

    function reread(name) {
        root.seq += 1;
        if (!Bridge.send({ op: "settings-get", id: "sg" + root.seq, name: name }))
            root.error = Tr.t("Could not reach the answer engine");
    }

    Connections {
        target: Bridge
        function onMessage(msg) {
            if (!msg || msg.type !== "settings") return;
            const id = String(msg.id || "");
            const op = id.slice(0, 2);
            if (["sl", "sg", "ss", "sp"].indexOf(op) < 0) return;   // another client's reply
            if (msg.error) {
                root.busy = false;
                root.error = String(msg.error);
                root.publish();
                return;
            }
            if (op === "sl") {
                root.rows = Array.isArray(msg.data) ? msg.data : [];
                root.ready = true;
                root.describe();
            } else if (op === "sg") {
                const updated = msg.data;
                if (updated && updated.name)
                    root.rows = root.rows.map(r => r.name === updated.name ? updated : r);
                root.describe();
            } else if (op === "ss") {
                root.error = "";
                root.reread(String(msg.name || ""));
            } else if (op === "sp") {
                root.error = "";
                root.refresh();
            }
            root.busy = false;
            root.publish();
        }
    }

    Component.onCompleted: refresh()
}
