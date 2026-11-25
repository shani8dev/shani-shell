pragma Singleton
// NetworkManager VPN connections, read and changed through bridge/vpn.py.
//
// Net.qml already watches `nmcli monitor` for Wi-Fi/hotspot/VPN state; this
// service owns the CLI details it does not cover — connection type, autoconnect,
// profile import, per-connection stats and delete — over the same JSON bridge
// pattern Services/BootInfo and Services/Agenda use. Every action refreshes the
// list afterwards so the panel never shows a half-applied change. One Process at
// a time: `busy` guards both the buttons and the stats timer.
//
// Registering a system-bus SecretAgent (so VPN secrets never prompt) is out of
// scope for this round; NetworkManager's own agent still handles credentials.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_VPN_TOOL") || "/usr/lib/shani-shell/vpn.py"

    property bool busy: false
    property bool available: false       // nmcli is installed
    property bool probed: false          // the first list answer has arrived
    property var connections: []         // [{ name, type, state, autoconnect }]
    property var stats: ({})             // name -> { connected, rxBytes, txBytes, uptime, peer, state }
    property string error: ""            // last failure, for the panel's error state
    property string note: ""             // last successful action, briefly
    property string pending: ""          // command in flight, for the reply
    property string subject: ""          // name it was about

    function invoke(cmd, args, subject) {
        if (root.busy) return false;
        root.pending = cmd;
        root.subject = subject || "";
        root.busy = true;
        job.command = ["python3", root.tool, cmd].concat(args || []);
        job.running = false;
        job.running = true;
        return true;
    }

    function refresh() { return invoke("list", []); }
    function up(name) { return invoke("up", [name]); }
    function down(name) { return invoke("down", [name]); }
    function toggle(name, isUp) { return isUp ? root.up(name) : root.down(name); }
    function setAutoconnect(name, on) { return invoke("autoconnect", [name, on ? "true" : "false"], name); }
    function importFile(path) { return invoke("import", [path]); }
    function remove(name) { return invoke("delete", [name], name); }
    function refreshStats(name) { if (name) return invoke("stats", [name], name); return false; }

    Process {
        id: job
        stdout: StdioCollector { id: vpnOut }
        stderr: StdioCollector { id: vpnErr }
        onExited: code => {
            let d = {};
            try { d = JSON.parse((vpnOut.text || "").trim() || "{}") || {}; } catch (e) { d = {}; }
            const what = root.pending;
            const who = root.subject;
            root.pending = "";
            root.subject = "";
            root.busy = false;

            const bad = code !== 0 || d.ok !== true;
            const raw = String((vpnErr.text || "")).trim().split("\n").pop();
            root.error = bad ? (d.error || raw || Tr.t("VPN command failed")) : "";
            if (bad) root.note = root.error;

            if (what === "list") {
                root.probed = true;
                root.available = d.available !== false;
                root.connections = Array.isArray(d.connections) ? d.connections : [];
                // an absent nmcli is a healthy answer with an empty list, but
                // the panel must still say why it has nothing to show
                if (!root.available) root.error = d.error || Tr.t("nmcli is not installed");
            } else if (what === "stats") {
                if (who) {
                    const all = Object.assign({}, root.stats);
                    all[who] = d;
                    root.stats = all;
                }
            } else {
                if (!bad) {
                    root.note = what === "import" ? Tr.t("Profile imported as %1").arg(d.name || "")
                               : what === "autoconnect" ? Tr.t("Autoconnect updated for %1").arg(who)
                               : what === "delete" ? Tr.t("Connection deleted")
                               : what === "up" ? Tr.t("Connected to %1").arg(who)
                               : Tr.t("Disconnected from %1").arg(who);
                }
                root.refresh();
            }
        }
    }

    // Net's nmcli monitor already tells us when VPN connections come and go.
    Component.onCompleted: root.refresh()
    Connections {
        target: Net
        function onVpnsChanged() { root.refresh(); }
    }
}
