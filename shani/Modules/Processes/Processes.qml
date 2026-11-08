// The Mission Center: the heaviest processes, what is using the machine,
// and a way to end it (SIGTERM, so the program can save and close). System
// numbers come from SysStats / Gpu / TopProcesses, all throttled background
// Processes (2s) — the UI thread never blocks on /proc or nvidia-smi.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.processes
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-processes"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: visible && Settings.blurWanted ? procRegion : null
    Region { id: procRegion; item: card; radius: Theme.radius }
    onVisibleChanged: TopProcesses.watching = visible
    // made when opened and gone when closed (shell.qml's LazyLoader)
    Component.onCompleted: TopProcesses.watching = visible
    Component.onDestruction: TopProcesses.watching = false

    MouseArea { anchors.fill: parent; onClicked: Ui.processes = false }
    Glass {
        id: card
        strong: true
        x: parent.width - width - 12
        y: Theme.barHeight + 14
        width: 420
        implicitHeight: Math.min(parent.height - (Theme.barHeight + 30), col.implicitHeight + 20)
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6
            SectionTitle {
                Layout.fillWidth: true
                Layout.margins: 4
                text: "Mission Center · cpu " + Math.round(SysStats.cpu * 100) + "% · mem " + Math.round(SysStats.mem * 100) + "%"
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
                text: Tr.t("Using the most")
            }
            Repeater {
                model: TopProcesses.list
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: "utilities-system-monitor"
                    title: modelData.name + "  ·  " + modelData.threads + " threads"
                    subtitle: "pid " + modelData.pid
                    trailing: modelData.cpu.toFixed(0) + "% cpu · " + modelData.mem.toFixed(1) + "% mem"
                    Button {
                        text: Tr.t("End")
                        kind: "danger"
                        onClicked: TopProcesses.end(parent.parent.modelData.pid)
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
