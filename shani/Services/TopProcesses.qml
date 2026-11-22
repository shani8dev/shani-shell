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
    // Ref-counted: several surfaces (overview, process list, power section) may
    // need samples at once. Each takes a token; the timer runs while any holds.
    property bool watching: false
    property int _watchers: 0
    function requestWatch() { if (++root._watchers > 0) root.watching = true; }
    function releaseWatch() { if (--root._watchers <= 0) { root._watchers = 0; root.watching = false; } }
    property var list: []                // [{ pid, name, cpu, mem, threads, ticks }]
    property real totalTicks: 0
    property int nCpus: 1
    property var diskIo: ({})            // pid -> total bytes read + written (/proc/<pid>/io)
    property bool nethogsAvailable: false
    property var lastTicks: null        // pid -> ticks, for the delta
    property real _prevTotal: 0

    function end(pid, signal) {
        // Only a fixed set of signals reaches the shell command: the UI never
        // passes an arbitrary string into `kill -<sig>`.
        const sig = ["TERM", "KILL", "INT", "HUP", "STOP", "CONT"].indexOf(signal) >= 0 ? signal : "TERM";
        Quickshell.execDetached(["kill", "-" + sig, String(pid)]);
        refresh.restart();
    }

    // Renice: lower priority is free, asking for a higher one needs the
    // administrator's password (the renice tool reports that itself). Validate
    // the number here so nothing but an integer in -20..19 reaches argv.
    function renice(pid, nice) {
        const n = Number(nice);
        if (!Number.isInteger(n) || n < -20 || n > 19 || !Number.isInteger(pid) || pid <= 0) return false;
        Quickshell.execDetached(["renice", "-n", String(n), "-p", String(pid)]);
        refresh.restart();
        return true;
    }

    // Details for one process: command line, user, state, threads, open files
    // and a short environment, read in the background from /proc. The helper
    // takes the pid as argv, never as text in a shell string.
    property var details: null
    function showDetails(pid) {
        if (!Number.isInteger(pid) || pid <= 0) return;
        detailsProc.command = ["python3", "-c",
            "import os, json, pwd, sys\n" +
            "pid=int(sys.argv[1])\n" +
            "d={'pid':pid,'cmdline':'','user':'','state':'','threads':0,'files':0,'env':[]}\n" +
            "try:\n" +
            "    d['cmdline']=open('/proc/%d/cmdline'%pid,'rb').read().replace(b'\\x00',b' ').decode('utf-8','replace').strip()\n" +
            "    for l in open('/proc/%d/status'%pid):\n" +
            "        if l.startswith('Uid:'):\n" +
            "            try: d['user']=pwd.getpwuid(int(l.split()[1])).pw_name\n" +
            "            except Exception: d['user']=l.split()[1]\n" +
            "        if l.startswith('State:'): d['state']=l.split('(',1)[1].strip() if '(' in l else l.split()[1]\n" +
            "        if l.startswith('Threads:'): d['threads']=int(l.split()[1])\n" +
            "    d['files']=len(os.listdir('/proc/%d/fd'%pid))\n" +
            "    d['env']=[x for x in open('/proc/%d/environ'%pid,'rb').read().replace(b'\\x00',b'\\n').decode('utf-8','replace').split('\\n') if x][:20]\n" +
            "except Exception: pass\n" +
            "print(json.dumps(d))", String(pid)];
        detailsProc.running = true;
    }
    Process {
        id: detailsProc
        stdout: StdioCollector { onStreamFinished: { try { root.details = JSON.parse(text); } catch (e) {} } }
    }
    Timer {
        id: refresh
        interval: 2000
        running: root.watching
        repeat: true
        triggeredOnStart: true
        onTriggered: { ps.running = true; if (!io.running) io.running = true; }
    }
    Process {
        id: ps
        command: ["python3", "-c",
            "import os, json, shutil, pwd\n" +
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
            "        rss=0; threads=0; user=''\n" +
            "        for l in open('/proc/'+pid+'/status'):\n" +
            "            if l.startswith('VmRSS:'): rss=int(l.split()[1])\n" +
            "            if l.startswith('Threads:'): threads=int(l.split()[1])\n" +
            "            if l.startswith('Uid:'):\n" +
            "                try: user=pwd.getpwuid(int(l.split()[1])).pw_name\n" +
            "                except Exception: user=l.split()[1]\n" +
            "        out.append({'pid':int(pid),'ppid':int(st[2]),'name':name,'ticks':ticks,'rss':rss,'threads':threads,'user':user})\n" +
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
                        return { pid: p.pid, ppid: p.ppid, name: p.name, cpu: cpu, mem: mem, threads: p.threads || 0, ticks: p.ticks, user: p.user || "" };
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

    // Per-process disk I/O: /proc/<pid>/io's read_bytes + write_bytes (cumulative
    // since the process started). Cheap to read, done in its own Process so the
    // UI thread never touches /proc; unavailable for a process we cannot read.
    Process {
        id: io
        command: ["python3", "-c",
            "import os, json\n" +
            "out={}\n" +
            "for pid in os.listdir('/proc'):\n" +
            "    if not pid.isdigit(): continue\n" +
            "    try:\n" +
            "        r=w=0\n" +
            "        for l in open('/proc/'+pid+'/io'):\n" +
            "            if l.startswith('read_bytes:'): r=int(l.split()[1])\n" +
            "            if l.startswith('write_bytes:'): w=int(l.split()[1])\n" +
            "        out[int(pid)]=r+w\n" +
            "    except Exception: pass\n" +
            "print(json.dumps(out))\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.diskIo = JSON.parse(text); } catch (e) {}
            }
        }
    }
}
