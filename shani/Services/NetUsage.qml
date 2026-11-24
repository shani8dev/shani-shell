pragma Singleton
// Network usage from vnStat's own database — the same source Settings > Network
// reads for "today / this month", but with its day and month history so the
// System Monitor can draw bars. Read only: nothing is written to vnStat, no
// second tracker and no idle poller (the monitor calls refresh() when opened).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property bool available: false
    property var interfaces: []          // real interfaces vnStat has data for
    property string selected: ""
    property var byInterface: ({})       // name → { days, months, week, month }
    property var days: []                // [{ date, rx, tx, total }], oldest first, last 7
    property var months: []              // [{ month, rx, tx, total }], oldest first, last 6
    property real weekTotal: 0           // sum of the shown seven days
    property real monthTotal: 0          // vnStat's latest month (bytes)

    function pad2(n) { const s = String(n); return s.length < 2 ? "0" + s : s; }
    function dayKey(d) { return d ? d.year + "-" + pad2(d.month) + "-" + pad2(d.day) : ""; }
    function monthKey(d) { return d ? d.year + "-" + pad2(d.month) : ""; }
    function sum(rows) { return rows.reduce((a, r) => a + r.total, 0); }

    // vnStat --json: [ { interfaces: [ { name, traffic: { day: [], month: [] } } ] } ]
    // Bytes in, bytes out and their sum per row; virtual interfaces are dropped
    // with the same filter Settings > Network uses for its usage line.
    function parse(text) {
        let outer;
        try { outer = JSON.parse(String(text || "")); } catch (e) { return { interfaces: [], byInterface: {} }; }
        const blocks = Array.isArray(outer) ? outer : [outer];
        const by = {};
        for (const block of blocks) {
            for (const itf of (block && block.interfaces) || []) {
                const name = itf && itf.name;
                if (!name || /^(lo|veth|docker|br-|virbr|tun|tap)/.test(name)) continue;
                const traffic = itf.traffic || {};
                const row = (r, label, field) => {
                    const rx = Number(r.rx) || 0, tx = Number(r.tx) || 0;
                    const entry = { rx: rx, tx: tx, total: rx + tx };
                    entry[field] = label;
                    return entry;
                };
                const days = (traffic.day || []).map(d => row(d, dayKey(d.date), "date")).slice(-7);
                const months = (traffic.month || []).map(m => row(m, monthKey(m.date), "month")).slice(-6);
                by[name] = { days: days, months: months, week: sum(days),
                             month: months.length ? months[months.length - 1].total : 0 };
            }
        }
        return { interfaces: Object.keys(by).sort(), byInterface: by };
    }

    function show(name) {
        const cur = root.byInterface[name] || { days: [], months: [], week: 0, month: 0 };
        root.selected = name;
        root.days = cur.days;
        root.months = cur.months;
        root.weekTotal = cur.week;
        root.monthTotal = cur.month;
    }
    function selectInterface(name) { if (root.interfaces.indexOf(name) >= 0) root.show(name); }

    // an absent vnStat is not an error worth a spinner: emit [] and show the
    // honest empty state instead (no interfaces, no bars, nothing to claim)
    Process {
        id: probe
        command: ["sh", "-c", 'command -v vnstat >/dev/null 2>&1 || { echo "[]"; exit 0; }; vnstat --json 2>/dev/null || echo "[]"']
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = root.parse(text);
                root.byInterface = parsed.byInterface;
                root.interfaces = parsed.interfaces;
                root.available = parsed.interfaces.length > 0;
                root.show(parsed.interfaces.indexOf(root.selected) >= 0 ? root.selected : (parsed.interfaces[0] || ""));
            }
        }
    }
    function refresh() { if (!probe.running) probe.running = true; }
}
