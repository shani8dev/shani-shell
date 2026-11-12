pragma Singleton
// Nearby (Modules/Nearby shows it): files to and from devices on the same
// network that run LocalSend - Android, iPhone, Windows, Mac, Linux - with
// bridge/nearby.py speaking LocalSend's protocol. Running while the window is
// open, or while the person has made this computer visible.
//
// Visible is off by default and does not outlive the session: turning it on
// opens LocalSend's port in the firewall for this session only (firewall-cmd
// without --permanent, which asks for the person's password through the
// shell's polkit agent); turning it off, or a restart, closes it again. Every
// transfer is asked - here and as a notification - before anything is written.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_NEARBY_TOOL") || "/usr/lib/shani-shell/nearby.py"
    readonly property string firewallCmd: Quickshell.env("SHANI_FIREWALL_CMD") || "firewall-cmd"
    readonly property int port: 53317
    property var devices: []          // [{ alias, fingerprint, deviceModel, deviceType, ip, port, protocol }]
    property var offers: []           // [{ session, from, files: [{ name, size }] }]
    property var transfers: ({})      // session -> { direction, done, total, to, state: "going"|"done"|"failed", error, files }
    property var pending: []          // files chosen to send (the Share sheet's, or picked)
    property bool visible_: false     // this computer can be found and sent to
    property bool scanning: false
    property string me: ""
    property string note: ""
    readonly property bool running: bridge.running

    function scan() { if (send({ op: "scan" })) scanning = true; }
    function sendTo(fp) { if (pending.length) send({ op: "send", to: fp, files: pending }); }
    function answer(sessionId, accept) {
        send({ op: "answer", session: sessionId, accept: accept });
        offers = offers.filter(o => o.session !== sessionId);
    }
    function setVisible(on) {
        if (on) {
            // the port first, then the listening: no window where it listens behind a closed port
            firewall.want = true;
            firewall.command = ["sh", "-c", '"$1" --state >/dev/null 2>&1 || exit 0; "$1" --add-port="$2"/tcp --add-port="$2"/udp', "sh", root.firewallCmd, String(root.port)];
            firewall.running = true;
        } else {
            send({ op: "visible", on: false });
            firewall.want = false;
            firewall.command = ["sh", "-c", '"$1" --state >/dev/null 2>&1 || exit 0; "$1" --remove-port="$2"/tcp --remove-port="$2"/udp', "sh", root.firewallCmd, String(root.port)];
            firewall.running = true;
        }
    }
    Process {
        id: firewall
        property bool want: false
        stderr: StdioCollector { id: fwErr }
        onExited: code => {
            if (!firewall.want)
                return;
            if (code === 0)
                root.send({ op: "visible", on: true });
            else
                root.note = Tr.t("The firewall was not opened, so nothing can reach this computer") + (fwErr.text.trim() ? ": " + fwErr.text.trim().split("\n").pop() : "");
        }
    }

    function send(obj) {
        if (!bridge.running)
            bridge.running = true;
        bridge.write(JSON.stringify(obj) + "\n");
        return true;
    }
    function setTransfer(sid, patch) {
        const t = Object.assign({}, root.transfers);
        t[sid] = Object.assign({}, t[sid] || {}, patch);
        root.transfers = t;
    }
    // kept running while the window is open or while visible; closed otherwise
    readonly property bool wanted: Ui.nearby || visible_
    onWantedChanged: if (!wanted && bridge.running) bridge.running = false
    Process {
        id: bridge
        command: ["python3", root.tool]
        stdinEnabled: true
        onRunningChanged: if (!running) { root.visible_ = false; root.scanning = false; }
        stdout: SplitParser {
            onRead: line => {
                let e = null;
                try { e = JSON.parse(line); } catch (err) { return; }
                if (e.event === "ready") root.me = e.alias;
                else if (e.event === "device") root.devices = root.devices.filter(d => d.fingerprint !== e.fingerprint).concat([e]);
                else if (e.event === "scanned") root.scanning = false;
                else if (e.event === "visible") root.visible_ = e.on;
                else if (e.event === "offer") {
                    root.offers = root.offers.concat([e]);
                    ask.offer(e);
                } else if (e.event === "progress") root.setTransfer(e.session, { direction: e.direction, done: e.done, total: e.total, to: e.to || "", state: "going" });
                else if (e.event === "finished") {
                    root.setTransfer(e.session, { direction: e.direction, state: "done", files: e.files });
                    if (e.direction === "receive")
                        Quickshell.execDetached(["notify-send", "-a", "Nearby", "-i", "folder-download", Tr.t("Received"), e.files.map(f => f.split("/").pop()).join(", ")]);
                } else if (e.event === "failed") {
                    if (e.session) root.setTransfer(e.session, { direction: e.direction, state: "failed", error: e.error });
                    else root.note = e.error;
                    root.offers = root.offers.filter(o => o.session !== e.session);
                }
            }
        }
    }
    // an offer, as a notification with Accept and Decline (the window has them too)
    Process {
        id: ask
        property string sessionId: ""
        function offer(e) {
            if (running)
                return;              // one asked at a time; the window shows the rest
            sessionId = e.session;
            const names = e.files.map(f => f.name);
            command = ["notify-send", "-a", "Nearby", "-i", "network-wireless", "-u", "critical", "-w",
                       "-A", "accept=" + Tr.t("Accept"), "-A", "decline=" + Tr.t("Decline"),
                       Tr.t("%1 wants to send you a file").arg(e.from),
                       names.slice(0, 3).join(", ") + (names.length > 3 ? " " + Tr.t("and %1 more").arg(names.length - 3) : "")];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const a = text.trim();
                if ((a === "accept" || a === "decline") && root.offers.some(o => o.session === ask.sessionId))
                    root.answer(ask.sessionId, a === "accept");
            }
        }
    }
    function human(b) {
        const u = ["B", "kB", "MB", "GB"];
        let v = b, i = 0;
        while (v >= 1000 && i < u.length - 1) { v /= 1000; i++; }
        return (i === 0 ? v : v.toFixed(v < 10 ? 1 : 0)) + " " + u[i];
    }
}
