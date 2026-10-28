pragma Singleton
// Removable drives (USB sticks, SD cards, phones in mass-storage mode) through
// udisks2 — the same authorisation path a file manager uses, so mounting and
// ejecting need no root. Follows `udisksctl monitor`, not a poll.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property var drives: []         // [{ dev, label, size, mount }] — removable partitions
    property bool available: false

    function mount(d) { Quickshell.execDetached(["udisksctl", "mount", "-b", d.dev]); }
    function open(d) { Qt.openUrlExternally("file://" + d.mount); }
    // unmount every partition of the disk, then power it off: safe to pull
    function eject(d) {
        Quickshell.execDetached(["sh", "-c", 'udisksctl unmount -b "$1" 2>/dev/null; udisksctl power-off -b "$2"', "sh", d.dev, d.disk]);
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
                        for (const p of (parts.length ? parts : (disk.fstype ? [disk] : [])))
                            out.push({ dev: p.name, disk: disk.name, label: p.label || p.name.replace("/dev/", ""),
                                       size: p.size, mount: p.mountpoint || "" });
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
