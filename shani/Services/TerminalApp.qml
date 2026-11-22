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
    property bool busy: false
    property string error: ""
    readonly property string sshDir: Quickshell.env("HOME") + "/.ssh"
    readonly property string hostsFile: sshDir + "/shani-terminal-hosts.json"

    function refresh() { hosts.running = true; keys.running = true; }

    // ---- host management ----
    function addHost(name, host, port, user, key, type) {
        const h = {
            id: String(Date.now()) + Math.floor(Math.random() * 1000),
            name: name || host, host: host, port: parseInt(port) || 22, user: user || Quickshell.env("USER"),
            key: key || "", type: type || "ssh", pinned: false,
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
    function connect(host) {
        if (!host) return;
        if (host.type === "serial") {
            Quickshell.execDetached(["sh", "-c", 'command -v picocom >/dev/null 2>&1 && exec picocom "$1" || echo "picocom is not installed"'
            , "sh", host.port]);
        } else {
            Quickshell.execDetached(["sh", "-c",
                'exec ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="~/.ssh/known_hosts.shani" -p "$2" -i "$3" "$1"'
            , "sh", host.user + "@" + host.host, String(host.port), host.key ? sshDir + "/" + host.key : ""]);
        }
    }
    function testConnection(host, cb) {
        if (!host) { cb("error", Tr.t("No host selected")); return; }
        busy = true;
        testProc.command = ["sh", "-c",
            'ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$2" "$1" "echo OK" 2>&1'
        , "sh", host.user + "@" + host.host, String(host.port || 22)];
        testProc.running = true;
        cbStore = cb;
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
            if (t === "OK") { root.busy = false; root.cbStore && root.cbStore("ok", "OK"); root.cbStore = null; }
            else { root.busy = false; root.cbStore && root.cbStore("error", t || Tr.t("Could not connect")); root.cbStore = null; }
        } }
        onExited: code => { root.busy = false; if (code !== 0 && root.cbStore) { root.cbStore("error", Tr.t("Could not connect: %1", root.testErr)); root.cbStore = null; } }
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