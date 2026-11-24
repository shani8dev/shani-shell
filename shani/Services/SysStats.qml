pragma Singleton
// CPU, memory, network and disk throughput plus the CPU's temperature for the
// bar, read straight from /proc and the kernel's hwmon sensors (no helper
// script), one sample every interval. Also the System Monitor numbers: per-core
// use, per-interface network rates, uptime, threads, clock speed and handles,
// and the root/home capacity from an occasional df.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property real cpu: 0            // 0..1 since the last sample
    property real mem: 0            // 0..1 used
    property real memTotalGb: 0
    property var last: null
    property real rxRate: 0         // bytes/s, summed over real interfaces
    property real txRate: 0
    property real diskReadRate: 0   // bytes/s over whole disks, from /proc/diskstats
    property real diskWriteRate: 0
    // short histories for the System Monitor's sparklines: the sampling timer
    // below already runs while a stats surface is open, so this costs no poller
    property var cpuHistory: []
    property var memHistory: []
    property var netHistory: []     // [{ rx, tx }]
    function push(arr, v) { const a = arr.concat([v]); return a.length > 60 ? a.slice(-60) : a; }
    property real temp: -1          // °C, the CPU package's; -1 without a sensor
    property string tempPath: ""
    property var lastNet: null
    readonly property int interval: 3000
    // --- System Monitor ----------------------------------------------------
    property var perCore: []            // [0..1] per core, since the last sample
    property var lastCores: null
    property var nets: []               // [{ name, rx, tx }] bytes/s per interface
    property var lastNetDev: null
    property real uptimeSec: 0
    property int threads: 0             // total threads (/proc/loadavg)
    property int fileHandles: 0         // allocated handles (/proc/sys/fs/file-nr)
    property string clockSpeed: ""      // from /proc/cpuinfo "cpu MHz" (lscpu's number)
    // pressure & capacity meters for the System Monitor: load averages, swap and
    // the kernel's PSI "some avg10" stall percentages (all from /proc).
    property real load1: 0
    property real load5: 0
    property real load15: 0
    property real swapTotalMb: 0
    property real swapUsedMb: 0
    property real psiCpu: 0              // % of time tasks stalled on CPU (avg10)
    property real psiMem: 0              // % stalled on memory
    property real psiIo: 0               // % stalled on I/O
    // filesystem capacity (bytes, from df -B1 on / and /home), refreshed slowly
    property real rootTotal: 0
    property real rootUsed: 0
    property real homeTotal: 0
    property real homeUsed: 0
    property bool homeSameDevice: true   // /home lives on / — no second bar needed
    readonly property string uptimeStr: {
        const s = Math.floor(root.uptimeSec);
        const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
        return (d ? d + "d " : "") + h + "h " + m + "m";
    }

    function rate(bps) {
        if (bps < 1024)
            return Math.round(bps) + " B/s";
        if (bps < 1024 * 1024)
            return (bps / 1024).toFixed(bps < 10240 ? 1 : 0) + " KB/s";
        return (bps / 1048576).toFixed(1) + " MB/s";
    }

    // whole devices only: partitions repeat their parent's sectors, so adding
    // both would double-count. loop/ram/dm are virtual plumbing, not spindles.
    readonly property string diskDevicePattern: "^(sd[a-z]|nvme[0-9]+n[0-9]+|vd[a-z]|mmcblk[0-9]+)$"
    property var lastDisk: null          // { read, write, t } — for timestamp deltas
    function parseDisk(text) {
        const re = new RegExp(root.diskDevicePattern);
        let read = 0, write = 0;
        for (const line of String(text).split("\n")) {
            const f = line.trim().split(/\s+/);
            if (f.length < 10 || !re.test(f[2]))
                continue;
            read += Number(f[5]) || 0;    // sectors read
            write += Number(f[9]) || 0;   // sectors written
        }
        return { read: read, write: write };
    }
    // df prints one row per distinct filesystem: a duplicate second row means
    // /home is mounted on /, so a second capacity bar would be the same number.
    function parseCapacity(text) {
        const lines = String(text).trim().split("\n").filter(x => x.trim() !== "");
        if (lines.length < 2)
            return;
        const r = lines[1].trim().split(/\s+/);
        const h = lines.length > 2 ? lines[2].trim().split(/\s+/) : r;
        if (r.length < 4 || h.length < 4)
            return;
        root.rootTotal = Number(r[1]) || 0;
        root.rootUsed = Number(r[2]) || 0;
        root.homeTotal = Number(h[1]) || 0;
        root.homeUsed = Number(h[2]) || 0;
        root.homeSameDevice = r[1] === h[1] && r[2] === h[2] && r[3] === h[3];
    }

    // sampled only while something shows it (the bar's chips, the stats widget,
    // the process list, the overview): every sample wakes the shell and redrew
    // six surfaces, 30 ms/s of an idle desktop for numbers nobody was looking at
    readonly property bool wanted: Settings.data.showSysStats || Settings.data.showNetSpeed || Ui.processes || Niri.overviewOpen
        || Array.from(Settings.data.desktopWidgets).indexOf("stats") >= 0
    onWantedChanged: if (!wanted) {
        root.last = null; root.lastNet = null; root.lastCores = null; root.lastNetDev = null;
        // no sample to difference against when a stats surface opens again
        root.lastDisk = null; root.diskReadRate = 0; root.diskWriteRate = 0;
    }
    Timer {
        interval: root.interval
        running: root.wanted
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            meminfo.reload();
            netdev.reload();
            diskStats.reload();
            uptimeView.reload();
            loadavg.reload();
            fileNr.reload();
            cpuinfo.reload();
            psiCpuFile.reload();
            psiMemFile.reload();
            psiIoFile.reload();
            if (root.tempPath)
                tempFile.reload();
        }
    }
    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const lines = text().split("\n");
            const f = lines[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + (f[4] || 0), total = f.reduce((a, b) => a + b, 0);
            if (root.last) {
                const dt = total - root.last.total;
                root.cpu = dt > 0 ? 1 - (idle - root.last.idle) / dt : 0;
                root.cpuHistory = root.push(root.cpuHistory, root.cpu);
            }
            root.last = { idle: idle, total: total };
            // per-core bars: cpuN lines
            const cores = [];
            for (const line of lines) {
                const m = line.match(/^cpu\d+\s+(.*)$/);
                if (!m) continue;
                const n = m[1].trim().split(/\s+/).map(Number);
                const ci = n[3] + (n[4] || 0), ct = n.reduce((a, b) => a + b, 0);
                cores.push({ idle: ci, total: ct });
            }
            if (root.lastCores && root.lastCores.length === cores.length) {
                root.perCore = cores.map((c, i) => {
                    const dt = c.total - root.lastCores[i].total;
                    return dt > 0 ? 1 - (c.idle - root.lastCores[i].idle) / dt : 0;
                });
            }
            root.lastCores = cores;
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
            root.memHistory = root.push(root.memHistory, root.mem);
            root.memTotalGb = total / 1048576;
            const st = Number((t.match(/SwapTotal:\s+(\d+)/) || [0, 0])[1]);
            const sf = Number((t.match(/SwapFree:\s+(\d+)/) || [0, 0])[1]);
            root.swapTotalMb = st / 1024;
            root.swapUsedMb = (st - sf) / 1024;
        }
    }
    FileView {
        id: netdev
        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0, tx = 0;
            const cur = {};
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
                cur[m[1]] = { rx: f[0], tx: f[8] };
            }
            const now = Date.now();
            if (root.lastNet) {
                const dt = (now - root.lastNet.t) / 1000;
                if (dt > 0) {
                    root.rxRate = Math.max(0, (rx - root.lastNet.rx) / dt);
                    root.txRate = Math.max(0, (tx - root.lastNet.tx) / dt);
                    root.netHistory = root.push(root.netHistory, { rx: root.rxRate, tx: root.txRate });
                }
            }
            root.lastNet = { rx: rx, tx: tx, t: now };
            // per-interface rates
            const prev = root.lastNetDev || {};
            const dt2 = root.lastNetDev ? (now - root.lastNetDev.t) / 1000 : 0;
            const list = [];
            for (const name of Object.keys(cur)) {
                const p = prev[name];
                list.push({
                    name: name,
                    rx: p && dt2 > 0 ? Math.max(0, (cur[name].rx - p.rx) / dt2) : 0,
                    tx: p && dt2 > 0 ? Math.max(0, (cur[name].tx - p.tx) / dt2) : 0
                });
            }
            list.sort((a, b) => b.rx + b.tx - a.rx - a.tx);
            root.nets = list;
            root.lastNetDev = { t: now };
            for (const name of Object.keys(cur)) root.lastNetDev[name] = cur[name];
        }
    }
    FileView {
        id: diskStats
        path: "/proc/diskstats"
        onLoaded: {
            const cur = root.parseDisk(text());
            const now = Date.now();
            if (root.lastDisk) {
                const dt = (now - root.lastDisk.t) / 1000;
                if (dt > 0) {
                    root.diskReadRate = Math.max(0, (cur.read - root.lastDisk.read) * 512 / dt);
                    root.diskWriteRate = Math.max(0, (cur.write - root.lastDisk.write) * 512 / dt);
                }
            }
            root.lastDisk = { read: cur.read, write: cur.write, t: now };
        }
    }
    // capacity moves slowly and df forks: once a minute, only while wanted
    Timer {
        id: capacityTick
        interval: 60000
        running: root.wanted
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!dfProc.running) dfProc.running = true
    }
    Process {
        id: dfProc
        command: ["df", "-B1", "--output=target,size,used,avail", "/", "/home"]
        stdout: StdioCollector { onStreamFinished: root.parseCapacity(text) }
    }
    FileView {
        id: uptimeView
        path: "/proc/uptime"
        onLoaded: { const v = parseFloat(String(text()).trim().split(/\s+/)[0]); root.uptimeSec = isNaN(v) ? 0 : v; }
    }
    FileView {
        id: loadavg
        path: "/proc/loadavg"
        onLoaded: {
            // "load1 load5 load15 running/total last_pid" — total is the thread count
            const parts = String(text()).trim().split(/\s+/);
            const total = parts[3] ? Number(String(parts[3]).split("/")[1]) : NaN;
            root.threads = isNaN(total) ? 0 : total;
            root.load1 = Number(parts[0]) || 0;
            root.load5 = Number(parts[1]) || 0;
            root.load15 = Number(parts[2]) || 0;
        }
    }
    // PSI: "some avg10=0.12 avg60=... avg300=... total=..." — avg10 is the
    // percentage of the last 10s that at least one task was stalled.
    function psi(text) { const m = String(text).match(/some\s+avg10=([\d.]+)/); return m ? parseFloat(m[1]) : 0; }
    FileView { id: psiCpuFile; path: "/proc/pressure/cpu"; printErrors: false; onLoaded: { root.psiCpu = psi(text()); } }
    FileView { id: psiMemFile; path: "/proc/pressure/memory"; printErrors: false; onLoaded: { root.psiMem = psi(text()); } }
    FileView { id: psiIoFile; path: "/proc/pressure/io"; printErrors: false; onLoaded: { root.psiIo = psi(text()); } }
    FileView {
        id: fileNr
        path: "/proc/sys/fs/file-nr"
        onLoaded: {
            // "allocated_handles free_handles max_handles"
            const v = parseInt(String(text()).trim().split(/\s+/)[0]);
            root.fileHandles = isNaN(v) ? 0 : v;
        }
    }
    FileView {
        id: cpuinfo
        path: "/proc/cpuinfo"
        onLoaded: {
            // the clock from /proc/cpuinfo "cpu MHz" (what lscpu reads); GHz text
            const m = String(text()).match(/cpu MHz\s*:\s*([\d.]+)/);
            if (m) {
                const ghz = parseFloat(m[1]) / 1000;
                root.clockSpeed = ghz >= 1 ? ghz.toFixed(2) + " GHz" : Math.round(parseFloat(m[1])) + " MHz";
            } else {
                const b = String(text()).match(/model name\s*:\s*(.*)/);
                if (b) root.clockSpeed = b[1].trim();
            }
        }
    }
}
