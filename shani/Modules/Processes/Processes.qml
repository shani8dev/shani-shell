// The heaviest processes, from the bar's CPU chip: what is using the machine,
// and a way to end it (SIGTERM, so the program can save and close).
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
    BackgroundEffect.blurRegion: visible && Settings.data.blur ? procRegion : null
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
        width: 360
        height: col.implicitHeight + 20
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 10
            spacing: 2
            SectionTitle {
                Layout.fillWidth: true
                Layout.margins: 4
                text: "Using the most · cpu " + Math.round(SysStats.cpu * 100) + "% · mem " + Math.round(SysStats.mem * 100) + "%"
            }
            Repeater {
                model: TopProcesses.list
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: "utilities-system-monitor"
                    title: modelData.name
                    subtitle: "pid " + modelData.pid
                    trailing: modelData.cpu.toFixed(0) + "% cpu · " + modelData.mem.toFixed(1) + "% mem"
                    Button {
                        text: Tr.t("End")
                        kind: "danger"
                        onClicked: TopProcesses.end(parent.parent.modelData.pid)
                    }
                }
            }
        }
    }
}
