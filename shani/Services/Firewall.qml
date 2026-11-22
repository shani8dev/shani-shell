pragma Singleton
// The firewall: firewalld, read and changed through firewall-cmd.
//
// One read pass gets the whole picture — is firewalld up, what the default zone
// is, and every zone with its services and ports — so the page never shows half
// a state. A change is made at runtime and then written through with
// --runtime-to-permanent: it survives a reload, and it does not drop the
// connections that are open right now (a --reload would).
//
// firewall-cmd talks to firewalld over D-Bus, so a normal user may ask; polkit
// asks for the password when the change needs one.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_FIREWALL_CMD") || "firewall-cmd"

    property bool available: false     // firewall-cmd is installed
    property bool running: false       // firewalld is up
    property string defaultZone: ""
    property var zones: []             // [{ name, active, target, services, ports, interfaces }]
    property string note: ""           // what the last change said, for the page

    // the zones worth offering: the person's own first, then the usual ones
    readonly property var named: ["public", "home", "work", "internal", "trusted", "block", "drop"]

    function refresh() { read.running = false; read.running = true; }

    // "public (active)\n  target: default\n  services: ssh 80/tcp" -> the zone list
    function parseZones(text) {
        const out = [];
        let cur = null;
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (/^\S/.test(line)) {                       // a zone header, not indented
                const m = /^(\S+)/.exec(line);
                if (!m) continue;
                cur = { name: m[1], active: line.indexOf("(active)") >= 0, target: "default",
                        services: [], ports: [], interfaces: [] };
                out.push(cur);
                continue;
            }
            if (!cur) continue;
            const kv = /^\s+([a-z-]+):\s*(.*)$/.exec(line);
            if (!kv) continue;
            const list = kv[2].trim() ? kv[2].trim().split(/\s+/) : [];
            if (kv[1] === "services") cur.services = list;
            else if (kv[1] === "ports") cur.ports = list;
            else if (kv[1] === "interfaces") cur.interfaces = list;
            else if (kv[1] === "target") cur.target = list.length ? list[0] : "default";
        }
        return out;
    }

    function zone(name) {
        const z = root.zones.filter(z => z.name === name)[0];
        return z || { name: name, active: false, target: "default", services: [], ports: [], interfaces: [] };
    }

    Process {
        id: read
        command: ["sh", "-c", 'command -v "$1" >/dev/null 2>&1 || exit 3; "$1" --state >/dev/null 2>&1 || exit 4; echo "default=$("$1" --get-default-zone 2>/dev/null)"; "$1" --list-all-zones 2>/dev/null', "sh", root.tool]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                root.available = true;
                root.running = true;
                const m = /^default=(.*)$/.exec(lines[0] || "");
                root.defaultZone = (m && m[1].trim()) || "";
                root.zones = root.parseZones(lines.slice(1).join("\n"));
            }
        }
        onExited: code => {
            if (code === 3) { root.available = false; root.running = false; root.zones = []; }
            else if (code === 4) { root.available = true; root.running = false; root.zones = []; }
        }
    }

    // one change: run the arguments, then make them permanent. `permanent`
    // false for --set-default-zone, which is permanent on its own.
    function run(args, permanent) {
        const tail = permanent === false ? "" : ' && "$tool" --runtime-to-permanent';
        apply.command = ["sh", "-c",
            'tool="$1"; shift; "$tool" --state >/dev/null 2>&1 || exit 4; "$tool" "$@" ' + tail,
            "sh", root.tool].concat(args);
        apply.running = false;
        apply.running = true;
    }

    // the firewall itself: start or stop firewalld
    function setEnabled(on) {
        apply.command = ["sh", "-c",
            'tool="$1"; shift; if [ "$1" = on ]; then pf=enable; else pf=disable; fi; shift; systemctl "$pf" --now firewalld >/dev/null 2>&1 || exit 5; "$tool" --state >/dev/null 2>&1 || exit 4',
            "sh", root.tool, on ? "on" : "off"];
        apply.running = false;
        apply.running = true;
    }

    function setDefaultZone(zone) { run(["--set-default-zone=" + zone], false); }
    function addService(zone, service) { run(["--zone=" + zone, "--add-service=" + service]); }
    function removeService(zone, service) { run(["--zone=" + zone, "--remove-service=" + service]); }
    function addPort(zone, port) { run(["--zone=" + zone, "--add-port=" + port]); }
    function removePort(zone, port) { run(["--zone=" + zone, "--remove-port=" + port]); }

    Process {
        id: apply
        stderr: StdioCollector { id: applyErr }
        onExited: code => {
            if (code === 0) root.note = "";
            else if (code === 4) root.note = Tr.t("The firewall is not running");
            else if (code === 5) root.note = Tr.t("That needs administrator rights");
            else root.note = (applyErr.text || "").trim() || Tr.t("The firewall refused that");
            read.running = false;
            read.running = true;
        }
    }

    Component.onCompleted: refresh()
}