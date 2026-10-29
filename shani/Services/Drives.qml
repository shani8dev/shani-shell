pragma Singleton
// Removable drives (USB sticks, SD cards, phones in mass-storage mode) through
// udisks2 — the same authorisation path a file manager uses, so mounting and
// ejecting need no root. Follows `udisksctl monitor`, not a poll.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property var drives: []         // [{ dev, disk, label, size, mount, luks, locked }] — removable partitions
    property bool available: false

    function mount(d) { Quickshell.execDetached(["udisksctl", "mount", "-b", d.dev]); }
    function open(d) { Qt.openUrlExternally("file://" + d.mount); }
    // unmount every partition of the disk, then power it off: safe to pull
    // an encrypted one is locked again first
    // when the unmount is refused (target is busy), say which programs hold it
    // open — what Windows' "this device is in use" never tells you
    property string busy: ""            // "Videos (mpv), Terminal (bash)" — empty once ejected
    function eject(d) {
        busy = "";
        ejecter.command = ["sh", "-c", 'if [ -n "$4" ] && ! udisksctl unmount -b "$1" >/dev/null 2>&1; then
                fuser -vm "$4" 2>&1 | awk \'/ kernel /{next} NR>1{print $NF}\' | sort -u | tr "\\n" " "; exit 3; fi
            [ -n "$3" ] && udisksctl lock -b "$3" 2>/dev/null; udisksctl power-off -b "$2"', "sh", d.dev, d.disk, d.luks || "", d.mount || ""];
        ejecter.running = true;
    }
    Process {
        id: ejecter
        stdout: StdioCollector { id: ejectOut }
        onExited: code => {
            if (code === 3) {
                const apps = ejectOut.text.trim().split(/\s+/).filter(x => x);
                root.busy = apps.length ? apps.join(", ") : "a program";
                Quickshell.execDetached(["notify-send", "-a", "Drives", "-i", "drive-removable-media", "The drive is in use",
                    "Close " + root.busy + " first, then eject it again."]);
            }
            list.running = true;
        }
    }
    // an encrypted drive (LUKS): the passphrase on stdin, never on a command
    // line; then the unlocked filesystem is mounted
    property string unlockError: ""
    function unlock(d, passphrase) {
        unlockError = "";
        unlocker.command = ["sh", "-c", 'out=$(printf "%s" "$2" | udisksctl unlock -b "$1" --key-file /dev/stdin 2>&1) || { echo "$out" >&2; exit 1; }
            dev=$(echo "$out" | grep -o "/dev/dm-[0-9]*" | head -1); [ -n "$dev" ] && udisksctl mount -b "$dev"', "sh", d.dev, passphrase];
        unlocker.running = true;
    }
    Process {
        id: unlocker
        stderr: StdioCollector { id: unlockErr }
        onExited: code => {
            root.unlockError = code === 0 ? "" : /passphrase|key/i.test(unlockErr.text) ? "Wrong passphrase" : (unlockErr.text.trim().split("\n").pop() || "Could not unlock");
            list.running = true;
        }
    }

    function refresh() { list.running = true; }

    Process {
        id: list
        running: true
        command: ["lsblk", "-J", "-p", "-o", "NAME,LABEL,SIZE,MOUNTPOINT,RM,HOTPLUG,TYPE,FSTYPE"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const out = [];
                    for (const disk of JSON.parse(text).blockdevices || []) {
                        if (!(disk.rm || disk.hotplug) || disk.type !== "disk")
                            continue;
                        const parts = (disk.children || []).filter(p => p.fstype);
                        for (const p of (parts.length ? parts : (disk.fstype ? [disk] : []))) {
                            if (p.fstype === "crypto_LUKS") {
                                // unlocked: its filesystem is a child; locked: the partition itself
                                const open = (p.children || []).find(c => c.fstype);
                                out.push(open ? { dev: open.name, disk: disk.name, label: open.label || p.label || "Encrypted drive", size: p.size,
                                                  mount: open.mountpoint || "", luks: p.name, locked: false }
                                              : { dev: p.name, disk: disk.name, label: p.label || "Encrypted drive", size: p.size,
                                                  mount: "", luks: p.name, locked: true });
                                continue;
                            }
                            out.push({ dev: p.name, disk: disk.name, label: p.label || p.name.replace("/dev/", ""),
                                       size: p.size, mount: p.mountpoint || "", luks: "", locked: false });
                        }
                    }
                    root.drives = out;
                } catch (e) {}
            }
        }
    }
    Process {
        running: true
        command: ["udisksctl", "monitor"]
        stdout: SplitParser { onRead: _ => debounce.restart() }
        onExited: code => root.available = false
        onStarted: root.available = true
    }
    Timer { id: debounce; interval: 600; onTriggered: list.running = true }
}
