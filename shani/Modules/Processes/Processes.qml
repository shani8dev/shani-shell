// The System Monitor: the heaviest processes, what is using the machine,
// and a way to end it (SIGTERM, so the program can save and close). System
// numbers come from SysStats / Gpu / TopProcesses, all throttled background
// Processes (2s) — the UI thread never blocks on /proc or nvidia-smi.
//
// Process list is shown as a tree: parent processes
// with their children indented beneath, so you can see what spawned what
// and end a whole family at once.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "System Monitor"
    visible: Ui.processes
    onGone: Ui.processes = false
    margins: 0
    implicitWidth: Theme.px(520)
    implicitHeight: Theme.px(720)
    property bool _watching: false
    onVisibleChanged: { if (visible && !_watching) { TopProcesses.requestWatch(); _watching = true; } else if (!visible && _watching) { TopProcesses.releaseWatch(); _watching = false; } }
    // made when opened and gone when closed (shell.qml's LazyLoader)
    Component.onCompleted: { if (visible) { TopProcesses.requestWatch(); _watching = true; } treeList = buildTree(); }
    Component.onDestruction: if (_watching) TopProcesses.releaseWatch()

    // ---- build a flat tree list with indent levels -------------------------
    // root processes (ppid <= 1 or ppid not among listed pids) are top-level;
    // children are indented under their parent
    property var treeList: []
    property string procQuery: ""
    property string endSignal: "TERM"
    // end confirmation lives in a per-row ConfirmButton keyed by pid. The
    // delegate records the pid at arm time, so a 2s refresh or a sort that
    // recycles the row cannot retarget the second tap to a different process.

    // ---- click-to-sort (htop style): a header tap picks a key, tapping it
    // again flips the direction. The tree keeps parents above their children;
    // only siblings at the same indent are compared.
    property string sortKey: "cpu"
    property bool sortDesc: true
    property bool sortApplied: false
    readonly property var sortKeys: ["name", "pid", "cpu", "mem", "disk"]
    function loadSort() {
        if (win.sortApplied) return;
        win.sortApplied = true;
        const k = sortPrefs.key;
        if (win.sortKeys.indexOf(k) >= 0) {
            win.sortKey = k;
            win.sortDesc = sortPrefs.desc !== false;
            win.treeList = win.buildTree();
        }
    }
    function saveSort() {
        // a late file load must not undo a click made while it was still reading
        win.sortApplied = true;
        sortPrefs.key = win.sortKey;
        sortPrefs.desc = win.sortDesc;
        Quickshell.execDetached(["mkdir", "-p", win.prefsDir]);
        sortPrefsFile.writeAdapter();
    }
    function setSort(key) {
        if (win.sortKey === key) win.sortDesc = !win.sortDesc;
        else { win.sortKey = key; win.sortDesc = key !== "pid" && key !== "name"; }
        win.treeList = win.buildTree();
        win.saveSort();
    }
    // Settings.data's JsonAdapter only accepts keys declared in
    // Common/Settings.qml, which this window does not own: the choice lives in
    // a sibling file in the same config dir, as Services/Osk.qml does.
    readonly property string prefsDir: {
        const p = Settings.path;
        return p.substring(0, p.lastIndexOf("/"));
    }
    FileView {
        id: sortPrefsFile
        path: win.prefsDir + "/processes-sort.json"
        atomicWrites: true
        printErrors: false
        onLoaded: Qt.callLater(function() { win.loadSort(); })  // let the adapter settle first
        onLoadFailed: win.sortApplied = true   // no file yet: keep the defaults
        JsonAdapter {
            id: sortPrefs
            property string key: "cpu"
            property bool desc: true
        }
    }
    function metric(p, key) {
        if (key === "pid") return p.pid;
        if (key === "name") return String(p.name || "");
        if (key === "mem") return p.mem;
        if (key === "disk") return TopProcesses.diskIo[p.pid] || 0;
        return p.cpu;
    }
    function sortRows(rows) {
        const key = win.sortKey, dir = win.sortDesc ? -1 : 1;
        return rows.slice().sort((a, b) => {
            const x = win.metric(a, key), y = win.metric(b, key);
            if (typeof x === "string" || typeof y === "string")
                return String(x).localeCompare(String(y)) * dir;
            return (x - y) * dir;
        });
    }

    // ---- Users view: the same samples added up per user ------------------------
    property bool byUser: false
    readonly property var userList: {
        const m = {};
        for (const p of TopProcesses.list) {
            const u = p.user || "?";
            const r = m[u] || (m[u] = { user: u, count: 0, cpu: 0, mem: 0, disk: 0 });
            r.count += 1; r.cpu += p.cpu; r.mem += p.mem;
            r.disk += TopProcesses.diskIo[p.pid] || 0;
        }
        return Object.values(m).sort((a, b) => b.cpu - a.cpu);
    }
    readonly property var shownList: win.procQuery
        ? win.treeList
            .filter(x => String(x.p.name || "").toLowerCase().includes(win.procQuery.toLowerCase()))
            // a search is a flat hit list: keeping a child's tree indent when
            // its parent did not match leaves an indented orphan in the result
            .map(x => ({ p: x.p, indent: 0 }))
        : win.treeList
    function buildTree() {
        const procs = TopProcesses.list;
        const byPid = {};
        for (const p of procs) byPid[p.pid] = p;
        const kids = {};
        for (const p of procs) {
            const pp = p.ppid;
            if (!kids[pp]) kids[pp] = [];
            kids[pp].push(p);
        }
        const out = [];
        function walk(parentIndent, ppid) {
            const children = kids[ppid] || [];
            const ordered = win.sortRows(children);
            for (const p of ordered) {
                out.push({ p: p, indent: parentIndent });
                walk(parentIndent + 1, p.pid);
            }
        }
        // roots: ppid <= 1 (init/systemd) or ppid not in our list
        // a root is any process whose parent is not in the list. `p.ppid <= 1`
        // also matched every child of PID 1, listing them once flat and once
        // under systemd; byPid has no 0 entry, so PID 1 itself stays a root.
        const roots = win.sortRows(procs.filter(p => !byPid[p.ppid]));
        for (const p of roots) {
            out.push({ p: p, indent: 0 });
            walk(1, p.pid);
        }
        return out;
    }
    Connections {
        target: TopProcesses
        function onListChanged() { treeList = buildTree(); }
        function onDiskIoChanged() { if (win.sortKey === "disk") treeList = buildTree(); }
    }
    property int detailPid: -1
    function openDetails(pid) { win.detailPid = pid; TopProcesses.showDetails(pid); }

    // total bytes read + written, as a short number for the Disk column
    function diskText(b) {
        if (!b) return "0";
        if (b < 1024) return b + " B";
        if (b < 1048576) return (b / 1024).toFixed(0) + " KB";
        if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB";
        return (b / 1073741824).toFixed(1) + " GB";
    }
    // the same >0.9 amber threshold the bar's chips and the desktop widget use
    function capacityTint(used, total) {
        return total > 0 && used / total > 0.9 ? Theme.amber : Theme.accent;
    }
    // System pressure meters: 0 normal, 1 busy, 2 saturated. Load is per core,
    // swap is a share of its total, PSI is the kernel's stall percentage.
    function loadLevel(load, cores) {
        const r = cores > 0 ? load / cores : load;
        return r >= 1 ? 2 : r >= 0.7 ? 1 : 0;
    }
    function swapLevel(used, total) {
        if (!(total > 0)) return 0;
        const r = used / total;
        return r >= 0.9 ? 2 : r >= 0.7 ? 1 : 0;
    }
    function psiLevel(value) {
        return value >= 40 ? 2 : value >= 20 ? 1 : 0;
    }
    function pressureColor(level) {
        return level >= 2 ? Theme.red : level >= 1 ? Theme.amber : Theme.accent;
    }

    // ---- System overview ---------------------------------------------------
    // One entry point to the details that live in other surfaces. Every number
    // below is a value SysStats already samples, and every button opens an
    // existing shell surface through the same API the launcher uses: no second
    // poller, no second reader and no new window of our own.
    readonly property var overviewLinks: [
            { label: Tr.t("Disks"), action: "disks" },
            { label: Tr.t("Disk usage"), action: "diskUsage" },
            { label: Tr.t("Battery & wellbeing"), action: "power" },
            { label: Tr.t("About this computer"), action: "about" }
        ]
    function openOverviewLink(action) {
        switch (action) {
        case "disks":
            Ui.closeAll(); Ui.disks = true; Disks.refresh();
            break;
        case "diskUsage":
            DiskUsage.open();
            break;
        case "power":
            Ui.openSettings("power");
            break;
        case "about":
            Ui.openSettings("about");
            break;
        }
    }

    Item {
        id: card
        anchors.fill: parent
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Theme.px(10)
            spacing: Theme.px(6)
            SectionTitle {
                Layout.fillWidth: true
                Layout.margins: Theme.px(4)
                text: Tr.t("System overview")
                Accessible.name: Tr.t("System info")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [
                        { label: Tr.t("CPU"), value: Math.round(SysStats.cpu * 100) + "%", tint: Theme.accent },
                        { label: Tr.t("Memory"), value: Math.round(SysStats.mem * 100) + "%", tint: Theme.blue },
                        { label: Tr.t("Disk I/O"), value: SysStats.rate(SysStats.diskReadRate + SysStats.diskWriteRate), tint: Theme.blue },
                        { label: Tr.t("Network"), value: SysStats.rate(SysStats.rxRate + SysStats.txRate), tint: Theme.amber },
                        { label: Tr.t("CPU temperature"), value: SysStats.temp > 0 ? Math.round(SysStats.temp) + "°" : "—", tint: Theme.accent },
                        { label: Tr.t("Load"), value: SysStats.load1.toFixed(2), tint: Theme.text }
                    ]
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Theme.px(1)
                        Text {
                            text: modelData.label
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(9) * Theme.fontScale
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: modelData.value
                            color: modelData.tint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                            font.features: { "tnum": 1 }
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Accessible.name: modelData.label + " " + text
                        }
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: win.overviewLinks
                    Button {
                        required property var modelData
                        kind: "outline"
                        text: modelData.label
                        Accessible.name: Tr.t("Open %1", modelData.label)
                        onClicked: win.openOverviewLink(modelData.action)
                    }
                }
            }
            // the last minute, from the samples SysStats already takes while
            // this window is open — no extra poller, and nothing draws at idle
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(2)
                    Text { text: Tr.t("CPU"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    Sparkline { Layout.fillWidth: true; values: SysStats.cpuHistory; color: Theme.accent }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(2)
                    Text { text: Tr.t("Memory"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    Sparkline { Layout.fillWidth: true; values: SysStats.memHistory; color: Theme.blue }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(2)
                    Text { text: Tr.t("Network"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    Sparkline { Layout.fillWidth: true; values: SysStats.netHistory.map(x => x.rx + x.tx); color: Theme.amber }
                }
                // whole-disk rates from the same 3 s sample, no extra poller
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(2)
                    Text { text: Tr.t("Disk I/O"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    Text {
                        text: "↓ " + SysStats.rate(SysStats.diskReadRate)
                        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                        font.features: { "tnum": 1 }; elide: Text.ElideRight; Layout.fillWidth: true
                    }
                    Text {
                        text: "↑ " + SysStats.rate(SysStats.diskWriteRate)
                        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                        font.features: { "tnum": 1 }; elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }
            }
            // --- system ---------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: sysCol.implicitHeight + 16
                radius: Theme.px(10)
                color: Theme.surface1
                border.width: 1
                border.color: Theme.stroke
                Column {
                    id: sysCol
                    anchors.fill: parent
                    anchors.margins: Theme.px(10)
                    spacing: Theme.px(3)
                    Text {
                        width: parent.width
                        text: Tr.t("System — up %1 · threads %2 · %3 · handles %4").arg(SysStats.uptimeStr).arg(SysStats.threads).arg(SysStats.clockSpeed || "clock unknown").arg(SysStats.fileHandles)
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        text: SysStats.temp > 0 ? ("cpu " + Math.round(SysStats.temp) + "° · ") : ""
                            + SysStats.memTotalGb.toFixed(1) + " GB · "
                            + (Gpu.stats ? (Gpu.stats.name + " " + Math.round(Gpu.stats.util) + "% · " + Math.round(Gpu.stats.memUsed / Math.max(1, Gpu.stats.memTotal) * 100) + "% mem") : "no GPU")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                        wrapMode: Text.Wrap
                    }
                    // root / home capacity from df, once a minute; home is
                    // omitted when it shares root's filesystem (same numbers)
                    Repeater {
                        model: [
                            { label: Tr.t("Root"), used: SysStats.rootUsed, total: SysStats.rootTotal,
                              show: SysStats.rootTotal > 0 },
                            { label: Tr.t("Home"), used: SysStats.homeUsed, total: SysStats.homeTotal,
                              show: SysStats.homeTotal > 0 && !SysStats.homeSameDevice }
                        ]
                        Row {
                            required property var modelData
                            visible: modelData.show
                            spacing: Theme.px(6)
                            Text {
                                text: modelData.label
                                color: Theme.dim
                                width: Theme.px(34)
                                font.family: Theme.font
                                font.pixelSize: Theme.px(10) * Theme.fontScale
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                width: Theme.px(120); height: Theme.px(6); radius: 3
                                color: Theme.pressed
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    width: parent.width * Math.min(1, Math.max(0,
                                        modelData.total > 0 ? modelData.used / modelData.total : 0))
                                    height: parent.height
                                    radius: parent.radius
                                    color: win.capacityTint(modelData.used, modelData.total)
                                }
                            }
                            Text {
                                text: Math.round((modelData.total > 0 ? modelData.used / modelData.total : 0) * 100) + "%"
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(9) * Theme.fontScale
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    // per-core bars
                    Row {
                        spacing: Theme.px(4)
                        visible: SysStats.perCore.length > 0
                        Repeater {
                            model: SysStats.perCore
                            Rectangle {
                                required property real modelData
                                width: Theme.px(30)
                                height: Theme.px(8)
                                radius: Theme.px(4)
                                color: Theme.pressed
                                Rectangle {
                                    width: parent.width * Math.min(1, Math.max(0, parent.modelData))
                                    height: parent.height
                                    radius: Theme.px(4)
                                    color: Theme.accent
                                }
                            }
                        }
                    }
                    // per-interface network
                    Repeater {
                        model: SysStats.nets
                        Text {
                            required property var modelData
                            width: parent.width
                            text: "↓ " + SysStats.rate(modelData.rx) + "  ↑ " + SysStats.rate(modelData.tx) + "  (" + modelData.name + ")"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            font.features: { "tnum": 1 }
                        }
                    }
                    Text {
                        width: parent.width
                        text: Tr.t("Per-process network: needs nethogs (root) — %1").arg(TopProcesses.nethogsAvailable ? "available" : "not installed, omitted")
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.px(9) * Theme.fontScale
                        wrapMode: Text.Wrap
                    }
                }
            }
            // ---- System pressure -------------------------------------------------
            // One compact row of the values SysStats already samples: load per
            // core, swap against its total, the kernel's three PSI stalls. No
            // second poller and no opaque card — thin bars on the surface.
            SectionTitle {
                Layout.fillWidth: true
                Layout.margins: Theme.px(4)
                text: Tr.t("System pressure")
                Accessible.name: Tr.t("System pressure meters")
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.px(4)
                spacing: Theme.px(8)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(2)
                    Text {
                        text: Tr.t("Load 1/5/15") + "  " + SysStats.load1.toFixed(2) + " / " + SysStats.load5.toFixed(2) + " / " + SysStats.load15.toFixed(2)
                        color: win.pressureColor(win.loadLevel(SysStats.load1, SysStats.perCore.length))
                        font.family: Theme.font
                        font.pixelSize: Theme.px(9) * Theme.fontScale
                        font.features: { "tnum": 1 }
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Accessible.name: text
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(5)
                        radius: Theme.px(3)
                        color: Theme.pressed
                        Rectangle {
                            width: parent.width * Math.min(1, Math.max(0, SysStats.load1 / Math.max(1, SysStats.perCore.length)))
                            height: parent.height
                            radius: parent.radius
                            color: win.pressureColor(win.loadLevel(SysStats.load1, SysStats.perCore.length))
                        }
                        Accessible.name: Tr.t("Load average") + " " + SysStats.load1.toFixed(2)
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(2)
                    Text {
                        text: Tr.t("Swap") + "  " + Math.round(SysStats.swapUsedMb) + " / " + Math.round(SysStats.swapTotalMb) + " MB"
                        color: win.pressureColor(win.swapLevel(SysStats.swapUsedMb, SysStats.swapTotalMb))
                        font.family: Theme.font
                        font.pixelSize: Theme.px(9) * Theme.fontScale
                        font.features: { "tnum": 1 }
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Accessible.name: text
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(5)
                        radius: Theme.px(3)
                        color: Theme.pressed
                        Rectangle {
                            width: parent.width * Math.min(1, Math.max(0, SysStats.swapTotalMb > 0 ? SysStats.swapUsedMb / SysStats.swapTotalMb : 0))
                            height: parent.height
                            radius: parent.radius
                            color: win.pressureColor(win.swapLevel(SysStats.swapUsedMb, SysStats.swapTotalMb))
                        }
                        Accessible.name: Tr.t("Swap") + " " + Math.round(SysStats.swapUsedMb) + " / " + Math.round(SysStats.swapTotalMb) + " MB"
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(2)
                    Text {
                        text: Tr.t("PSI stalls") + "  " + SysStats.psiCpu.toFixed(1) + " / " + SysStats.psiMem.toFixed(1) + " / " + SysStats.psiIo.toFixed(1) + " %"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(9) * Theme.fontScale
                        font.features: { "tnum": 1 }
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Accessible.name: text
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(3)
                        Repeater {
                            model: [
                                { label: Tr.t("CPU"), value: SysStats.psiCpu },
                                { label: Tr.t("Memory"), value: SysStats.psiMem },
                                { label: Tr.t("I/O"), value: SysStats.psiIo }
                            ]
                            Rectangle {
                                id: psiMeter
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.px(5)
                                radius: Theme.px(3)
                                color: Theme.pressed
                                Rectangle {
                                    width: psiMeter.width * Math.min(1, Math.max(0, psiMeter.modelData.value / 100))
                                    height: psiMeter.height
                                    radius: psiMeter.radius
                                    color: win.pressureColor(win.psiLevel(psiMeter.modelData.value))
                                }
                                Accessible.name: Tr.t("%1 PSI %2%", psiMeter.modelData.label, psiMeter.modelData.value.toFixed(1))
                            }
                        }
                    }
                }
            }
            // ---- Hardware sensors ------------------------------------------------
            // One row per readable hwmon input. The bridge is only polled while
            // this window is open (Sensors.wanted), and an empty tree is not a
            // failure: say so instead of drawing a blank section. The list
            // scrolls so a machine with 20 inputs cannot push the tree away.
            function sensorSeverity(level) {
                return level >= 2 ? Tr.t("Critical") : level >= 1 ? Tr.t("Near maximum") : Tr.t("Normal");
            }
            SectionTitle {
                Layout.fillWidth: true
                Layout.margins: Theme.px(4)
                text: Tr.t("Sensors")
                Accessible.name: Tr.t("Hardware sensors")
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.px(4)
                spacing: Theme.px(3)
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Sensors.sensors.length > 0 || Sensors.error !== "" || (!Sensors.answered && Sensors.loading) ? Theme.px(120) : Theme.px(18)
                    contentWidth: width
                    contentHeight: sensorRows.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: sensorRows
                        width: parent.width
                        spacing: Theme.px(3)
                        Repeater {
                            model: Sensors.sensors
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.px(8)
                                Text {
                                    text: modelData.label || modelData.name || Tr.t("Sensor")
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(11) * Theme.fontScale
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Accessible.name: Tr.t("Sensor %1", text)
                                }
                                Rectangle {
                                    Layout.preferredWidth: Theme.px(48)
                                    Layout.preferredHeight: Theme.px(5)
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: Theme.px(3)
                                    color: Theme.pressed
                                    property int sev: modelData.level || 0
                                    Rectangle {
                                        width: parent.width * (parent.sev + 1) / 3
                                        height: parent.height
                                        radius: parent.radius
                                        color: parent.sev >= 2 ? Theme.red : parent.sev >= 1 ? Theme.amber : Theme.blue
                                    }
                                    Accessible.name: Tr.t("Severity: %1", col.sensorSeverity(modelData.level || 0))
                                }
                                Text {
                                    text: (typeof modelData.value === "number" ? modelData.value : 0) + " " + (modelData.unit || "")
                                    color: modelData.level >= 2 ? Theme.red : modelData.level >= 1 ? Theme.amber : Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(11) * Theme.fontScale
                                    font.features: { "tnum": 1 }
                                    Layout.rightMargin: Theme.px(2)
                                    Accessible.name: Tr.t("%1 %2, %3", modelData.label || modelData.name || "", text, col.sensorSeverity(modelData.level || 0))
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: Sensors.answered && Sensors.error === "" && Sensors.sensors.length === 0
                            text: Tr.t("No hardware sensors found.")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: !Sensors.loading && Sensors.error !== ""
                            text: Sensors.error
                            color: Theme.amber
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            wrapMode: Text.Wrap
                        }
                        BusyNote {
                            Layout.fillWidth: true
                            visible: Sensors.loading && !Sensors.answered && Sensors.sensors.length === 0
                            note: Tr.t("Reading sensors…")
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: Sensors.sensors.length > 0
                    text: Tr.t("Temperatures in °C · voltages in V · fans in RPM · amber at maximum, red at critical")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.px(9) * Theme.fontScale
                    wrapMode: Text.Wrap
                }
            }
            // ---- Network usage --------------------------------------------------
            // vnStat's own day/month history, read once when this window opens
            // (NetUsage.refresh()). The live rates above are left as they were.
            ColumnLayout {
                id: netUsageSection
                Layout.fillWidth: true
                spacing: Theme.px(4)
                readonly property real dayMax: {
                    let m = 0;
                    for (const d of NetUsage.days) m = Math.max(m, d.total);
                    return m;
                }
                Connections { target: win; function onVisibleChanged() { if (win.visible) NetUsage.refresh(); } }
                // the LazyLoader creates this section when the monitor opens:
                // ask once here; onVisibleChanged covers a later close/reopen
                Component.onCompleted: NetUsage.refresh()

                SectionTitle {
                    Layout.fillWidth: true
                    Layout.margins: Theme.px(4)
                    text: Tr.t("Network usage")
                    Accessible.name: Tr.t("Network usage from vnStat")
                }
                Text {
                    Layout.fillWidth: true
                    visible: NetUsage.available
                    text: Tr.t("This month %1 · last 7 days %2").arg(Theme.bytes(NetUsage.monthTotal)).arg(Theme.bytes(NetUsage.weekTotal))
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    font.features: { "tnum": 1 }
                    Accessible.name: text
                }
                Text {
                    Layout.fillWidth: true
                    visible: !NetUsage.available
                    text: Tr.t("No vnStat data yet — network usage appears once vnStat has a day of history.")
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: NetUsage.interfaces.length > 1
                    spacing: Theme.px(6)
                    Text { text: Tr.t("Interface:"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    Repeater {
                        model: NetUsage.interfaces
                        Choice {
                            required property var modelData
                            text: modelData
                            selected: NetUsage.selected === modelData
                            onClicked: NetUsage.selectInterface(modelData)
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: NetUsage.available && NetUsage.days.length > 0
                    spacing: Theme.px(4)
                    Repeater {
                        model: NetUsage.days
                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.px(46)
                                radius: Theme.px(3)
                                color: Theme.pressed
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: parent.height * (netUsageSection.dayMax > 0 ? Math.max(0.03, modelData.total / netUsageSection.dayMax) : 0)
                                    radius: parent.radius
                                    color: Theme.accent
                                    Accessible.name: Tr.t("%1: %2", modelData.date, Theme.bytes(modelData.total))
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.date.slice(5)
                                color: Theme.dim
                                horizontalAlignment: Text.AlignHCenter
                                font.family: Theme.font
                                font.pixelSize: Theme.px(9) * Theme.fontScale
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: Theme.bytes(modelData.total)
                                color: Theme.faint
                                horizontalAlignment: Text.AlignHCenter
                                font.family: Theme.font
                                font.pixelSize: Theme.px(9) * Theme.fontScale
                                font.features: { "tnum": 1 }
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
            SectionTitle {
                Layout.fillWidth: true
                Layout.margins: Theme.px(4)
                text: Tr.t("Process tree")
            }
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Find a process…")
                text: win.procQuery
                onTextChanged: win.procQuery = text
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text { text: Tr.t("View:"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; height: Math.max(Theme.px(24), Theme.touchTarget); verticalAlignment: Text.AlignVCenter }
                Choice { text: Tr.t("Processes"); selected: !win.byUser; onClicked: win.byUser = false }
                Choice { text: Tr.t("Users"); selected: win.byUser; onClicked: win.byUser = true }
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text { text: Tr.t("End with signal:"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; height: Math.max(Theme.px(24), Theme.touchTarget); verticalAlignment: Text.AlignVCenter }
                Repeater {
                    model: ["TERM", "KILL", "INT", "HUP", "STOP", "CONT"]
                    Choice {
                        required property var modelData
                        text: modelData
                        selected: win.endSignal === modelData
                        onClicked: win.endSignal = modelData
                    }
                }
            }
            // clickable column headers: tap to sort, tap again to reverse
            RowLayout {
                visible: !win.byUser
                Layout.fillWidth: true
                Layout.leftMargin: win.compact ? 0 : Theme.px(20)
                spacing: Theme.px(6)
                Repeater {
                    model: [
                        { key: "name", label: Tr.t("Name"), width: -1 },
                        { key: "pid", label: "PID", width: win.compact ? 42 : 60 },
                        { key: "cpu", label: "CPU", width: win.compact ? 46 : 70 },
                        { key: "mem", label: Tr.t("Memory"), width: win.compact ? 46 : 70 },
                        { key: "disk", label: Tr.t("Disk"), width: win.compact ? 44 : 64 }
                    ]
                    Text {
                        required property var modelData
                        text: modelData.label + (win.sortKey === modelData.key ? (win.sortDesc ? " ↓" : " ↑") : "")
                        color: win.sortKey === modelData.key ? Theme.accent : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                        font.weight: win.sortKey === modelData.key ? Font.DemiBold : Font.Normal
                        Layout.fillWidth: modelData.width < 0
                        Layout.preferredWidth: modelData.width < 0 ? 0 : modelData.width
                        Accessible.role: Accessible.Button
                        Accessible.name: Tr.t("Sort by %1", modelData.label)
                        Accessible.onPressAction: win.setSort(modelData.key)
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.setSort(modelData.key) }
                        // keys and a controller: Enter / Space sorts by this column, once
                        KeyFocus { name: Tr.t("Sort by %1", modelData.label); onActivated: win.setSort(modelData.key) }
                    }
                }
            }
            // the processes, a row each, in a list that scrolls: as a Repeater of
            // heightless Items every row was drawn on top of the one before
            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: procList
                visible: !win.byUser
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Theme.px(160)
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: win.shownList
                delegate: RowLayout {
                    id: procRow
                    required property var modelData
                    readonly property int indent: modelData.indent
                    readonly property var p: modelData.p
                    width: procList.width
                    height: Math.max(Theme.px(36), Theme.touchTarget)
                    spacing: Theme.px(6)
                    Item { implicitWidth: Math.min(procRow.indent, win.compact ? 2 : 99) * 14; implicitHeight: 1 }
                    Text {
                        text: procRow.p.name
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                        color: procRow.indent === 0 ? Theme.text : Theme.dim
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: procRow.p.pid
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                        font.features: { "tnum": 1 }
                        color: Theme.faint
                    }
                    Text {
                        text: procRow.p.cpu.toFixed(0) + " %  ·  " + procRow.p.mem.toFixed(1) + " %"
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                        font.features: { "tnum": 1 }
                        color: procRow.p.cpu >= 50 ? Theme.danger : Theme.dim
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: win.compact ? Theme.px(52) : Theme.px(96)
                    }
                    Text {
                        text: win.diskText(TopProcesses.diskIo[procRow.p.pid] || 0)
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                        font.features: { "tnum": 1 }
                        color: Theme.faint
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: win.compact ? Theme.px(44) : Theme.px(64)
                        Accessible.name: Tr.t("Disk I/O") + " " + text
                        Hint { text: Tr.t("Total read + write for this process, from /proc/<pid>/io") }
                    }
                    Text {
                        // cpu is already a percentage of one core (it includes the
                        // core count), so ~6.5 W per fully loaded core = cpu * 0.065
                        visible: !win.compact
                        text: Math.round(procRow.p.cpu * 0.065) + " W"
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                        font.features: { "tnum": 1 }
                        color: Theme.faint
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: Theme.px(44)
                        Accessible.name: Tr.t("Energy estimate") + " " + text
                        Hint { text: Tr.t("Estimate from CPU use — not measured") }
                    }
                    Button {
                        text: Tr.t("Details")
                        flat: true
                        Accessible.name: Tr.t("Details for") + " " + procRow.p.name
                        onClicked: win.openDetails(procRow.p.pid)
                    }
                    ConfirmButton {
                        id: endConfirm
                        // a recycled delegate changes `value`; only the pid armed
                        // by the first tap may be ended by the second
                        property int armedPid: -1
                        onArmedChanged: if (armed) armedPid = procRow.p.pid
                        implicitWidth: Math.max(Theme.touchTarget, armedText.length * 8 + 28)
                        implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                        value: String(procRow.p.pid)
                        text: Tr.t("End")
                        armedText: Tr.t("Tap again")
                        kind: endConfirm.armed ? "danger" : "plain"
                        interval: 3000
                        // ending the compositor or the shell takes the session down
                        enabled: !/^(niri|qs|quickshell|systemd|init)$/.test(procRow.p.name)
                        Accessible.name: Tr.t("End") + " " + procRow.p.name
                        onConfirmed: {
                            if (endConfirm.armedPid === procRow.p.pid) TopProcesses.end(procRow.p.pid, win.endSignal);
                        }
                        Connections {
                            target: TopProcesses
                            // a refresh that drops the armed process cancels the confirm
                            function onListChanged() {
                                if (endConfirm.armed && !TopProcesses.list.some(p => p.pid === endConfirm.armedPid)) endConfirm.disarm();
                            }
                        }
                        Connections {
                            target: win
                            function onVisibleChanged() { if (!win.visible) endConfirm.disarm() }
                        }
                    }
                }
            }
            Text {
                visible: !win.byUser && win.procQuery !== "" && win.shownList.length === 0
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("No process matches \"%1\"", win.procQuery)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            // Users view: per-user totals from the same samples, read-only
            ListView {
                id: userList
                visible: win.byUser
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Theme.px(160)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: win.userList
                delegate: RowLayout {
                    required property var modelData
                    width: userList.width
                    spacing: Theme.px(8)
                    Text { text: modelData.user; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: modelData.count + " " + Tr.t("processes"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale; Layout.preferredWidth: Theme.px(90) }
                    Text { text: modelData.cpu.toFixed(0) + "% CPU"; color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale; Layout.preferredWidth: Theme.px(70) }
                    Text { text: modelData.mem.toFixed(1) + "% mem"; color: Theme.blue; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale; Layout.preferredWidth: Theme.px(70) }
                    Text { text: win.diskText(modelData.disk); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale; Layout.preferredWidth: Theme.px(70) }
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("CPU is % since the last sample (/proc/stat deltas) · updates every 2s")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Energy is estimated from CPU use, not measured · Disk is total read + write from /proc/<pid>/io")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(9) * Theme.fontScale
                wrapMode: Text.Wrap
            }
        }

        // ---- process details + renice ---------------------------------------------
        Dialog {
            id: detailsDialog
            anchors.centerIn: parent
            width: Math.min(win.width * 0.85, Theme.px(460))
            title: Tr.t("Process details · %1", win.detailPid)
            modal: true
            standardButtons: Dialog.Close
            visible: win.detailPid > 0 && TopProcesses.details !== null
            onClosed: { win.detailPid = -1; TopProcesses.details = null; }
            contentItem: ColumnLayout {
                id: detailCol
                spacing: Theme.px(6)
                // a child of a Dialog's contentItem cannot see a property
                // declared on it, so every use below is qualified by the id
                readonly property var det: TopProcesses.details || ({})
                Text { Layout.fillWidth: true; text: detailCol.det.cmdline || Tr.t("(no command line)"); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale; wrapMode: Text.Wrap }
                Text { Layout.fillWidth: true; text: Tr.t("User %1 · state %2 · %3 threads · %4 open files").arg(detailCol.det.user || "?").arg(detailCol.det.state || "?").arg(detailCol.det.threads || 0).arg(detailCol.det.files || 0); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; wrapMode: Text.Wrap }
                Text { Layout.fillWidth: true; text: Tr.t("Environment"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                Text { Layout.fillWidth: true; text: (detailCol.det.env || []).join("\n"); color: Theme.faint; font.family: Theme.mono; font.pixelSize: Theme.px(9) * Theme.fontScale; wrapMode: Text.Wrap; maximumLineCount: 8; elide: Text.ElideRight }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Text { text: Tr.t("Nice value (−20 = first, 19 = last)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    TextField { id: niceField; Layout.preferredWidth: Theme.px(60); placeholder: "-20…19" }
                    Button { text: Tr.t("Apply nice"); enabled: /^-?\d+$/.test(niceField.text); onClicked: { TopProcesses.renice(win.detailPid, parseInt(niceField.text, 10)); niceField.text = ""; } }
                }
            }
        }
    }
}
