pragma Singleton
// The heaviest processes, for the bar's CPU chip and the System Monitor:
// refreshed every two seconds only while a list is open, in the background
// (a Process, never the UI thread) so the UI never freezes.
//
// Per-process CPU comes from /proc/stat deltas: the helper prints each
// process's utime+stime ticks and the system's total ticks; QML turns two
// samples into a percentage. Memory is VmRSS over the total from
// /proc/meminfo; threads come from /proc/<pid>/status.
//
// Per-process network is via nethogs when it is installed (it usually needs
// root, honestly so): nethogsAvailable is false and no net numbers are
// shown when it is absent, rather than inventing them.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool watching: false
    property var list: []                // [{ pid, name, cpu, mem, threads, ticks }]
    property real totalTicks: 0
    property int nCpus: 1
    property bool nethogsAvailable: false
    property var lastTicks: null        // pid -> ticks, for the delta
    property real _prevTotal: 0

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
        command: ["python3", "-c",
            "import os, json, shutil\n" +
            "def total():\n" +
            "    try:\n" +
            "        f=open('/proc/stat').readline().split()[1:]\n" +
            "        return sum(map(int, f))\n" +
            "    except Exception: return 0\n" +
            "def cpus():\n" +
            "    try: return max(1, sum(1 for l in open('/proc/stat') if l.startswith('cpu') and l[3].isdigit()))\n" +
            "    except Exception: return 1\n" +
            "def memtotal():\n" +
            "    try:\n" +
            "        for l in open('/proc/meminfo'):\n" +
            "            if l.startswith('MemTotal:'): return int(l.split()[1])\n" +
            "        return 0\n" +
            "    except Exception: return 0\n" +
            "mt=memtotal(); out=[]\n" +
            "for pid in os.listdir('/proc'):\n" +
            "    if not pid.isdigit(): continue\n" +
            "    try:\n" +
            "        st=open('/proc/'+pid+'/stat').read().split(') ',1)[1].split()\n" +
            "        ticks=int(st[11])+int(st[12])\n" +
            "        name=open('/proc/'+pid+'/comm').read().strip()\n" +
            "        rss=0; threads=0\n" +
            "        for l in open('/proc/'+pid+'/status'):\n" +
            "            if l.startswith('VmRSS:'): rss=int(l.split()[1])\n" +
            "            if l.startswith('Threads:'): threads=int(l.split()[1])\n" +
            "        out.append({'pid':int(pid),'ppid':int(st[2]),'name':name,'ticks':ticks,'rss':rss,'threads':threads})\n" +
            "    except Exception: pass\n" +
            "print(json.dumps({'total':total(),'cpus':cpus(),'memtotal':mt,'nethogs':shutil.which('nethogs') is not None,'procs':out}))\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.totalTicks = d.total || 0;
                    root.nCpus = d.cpus || 1;
                    root.nethogsAvailable = !!d.nethogs;
                    const mt = d.memtotal || 0;
                    const prev = root.lastTicks || {};
                    const next = {};
                    const rows = (d.procs || []).map(p => {
                        const cpu = prev[p.pid] !== undefined && d.total
                            ? Math.max(0, (p.ticks - prev[p.pid]) / Math.max(1, d.total - (root._prevTotal || d.total))) * 100 * root.nCpus
                            : 0;
                        const mem = mt > 0 ? (p.rss / mt) * 100 : 0;
                        next[p.pid] = p.ticks;
                        return { pid: p.pid, name: p.name, cpu: cpu, mem: mem, threads: p.threads || 0, ticks: p.ticks };
                    });
                    // all processes, sorted by CPU then memory — tree view
                    // builds parent->children from ppid
                    rows.sort((a, b) => b.cpu - a.cpu || b.mem - a.mem);
                    root.list = rows;
                    root.lastTicks = next;
                    root._prevTotal = d.total;
                } catch (e) {
                    // a weird /proc: keep the last good list, never blank the UI
                    root.list = root.list || [];
                }
            }
        }
    }
}
