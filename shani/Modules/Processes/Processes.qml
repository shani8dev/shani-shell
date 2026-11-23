// The System Monitor: the heaviest processes, what is using the machine,
// and a way to end it (SIGTERM, so the program can save and close). System
// numbers come from SysStats / Gpu / TopProcesses, all throttled background
// Processes (2s) — the UI thread never blocks on /proc or nvidia-smi.
//
// Process list is shown as a tree: parent processes
// with their children indented beneath, so you can see what spawned what
// and end a whole family at once.
import Quickshell
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
    // end confirmation is keyed by pid, not by a delegate row: a 2s refresh or
    // a sort can recycle the row and must not retarget or silently drop it
    property int confirmPid: -1
    Timer { id: endConfirmTimer; interval: 3000; onTriggered: win.confirmPid = -1 }
    onConfirmPidChanged: if (confirmPid > 0) endConfirmTimer.restart()

    // ---- click-to-sort (htop style): a header tap picks a key, tapping it
    // again flips the direction. The tree keeps parents above their children;
    // only siblings at the same indent are compared.
    property string sortKey: "cpu"
    property bool sortDesc: true
    function setSort(key) {
        if (win.sortKey === key) win.sortDesc = !win.sortDesc;
        else { win.sortKey = key; win.sortDesc = key !== "pid" && key !== "name"; }
        win.treeList = win.buildTree();
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
        const roots = win.sortRows(procs.filter(p => p.ppid <= 1 || !byPid[p.ppid]));
        for (const p of roots) {
            out.push({ p: p, indent: 0 });
            walk(1, p.pid);
        }
        return out;
    }
    Connections {
        target: TopProcesses
        function onListChanged() {
            treeList = buildTree();
            if (win.confirmPid > 0 && !TopProcesses.list.some(p => p.pid === win.confirmPid)) win.confirmPid = -1;
        }
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
                text: "CPU " + Math.round(SysStats.cpu * 100) + " %  ·  " + Tr.t("memory") + " " + Math.round(SysStats.mem * 100) + "%"
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
                    // load, swap and the kernel's PSI stall meters
                    Text {
                        width: parent.width
                        text: Tr.t("Load %1 / %2 / %3 · swap %4 / %5 MB").arg(SysStats.load1.toFixed(2)).arg(SysStats.load5.toFixed(2)).arg(SysStats.load15.toFixed(2)).arg(Math.round(SysStats.swapUsedMb)).arg(Math.round(SysStats.swapTotalMb))
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                        wrapMode: Text.Wrap
                    }
                    Row {
                        spacing: Theme.px(8)
                        Repeater {
                            model: [
                                { label: Tr.t("CPU"), value: SysStats.psiCpu },
                                { label: Tr.t("Memory"), value: SysStats.psiMem },
                                { label: Tr.t("I/O"), value: SysStats.psiIo }
                            ]
                            Row {
                                spacing: Theme.px(4)
                                Text { text: modelData.label + " PSI " + modelData.value.toFixed(1) + "%"; color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(9) * Theme.fontScale; anchors.verticalCenter: parent.verticalCenter }
                                Rectangle {
                                    width: Theme.px(48); height: Theme.px(6); radius: Theme.px(3); color: Theme.pressed; anchors.verticalCenter: parent.verticalCenter
                                    Rectangle { width: parent.width * Math.min(1, Math.max(0, modelData.value / 100)); height: parent.height; radius: parent.radius; color: Theme.amber }
                                }
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
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text { text: Tr.t("View:"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Choice { text: Tr.t("Processes"); selected: !win.byUser; onClicked: win.byUser = false }
                Choice { text: Tr.t("Users"); selected: win.byUser; onClicked: win.byUser = true }
                Item { Layout.fillWidth: true }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text { text: Tr.t("End with signal:"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
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
                Layout.leftMargin: Theme.px(20)
                spacing: Theme.px(6)
                Repeater {
                    model: [
                        { key: "name", label: Tr.t("Name"), width: -1 },
                        { key: "pid", label: "PID", width: 60 },
                        { key: "cpu", label: "CPU", width: 70 },
                        { key: "mem", label: Tr.t("Memory"), width: 70 },
                        { key: "disk", label: Tr.t("Disk"), width: 64 }
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
                    Item { implicitWidth: procRow.indent * 14; implicitHeight: 1 }
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
                        Layout.preferredWidth: Theme.px(96)
                    }
                    Text {
                        text: win.diskText(TopProcesses.diskIo[procRow.p.pid] || 0)
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                        font.features: { "tnum": 1 }
                        color: Theme.faint
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: Theme.px(64)
                        Accessible.name: Tr.t("Disk I/O") + " " + text
                        Hint { text: Tr.t("Total read + write for this process, from /proc/<pid>/io") }
                    }
                    Text {
                        // cpu is already a percentage of one core (it includes the
                        // core count), so ~6.5 W per fully loaded core = cpu * 0.065
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
                    Button {
                        text: win.confirmPid === procRow.p.pid ? Tr.t("Tap again") : Tr.t("End")
                        kind: win.confirmPid === procRow.p.pid ? "danger" : "plain"
                        flat: true
                        // ending the compositor or the shell takes the session down
                        enabled: !/^(niri|qs|quickshell|systemd|init)$/.test(procRow.p.name)
                        Accessible.name: Tr.t("End") + " " + procRow.p.name
                        onClicked: {
                            if (win.confirmPid === procRow.p.pid) { TopProcesses.end(procRow.p.pid, win.endSignal); win.confirmPid = -1; }
                            else win.confirmPid = procRow.p.pid;
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
