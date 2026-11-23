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
    property bool probed: false        // the startup read has answered: below states are real
    property string defaultZone: ""
    property var zones: []             // [{ name, active, target, services, ports, interfaces, rich }]
    property var zoneNames: []         // every zone, active or not (--get-zones)
    property string note: ""           // what the last change said, for the page

    // the zones worth offering: the person's own first, then the usual ones. What
    // firewalld really has always wins over this list - a zone can be added.
    readonly property var usual: ["public", "home", "work", "internal", "trusted", "block", "drop"]
    readonly property var named: {
        const have = root.zoneNames.length ? root.zoneNames : root.zones.map(z => z.name);
        return root.usual.filter(z => have.indexOf(z) >= 0)
            .concat(have.filter(z => root.usual.indexOf(z) < 0).sort());
    }

    function refresh() { read.running = false; read.running = true; }

    // "public (active)\n  target: default\n  services: ssh 80/tcp" -> the zone list
    // A rich rule is one indented line under "rich rules:" that is not a
    // "key: value" pair ("rule family=… service name="ssh" reject").
    function parseZones(text) {
        const out = [];
        let cur = null;
        let rich = false;
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (/^\S/.test(line)) {                       // a zone header, not indented
                const m = /^(\S+)/.exec(line);
                if (!m) continue;
                cur = { name: m[1], active: line.indexOf("(active)") >= 0, target: "default",
                        services: [], ports: [], protocols: [], rich: [], interfaces: [] };
                out.push(cur);
                rich = false;
                continue;
            }
            if (!cur) continue;
            const kv = /^\s+([a-z][a-z ]*):\s*(.*)$/.exec(line);
            if (kv) {
                const list = kv[2].trim() ? kv[2].trim().split(/\s+/) : [];
                rich = kv[1] === "rich rules";
                if (rich && list.length) cur.rich = list;
                else if (kv[1] === "services") cur.services = list;
                else if (kv[1] === "ports") cur.ports = list;
                else if (kv[1] === "protocols") cur.protocols = list;
                else if (kv[1] === "interfaces") cur.interfaces = list;
                else if (kv[1] === "target") cur.target = list.length ? list[0] : "default";
                continue;
            }
            if (rich && /^\s+rule\s/.test(line)) cur.rich.push(line.trim());
        }
        return out;
    }

    function zone(name) {
        const z = root.zones.filter(z => z.name === name)[0];
        return z || { name: name, active: false, target: "default", services: [], ports: [], protocols: [], rich: [], interfaces: [] };
    }

    Process {
        id: read
        command: ["sh", "-c", 'command -v "$1" >/dev/null 2>&1 || exit 3; "$1" --state >/dev/null 2>&1 || exit 4; echo "default=$("$1" --get-default-zone 2>/dev/null)"; echo "zones=$("$1" --get-zones 2>/dev/null | tr "\\n" " ")"; "$1" --list-all-zones 2>/dev/null', "sh", root.tool]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                root.probed = true;
                root.available = true;
                root.running = true;
                const m = /^default=(.*)$/.exec(lines[0] || "");
                root.defaultZone = (m && m[1].trim()) || "";
                const zs = /^zones=(.*)$/.exec(lines[1] || "");
                root.zoneNames = zs ? zs[1].trim().split(/\s+/).filter(x => x) : [];
                root.zones = root.parseZones(lines.slice(2).join("\n"));
            }
        }
        onExited: code => {
            root.probed = true;
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

    // ---- rich rules ---------------------------------------------------------
    // One rule says more than a port or a service can: who (a source address or
    // range), what, and what happens - accept, reject or drop - optionally only
    // up to a rate ("2/m"), logging, or forwarding a port elsewhere. firewalld
    // takes it as one quoted argument and hands it back verbatim, so that same
    // string is what removes it again.
    function addRich(zone, rule) {
        const r = String(rule || "").trim();
        if (r) run(["--zone=" + zone, "--add-rich-rule=" + r]);
    }
    function removeRich(zone, rule) { run(["--zone=" + zone, "--remove-rich-rule=" + rule]); }

    // firewalld's own presets, in its own words: enough to reach for without
    // remembering the syntax
    readonly property var richPresets: [
        { label: "Reject ping", rule: 'rule protocol value="icmp" reject' },
        { label: "Allow this network to reach SSH", rule: 'rule family="ipv4" source address="192.168.1.0/24" service name="ssh" accept' },
        { label: "Limit new SSH connections", rule: 'rule service name="ssh" limit value="3/m" accept' },
        { label: "Log and reject", rule: 'rule service name="telnet" log prefix="telnet" level="info" limit value="2/m" reject' },
    ];

    // ---- zones --------------------------------------------------------------
    // A new zone is permanent-only in firewalld, so it is created with
    // --permanent and needs no runtime-to-permanent; a reload is not needed
    // either, the zone is there at once.
    function newZone(name) { run(["--permanent", "--new-zone=" + String(name || "").trim()], false); }
    function deleteZone(name) { run(["--permanent", "--delete-zone=" + name], false); }

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
