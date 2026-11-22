pragma Singleton
// Disks: all block devices on the system — disks, partitions, and their
// filesystems, sizes, mount points, SMART health. Destructive operations
// (erase, format, encrypt, install stick) run through pkexec with polkit
// authorisation and a two-click confirm in the UI.
//
// Read operations use lsblk / udisksctl / smartctl (no root needed).
// Write operations use pkexec + the standard tools (wipefs, mkfs.*, cryptsetup, dd).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property var disks: []            // [{ name, path, model, size, type, mountpoints, fstype, label, children, removable, hotplug, ro, majmin }]
    property var health: ({})         // { "/dev/sda": { overall, temp, hours, ... } }
    property var smart: ({})          // the full report for the SMART dialog
    property var benchmarkResult: null // { mbps, seconds, bytes }
    property real jobProgress: -1
    property string jobLabel: ""
    property string error: ""
    property bool busy: false

    readonly property var tool: Quickshell.env("SHANI_DISKS_TOOL") || "/usr/lib/shani-shell/disks.py"

    function refresh() {
        if (!lister.running) lister.running = true;
    }

    // ---- destructive operations (all need polkit) -------------------------------
    // Each returns via the writer process's stdout/stderr.
    // The UI must confirm before calling these.

    // Quick erase: wipe filesystem signatures (fast, not secure)
    function eraseQuick(device) {
        run(["erase-quick", device]);
    }

    // Secure erase: zero the first 100 MB (slower but safer)
    function eraseSecure(device) {
        run(["erase-secure", device]);
    }

    // Format: create a new filesystem
    // fstype: "ext4", "btrfs", "vfat", "xfs", "exfat"
    function format(device, fstype, label) {
        run(["format", device, fstype, label || ""]);
    }

    // Encrypt: LUKS format + open + create filesystem inside
    // fstype: the filesystem to create inside the encrypted container
    function encrypt(device, fstype, passphrase) {
        run(["encrypt", device, fstype, passphrase]);
    }

    // Install stick: write an ISO to a USB drive
    function installStick(device, iso) {
        run(["install-stick", device, iso]);
    }

    // ---- SMART health, details and self-tests -----------------------------------
    function checkHealth(device) {
        run(["health", device]);
    }
    function smartDetails(device) {
        run(["smart", device]);
    }
    // short / long / conveyance: a fixed set, never a typed command string
    function smartTest(device, kind) {
        if (["short", "long", "extended", "conveyance"].indexOf(kind) < 0) return;
        run(["smart-test", device, kind]);
    }
    function benchmark(device) {
        run(["benchmark", device]);
    }
    // chown the mounted filesystem to the signed-in user (two-click confirm in UI)
    function takeOwnership(device) {
        run(["take-ownership", device]);
    }

    // ---- mount / unmount / power-off --------------------------------------------
    function mount(device) {
        Quickshell.execDetached(["udisksctl", "mount", "-b", device]);
        Qt.callLater(root.refresh);
    }
    function unmount(device) {
        Quickshell.execDetached(["udisksctl", "unmount", "-b", device]);
        Qt.callLater(root.refresh);
    }
    function powerOff(device) {
        Quickshell.execDetached(["udisksctl", "power-off", "-b", device]);
        Qt.callLater(root.refresh);
    }
    // mount options: only a conservative charset reaches udisksctl, as argv
    function mountWithOptions(device, options) {
        const opts = String(options || "").trim();
        if (!/^[\w=,.-]*$/.test(opts)) return false;
        const cmd = ["udisksctl", "mount", "-b", device];
        if (opts) cmd.push("-o", opts);
        Quickshell.execDetached(cmd);
        Qt.callLater(root.refresh);
        return true;
    }
    // detach a loop device created for a disk image
    function detachLoop(device) {
        Quickshell.execDetached(["udisksctl", "loop-delete", "-b", device]);
        Qt.callLater(root.refresh);
    }
    // stop a running job: the pkexec helper is cancelled and the queue cleared
    function cancelJob() {
        writer.running = false;
        root._queue = [];
        root.busy = false;
        root.jobProgress = -1;
        root.jobLabel = "";
        root.error = Tr.t("Operation cancelled");
    }

    // ---- internal: one write at a time ------------------------------------------
    property var _queue: []
    property var currentArgs: []
    function run(args) { _queue = _queue.concat([args]); next(); }
    function next() {
        if (writer.running || _queue.length === 0)
            return;
        busy = true;
        root.currentArgs = _queue[0];
        root.jobLabel = String(_queue[0][0] || "").replace("-", " ");
        root.jobProgress = -1;
        writer.command = ["pkexec", root.tool].concat(_queue[0]);
        _queue = _queue.slice(1);
        writer.running = true;
    }

    // ---- listing ----------------------------------------------------------------
    Process {
        id: lister
        command: ["lsblk", "-J", "-b", "-p", "-o", "NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,LABEL,MODEL,RM,HOTPLUG,RO"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.disks = (data.blockdevices || []).map(d => ({
                        name: d.name || "",
                        path: d.path || ("/dev/" + d.name),
                        model: d.model || "",
                        size: root.humanSize(d.size || 0),
                        bytes: Number(d.size) || 0,
                        type: d.type || "disk",       // disk, part, loop, rom
                        fstype: d.fstype || "",
                        label: d.label || "",
                        mountpoints: d.mountpoints || [],
                        children: d.children || [],
                        removable: d.rm === true || d.rm === "true",
                        hotplug: d.hotplug === true || d.hotplug === "true",
                        ro: d.ro === true || d.ro === "true",
                        majmin: d.path || d.name || "",
                    }));
                } catch (e) {
                    root.disks = [];
                    root.error = Tr.t("Could not read the disk list");
                }
            }
        }
        onExited: code => { if (code !== 0) root.error = Tr.t("Could not read the disk list (is lsblk installed?)"); }
    }

    Process {
        id: writer
        stderr: StdioCollector { id: writeErr }
        // each helper line is JSON: either {"progress", "line"} or the final
        // result object (health / smart / benchmark).
        stdout: SplitParser {
            onRead: line => {
                const t = String(line).trim();
                if (!t.startsWith("{")) return;
                let r;
                try { r = JSON.parse(t); } catch (e) { return; }
                if (r.progress !== undefined && r.progress !== null) {
                    root.jobProgress = Number(r.progress) || 0;
                    if (r.line) root.jobLabel = String(r.line).slice(0, 120);
                    return;
                }
                const cmd = String(root.currentArgs[0] || "");
                const dev = String(root.currentArgs[1] || "");
                if (cmd === "health" || cmd === "smart") {
                    const nh = Object.assign({}, root.health);
                    if (dev) nh[dev] = r;
                    root.health = nh;
                    if (cmd === "smart") root.smart = r;
                } else if (cmd === "benchmark") {
                    root.benchmarkResult = r;
                }
            }
        }
        onExited: code => {
            root.busy = false;
            root.jobProgress = -1;
            root.jobLabel = "";
            root.currentArgs = [];
            if (code !== 0 && code !== 1)   // 1 = polkit dismissed, not an error
                root.error = writeErr.text.trim().split("\n").pop() || Tr.t("The operation failed");
            else
                root.error = "";
            root.refresh();
            root.next();
        }
    }

    // ---- helpers ----------------------------------------------------------------
    function humanSize(s) {
        const n = parseInt(s) || 0;
        if (n >= 1e12) return (n / 1e12).toFixed(1) + " TB";
        if (n >= 1e9)  return (n / 1e9).toFixed(1) + " GB";
        if (n >= 1e6)  return (n / 1e6).toFixed(1) + " MB";
        if (n >= 1e3)  return (n / 1e3).toFixed(1) + " KB";
        return n + " B";
    }

    // ---- filesystem choices -----------------------------------------------------
    readonly property var fstypes: [
        { id: "ext4",  name: "ext4",  desc: Tr.t("Linux — most compatible") },
        { id: "btrfs", name: "btrfs", desc: Tr.t("Linux — snapshots and compression") },
        { id: "vfat",  name: "vfat",  desc: Tr.t("USB / SD — works everywhere") },
        { id: "xfs",   name: "xfs",   desc: Tr.t("Linux — large files") },
        { id: "exfat", name: "exfat", desc: Tr.t("USB / SD — large files, works everywhere") },
    ]
}