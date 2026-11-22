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

    // ---- SMART health -----------------------------------------------------------
    function checkHealth(device) {
        run(["health", device]);
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

    // ---- internal: one write at a time ------------------------------------------
    property var _queue: []
    function run(args) { _queue = _queue.concat([args]); next(); }
    function next() {
        if (writer.running || _queue.length === 0)
            return;
        busy = true;
        writer.command = ["pkexec", root.tool].concat(_queue[0]);
        _queue = _queue.slice(1);
        writer.running = true;
    }

    // ---- listing ----------------------------------------------------------------
    Process {
        id: lister
        command: ["lsblk", "-J", "-p", "-o", "NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,LABEL,MODEL,RM,HOTPLUG,RO"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.disks = (data.blockdevices || []).map(d => ({
                        name: d.name || "",
                        path: d.path || ("/dev/" + d.name),
                        model: d.model || "",
                        size: root.humanSize(d.size || ""),
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
        stdout: StdioCollector {
            onStreamFinished: {
                // health check returns JSON
                if (text.trim().startsWith("{")) {
                    try {
                        const h = JSON.parse(text);
                        const nh = Object.assign({}, root.health);
                        // find the device this is for
                        const dev = _queue.length > 0 ? _queue[0][1] : "";
                        if (dev) nh[dev] = h;
                        root.health = nh;
                    } catch (e) {}
                }
            }
        }
        onExited: code => {
            root.busy = false;
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