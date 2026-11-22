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
    readonly property var shownList: win.procQuery
        ? win.treeList.filter(x => String(x.p.name || "").toLowerCase().includes(win.procQuery.toLowerCase()))
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
            children.sort((a, b) => b.cpu - a.cpu || b.mem - a.mem);
            for (const p of children) {
                out.push({ p: p, indent: parentIndent });
                walk(parentIndent + 1, p.pid);
            }
        }
        // roots: ppid <= 1 (init/systemd) or ppid not in our list
        const roots = procs.filter(p => p.ppid <= 1 || !byPid[p.ppid]);
        roots.sort((a, b) => b.cpu - a.cpu || b.mem - a.mem);
        for (const p of roots) {
            out.push({ p: p, indent: 0 });
            walk(1, p.pid);
        }
        return out;
    }
    Connections {
        target: TopProcesses
        function onListChanged() { treeList = buildTree(); }
    }

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
            // the processes, a row each, in a list that scrolls: as a Repeater of
            // heightless Items every row was drawn on top of the one before
            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: procList
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
                    property bool confirming: false
                    Timer { interval: 3000; running: procRow.confirming; onTriggered: procRow.confirming = false }
                    // reuseItems recycles rows: a pending confirm must not carry
                    // over to the different process this delegate now shows
                    ListView.onReused: procRow.confirming = false
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
                        text: procRow.confirming ? Tr.t("Tap again") : Tr.t("End")
                        kind: procRow.confirming ? "danger" : "plain"
                        flat: true
                        // ending the compositor or the shell takes the session down
                        enabled: !/^(niri|qs|quickshell|systemd|init)$/.test(procRow.p.name)
                        Accessible.name: Tr.t("End") + " " + procRow.p.name
                        onClicked: {
                            if (procRow.confirming) TopProcesses.end(procRow.p.pid);
                            procRow.confirming = !procRow.confirming;
                        }
                    }
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
    }
}