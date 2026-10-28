pragma Singleton
// The heaviest processes, for the bar's CPU chip: refreshed every two seconds
// only while the list is open.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool watching: false
    property var list: []                // [{ pid, name, cpu, mem }]

    function end(pid) {
        Quickshell.execDetached(["kill", "-TERM", String(pid)]);
        refresh.restart();
    }
    Timer {
        id: refresh
        interval: 2000
        running: root.watching
        repeat: true
        triggeredOnStart: true
        onTriggered: ps.running = true
    }
    Process {
        id: ps
        command: ["ps", "-eo", "pid=,comm=,pcpu=,pmem=", "--sort=-pcpu"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.list = text.trim().split("\n").slice(0, 6).map(l => {
                    const f = l.trim().split(/\s+/);
                    return { pid: Number(f[0]), name: f[1], cpu: Number(f[2]), mem: Number(f[3]) };
                }).filter(p => p.pid > 0);
            }
        }
    }
}
