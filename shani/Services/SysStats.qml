pragma Singleton
// CPU, memory, network throughput and the CPU's temperature for the bar, read
// straight from /proc and the kernel's hwmon sensors (no helper script), one
// sample every interval.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property real cpu: 0            // 0..1 since the last sample
    property real mem: 0            // 0..1 used
    property var last: null
    property real rxRate: 0         // bytes/s, summed over real interfaces
    property real txRate: 0
    property real temp: -1          // °C, the CPU package's; -1 without a sensor
    property string tempPath: ""
    property var lastNet: null
    readonly property int interval: 3000

    function rate(bps) {
        if (bps < 1024)
            return Math.round(bps) + " B/s";
        if (bps < 1024 * 1024)
            return (bps / 1024).toFixed(bps < 10240 ? 1 : 0) + " KB/s";
        return (bps / 1048576).toFixed(1) + " MB/s";
    }

    Timer {
        interval: root.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            meminfo.reload();
            netdev.reload();
            if (root.tempPath)
                tempFile.reload();
        }
    }
    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + (f[4] || 0), total = f.reduce((a, b) => a + b, 0);
            if (root.last) {
                const dt = total - root.last.total;
                root.cpu = dt > 0 ? 1 - (idle - root.last.idle) / dt : 0;
            }
            root.last = { idle: idle, total: total };
        }
    }
    // the CPU's sensor: coretemp (Intel), k10temp / zenpower (AMD), cpu_thermal (ARM)
    Process {
        running: true
        command: ["sh", "-c", 'for h in /sys/class/hwmon/hwmon*; do case "$(cat "$h/name" 2>/dev/null)" in coretemp|k10temp|zenpower|cpu_thermal|soc_thermal) echo "$h/temp1_input"; exit 0;; esac; done']
        stdout: StdioCollector { onStreamFinished: root.tempPath = text.trim() }
    }
    FileView {
        id: tempFile
        path: root.tempPath
        printErrors: false
        onLoaded: { const v = parseInt(text()); root.temp = isNaN(v) ? -1 : v / 1000; }
    }
    FileView {
        id: meminfo
        path: "/proc/meminfo"
        onLoaded: {
            const t = text();
            const total = Number((t.match(/MemTotal:\s+(\d+)/) || [0, 0])[1]);
            const avail = Number((t.match(/MemAvailable:\s+(\d+)/) || [0, 0])[1]);
            root.mem = total > 0 ? (total - avail) / total : 0;
        }
    }
    FileView {
        id: netdev
        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0, tx = 0;
            for (const line of text().split("\n").slice(2)) {
                const m = line.trim().match(/^([^:]+):\s*(.*)$/);
                if (!m)
                    continue;
                // loopback and virtual plumbing would double-count real traffic
                if (/^(lo|veth|docker|br-|virbr|vnet|tun|tap)/.test(m[1]))
                    continue;
                const f = m[2].split(/\s+/).map(Number);
                rx += f[0];
                tx += f[8];
            }
            const now = Date.now();
            if (root.lastNet) {
                const dt = (now - root.lastNet.t) / 1000;
                if (dt > 0) {
                    root.rxRate = Math.max(0, (rx - root.lastNet.rx) / dt);
                    root.txRate = Math.max(0, (tx - root.lastNet.tx) / dt);
                }
            }
            root.lastNet = { rx: rx, tx: tx, t: now };
        }
    }
}
