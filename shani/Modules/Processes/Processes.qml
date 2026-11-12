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
    implicitWidth: 520
    implicitHeight: 720
    onVisibleChanged: TopProcesses.watching = visible
    // made when opened and gone when closed (shell.qml's LazyLoader)
    Component.onCompleted: { TopProcesses.watching = visible; treeList = buildTree(); }
    Component.onDestruction: TopProcesses.watching = false

    // ---- build a flat tree list with indent levels -------------------------
    // root processes (ppid <= 1 or ppid not among listed pids) are top-level;
    // children are indented under their parent
    property var treeList: []
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

    Item {
        id: card
        anchors.fill: parent
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6
            SectionTitle {
                Layout.fillWidth: true
                Layout.margins: 4
                text: "CPU " + Math.round(SysStats.cpu * 100) + " %  ·  " + Tr.t("memory") + " " + Math.round(SysStats.mem * 100) + "%"
            }
            // --- system ---------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: sysCol.implicitHeight + 16
                radius: 10
                color: Theme.surface1
                border.width: 1
                border.color: Theme.stroke
                Column {
                    id: sysCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 3
                    Text {
                        width: parent.width
                        text: Tr.t("System — up %1 · threads %2 · %3 · handles %4").arg(SysStats.uptimeStr).arg(SysStats.threads).arg(SysStats.clockSpeed || "clock unknown").arg(SysStats.fileHandles)
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        text: SysStats.temp > 0 ? ("cpu " + Math.round(SysStats.temp) + "° · ") : ""
                            + SysStats.memTotalGb.toFixed(1) + " GB · "
                            + (Gpu.stats ? (Gpu.stats.name + " " + Math.round(Gpu.stats.util) + "% · " + Math.round(Gpu.stats.memUsed / Math.max(1, Gpu.stats.memTotal) * 100) + "% mem") : "no GPU")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10 * Theme.fontScale
                        wrapMode: Text.Wrap
                    }
                    // per-core bars
                    Row {
                        spacing: 4
                        visible: SysStats.perCore.length > 0
                        Repeater {
                            model: SysStats.perCore
                            Rectangle {
                                required property real modelData
                                width: 30
                                height: 8
                                radius: 4
                                color: Theme.pressed
                                Rectangle {
                                    width: parent.width * Math.min(1, Math.max(0, parent.modelData))
                                    height: parent.height
                                    radius: 4
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
                            font.pixelSize: 10 * Theme.fontScale
                            font.features: { "tnum": 1 }
                        }
                    }
                    Text {
                        width: parent.width
                        text: Tr.t("Per-process network: needs nethogs (root) — %1").arg(TopProcesses.nethogsAvailable ? "available" : "not installed, omitted")
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 9 * Theme.fontScale
                        wrapMode: Text.Wrap
                    }
                }
            }
            SectionTitle {
                Layout.fillWidth: true
                Layout.margins: 4
                text: Tr.t("Process tree")
            }
            // the processes, a row each, in a list that scrolls: as a Repeater of
            // heightless Items every row was drawn on top of the one before
            ListView {
                id: procList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 160
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: win.treeList
                delegate: RowLayout {
                    id: procRow
                    required property var modelData
                    readonly property int indent: modelData.indent
                    readonly property var p: modelData.p
                    width: procList.width
                    height: 28
                    spacing: 6
                    Item { implicitWidth: procRow.indent * 14; implicitHeight: 1 }
                    Text {
                        text: procRow.p.name
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                        color: procRow.indent === 0 ? Theme.text : Theme.dim
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: procRow.p.pid
                        font.family: Theme.font
                        font.pixelSize: 10 * Theme.fontScale
                        font.features: { "tnum": 1 }
                        color: Theme.faint
                    }
                    Text {
                        text: procRow.p.cpu.toFixed(0) + " %  ·  " + procRow.p.mem.toFixed(1) + " %"
                        font.family: Theme.font
                        font.pixelSize: 10 * Theme.fontScale
                        font.features: { "tnum": 1 }
                        color: procRow.p.cpu >= 50 ? Theme.danger : Theme.dim
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: 96
                    }
                    Button {
                        text: Tr.t("End")
                        flat: true
                        Accessible.name: Tr.t("End") + " " + procRow.p.name
                        onClicked: TopProcesses.end(procRow.p.pid)
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("CPU is % since the last sample (/proc/stat deltas) · updates every 2s")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
                wrapMode: Text.Wrap
            }
        }
    }
}