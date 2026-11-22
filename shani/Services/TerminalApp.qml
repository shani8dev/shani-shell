pragma Singleton
// Terminal: a SSH connection manager (like PuTTY) with host groups and
// key management. Hosts are stored in ~/.ssh/shani-terminal-hosts.json.
// Keys are listed/generated via ssh-keygen, stored in ~/.ssh/.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property var hosts: []               // [{ id, name, host, port, user, key, type }]
    property var keys: []                // [{ id, name, fingerprint, path }]
    property var tunnels: []             // [{ id, pidfile, label, host, localPort, remoteHost, remotePort }]
    property var snippets: Settings.loaded ? (Settings.data.sshSnippets || []) : []
    property bool busy: false
    property string error: ""
    readonly property string sshDir: Quickshell.env("HOME") + "/.ssh"
    readonly property string hostsFile: sshDir + "/shani-terminal-hosts.json"

    function refresh() { hosts.running = true; keys.running = true; }

    // ---- host management ----
    function addHost(name, host, port, user, key, type, opts) {
        const o = opts || {};
        const h = {
            id: String(Date.now()) + Math.floor(Math.random() * 1000),
            name: name || host, host: host, port: parseInt(port) || 22, user: user || Quickshell.env("USER"),
            key: key || "", type: type || "ssh", pinned: false,
            proxyJump: o.proxyJump || "", forwardAgent: !!o.forwardAgent, x11: !!o.x11,
            compression: !!o.compression, extraOpts: Array.isArray(o.extraOpts) ? o.extraOpts : [],
            lastConnected: 0, status: "", lastTested: 0,
        };
        hosts = hosts.concat([h]);
        saveHostsTimer.restart();
    }
    function updateHost(id, fields) {
        hosts = hosts.map(h => h.id === id ? Object.assign({}, h, fields) : h);
        saveHostsTimer.restart();
    }
    function deleteHost(id) {
        hosts = hosts.filter(h => h.id !== id);
        saveHostsTimer.restart();
    }
    function togglePin(id) {
        const h = hosts.find(h => h.id === id);
        if (h) updateHost(id, { pinned: !h.pinned });
    }

    // ---- key management ----
    function generateKey(name, bits) {
        busy = true;
        genProc.command = ["sh", "-c",
            'ssh-keygen -t rsa -b ' + String(bits || 2048) + ' -f "$1" -N "" -C "$2" 2>/dev/null && echo "OK"'
        , "sh", sshDir + "/" + String(name || ("key-" + Date.now())), name || "ssh-key"];
        genProc.running = true;
    }
    function importKey(srcPath, name) {
        if (!srcPath || !name) return;
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p "$2"; cp "$1" "$2"; chmod 600 "$2" 2>/dev/null; fp=$(ssh-keygen -lf "$2" 2>/dev/null | awk "{print \\$2}") || fp="unknown"; echo "$fp" > "$2.fingerprint" 2>/dev/null || true'
        , "sh", srcPath, sshDir + "/" + name]);
        refresh();
    }

    // ---- connect / test ----
    // Build ssh's argv directly — no shell string, so an option typed by the
    // person can never become another command. ProxyJump, forwarding, X11,
    // compression and arbitrary -o values are all ordinary argv slots.
    function sshArgs(host, extra) {
        const a = ["ssh", "-o", "StrictHostKeyChecking=accept-new",
                   "-o", "UserKnownHostsFile=" + sshDir + "/known_hosts.shani",
                   "-p", String(host.port || 22)];
        if (host.key) a.push("-i", sshDir + "/" + host.key);
        if (host.proxyJump) a.push("-J", String(host.proxyJump));
        if (host.forwardAgent) a.push("-A");
        if (host.x11) a.push("-X");
        if (host.compression) a.push("-C");
        for (const o of (host.extraOpts || [])) a.push("-o", String(o));
        return a.concat(extra || [], [String(host.user || "") + "@" + host.host]);
    }
    function connect(host) {
        if (!host) return;
        if (host.type === "serial") {
            Quickshell.execDetached(["picocom", String(host.port)]);
        } else {
            Quickshell.execDetached(sshArgs(host));
        }
        // a recents list: when this host was last launched (not proof it stayed up)
        if (host.id !== undefined) updateHost(host.id, { lastConnected: Date.now() });
    }
    function testConnection(host, cb) {
        if (!host) { cb("error", Tr.t("No host selected")); return; }
        busy = true;
        testProc.command = sshArgs(host, ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "echo", "OK"]);
        testProc.running = true;
        cbStore = cb;
        testedId = host.id;
    }
    property var testedId: null
    function recordTest(id, ok) {
        if (id !== undefined && id !== null)
            updateHost(id, { status: ok ? "ok" : "failed", lastTested: Date.now() });
    }

    // ---- port forwards: -L local, -R remote, -D dynamic SOCKS, kept in the background ----
    // For -R the "local port" is the port opened on the server; for -D only a
    // port is needed. Every value reaches ssh as argv, never inside a shell string.
    function tunnel(h, localPort, remoteHost, remotePort, mode) {
        if (!h) return "";
        const lp = parseInt(localPort, 10), rp = parseInt(remotePort, 10);
        if (!lp || lp < 1 || lp > 65535) return "";
        const m = ["L", "R", "D"].indexOf(mode) >= 0 ? mode : "L";
        if (m !== "D" && (!rp || rp < 1 || rp > 65535)) return "";
        if (m !== "D" && !remoteHost) return "";
        const id = String(Date.now()) + Math.floor(Math.random() * 1000);
        const pidfile = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-tunnel-" + id + ".pid";
        const sshArgs = ["ssh", "-N", "-o", "StrictHostKeyChecking=accept-new", "-p", String(h.port || 22)];
        if (h.key) sshArgs.push("-i", sshDir + "/" + h.key);
        if (m === "L") sshArgs.push("-L", lp + ":" + remoteHost + ":" + rp);
        else if (m === "R") sshArgs.push("-R", lp + ":" + remoteHost + ":" + rp);
        else sshArgs.push("-D", String(lp));
        sshArgs.push(h.user + "@" + h.host);
        // $1 is the pidfile; the rest is the ssh command, run detached with nohup
        Quickshell.execDetached(["sh", "-c", 'pf=$1; shift; nohup "$@" >/dev/null 2>&1 & echo $! > "$pf"', "sh", pidfile].concat(sshArgs));
        const label = m === "D" ? "SOCKS " + lp : (m === "R" ? "remote " : "") + lp + " → " + remoteHost + ":" + rp;
        root.tunnels = root.tunnels.concat([{ id: id, pidfile: pidfile, mode: m,
            label: label + " · " + (h.name || h.host),
            host: h.host, localPort: lp, remoteHost: remoteHost, remotePort: rp }]);
        return id;
    }
    function stopTunnel(id) {
        const t = root.tunnels.find(x => x.id === id);
        if (!t) return;
        Quickshell.execDetached(["sh", "-c", 'if [ -f "$1" ]; then kill "$(cat "$1")" 2>/dev/null || true; rm -f "$1"; fi', "sh", t.pidfile]);
        root.tunnels = root.tunnels.filter(x => x.id !== id);
    }

    // ---- hosts JSON import / export -------------------------------------------
    // The whole host list moves in and out as JSON, so it can be moved to a
    // new machine. Import merges by id; it never drops a host already here.
    function exportHosts(path) {
        if (!path) return false;
        exportProc.command = ["sh", "-c", 'd=${1%/*}; [ -n "$d" ] && [ "$d" != "$1" ] && mkdir -p "$d"; printf "%s" "$2" > "$1"',
            "sh", path, JSON.stringify(hosts)];
        exportProc.running = true;
        return true;
    }
    function importHosts(path) {
        if (!path) return false;
        importProc.command = ["sh", "-c", 'cat "$1" 2>/dev/null || echo "[]"', "sh", path];
        importProc.running = true;
        return true;
    }
    Process { id: exportProc; stdout: StdioCollector { onStreamFinished: { root.error = ""; } } }
    Process {
        id: importProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const incoming = JSON.parse(text);
                    if (!Array.isArray(incoming)) throw new Error("not a list");
                    const seen = {};
                    for (const h of hosts) seen[h.id] = true;
                    const add = incoming.filter(h => h && h.host && h.id && !seen[h.id]).map(h => ({
                        id: String(h.id), name: h.name || h.host, host: String(h.host),
                        port: parseInt(h.port) || 22, user: h.user || Quickshell.env("USER"),
                        key: h.key || "", type: h.type || "ssh", pinned: !!h.pinned,
                        proxyJump: h.proxyJump || "", forwardAgent: !!h.forwardAgent,
                        x11: !!h.x11, compression: !!h.compression,
                        extraOpts: Array.isArray(h.extraOpts) ? h.extraOpts : [],
                        lastConnected: h.lastConnected || 0, status: h.status || "", lastTested: h.lastTested || 0,
                    }));
                    root.hosts = root.hosts.concat(add);
                    saveHostsTimer.restart();
                    root.error = "";
                } catch (e) {
                    root.error = Tr.t("That file is not a host list");
                }
            }
        }
    }

    // ---- SSH snippets: stored in Settings.data.sshSnippets ----
    function addSnippet(name, command) {
        name = String(name || "").trim();
        command = String(command || "").trim();
        if (!name || !command) return;
        const next = root.snippets.filter(s => s.name !== name).concat([{ name: name, command: command }]);
        root.snippets = next;
        Settings.data.sshSnippets = next;
    }
    function deleteSnippet(name) {
        const next = root.snippets.filter(s => s.name !== name);
        root.snippets = next;
        Settings.data.sshSnippets = next;
    }

    // ---- internals ----
    property var cbStore: null
    Timer { id: saveHostsTimer; interval: 500; onTriggered: writeHosts() }
    function writeHosts() {
        writeFileTimer.setText(JSON.stringify(hosts));
    }
    Timer { id: writeFileTimer; interval: 300; onTriggered: {
        writeFile.path = hostsFile;
        writeFile.setText(text);
    } property string text: "" }

    Process {
        id: genProc
        stdout: StdioCollector { onStreamFinished: { if (text.trim() === "OK") { root.busy = false; root.refresh(); } } }
        onExited: code => { root.busy = false; if (code !== 0) root.error = Tr.t("Could not generate the key"); else root.refresh(); }
    }
    Process {
        id: testProc
        stdout: StdioCollector { onStreamFinished: {
            const t = text.trim();
            const ok = t === "OK";
            if (ok) { root.busy = false; root.recordTest(root.testedId, true); root.cbStore && root.cbStore("ok", "OK"); root.cbStore = null; }
            else { root.busy = false; root.recordTest(root.testedId, false); root.cbStore && root.cbStore("error", t || Tr.t("Could not connect")); root.cbStore = null; }
        } }
        onExited: code => { root.busy = false; if (code !== 0 && root.cbStore) { root.recordTest(root.testedId, false); root.cbStore("error", Tr.t("Could not connect: %1", root.testErr)); root.cbStore = null; } }
        stderr: StdioCollector { id: testErr }
    }
    property string testErr: ""

    Process { id: hosts; command: ["sh", "-c", 'cat "$1" 2>/dev/null || echo "[]"', "sh", root.hostsFile]
        stdout: StdioCollector { onStreamFinished: { try { root.hosts = JSON.parse(text); } catch (e) { root.hosts = []; } } }
        onExited: code => { if (code !== 0) root.hosts = []; }
    }
    Process { id: keys; command: ["sh", "-c",
        'd="$1"; [ -d "$d" ] || exit 0; for f in "$d"/*.pub "$d"/*.pem; do [ -f "$f" ] && echo "$(ssh-keygen -lf "$f" 2>/dev/null | awk "{print \\$2}") $(basename "$f")"; done 2>/dev/null | head -20', "sh", root.sshDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l !== "");
                root.keys = lines.map((line, i) => {
                    const parts = line.split(" ");
                    const name = (parts[1] ? parts[1].replace(/\.ssh$/, "").replace(/\.pem$/, "") : "key-" + i) || ("key-" + i);
                    return { id: "k" + i + Date.now(), name: name, fingerprint: parts[0] || "", path: root.sshDir + "/" + name };
                });
            }
        }
    }

    FileView {
        id: writeFile
        path: root.hostsFile
        onTextChanged: {}
        printErrors: false
    }

    Component.onCompleted: refresh()
}