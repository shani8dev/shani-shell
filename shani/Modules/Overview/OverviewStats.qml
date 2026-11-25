// The overview's corner card, after Android's recents: how busy the computer
// is (CPU, memory), the apps holding the most memory, and "Close all" - the
// Android button, which closes the open windows (a second click confirms).
// There is no "free RAM" button on purpose: Linux keeps spare memory as file
// cache and hands it back the moment an app asks, so emptying it only makes
// the next launch slower. Closing what you no longer use is what frees memory.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Niri.overviewOpen && !Ui.launcher && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; right: true }
    margins { top: 58; right: 16 }
    implicitWidth: Theme.px(300)
    implicitHeight: card.implicitHeight + 8
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-overview-stats"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? cardRegion : null
    Region { id: cardRegion; item: card; radius: card.radius }

    readonly property var windows: Object.values(Niri.windows)
    property bool _watching: false
    onVisibleChanged: { if (closeAllConfirm) closeAllConfirm.disarm(); if (visible && !_watching) { TopProcesses.requestWatch(); _watching = true; } else if (!visible && _watching) { TopProcesses.releaseWatch(); _watching = false; } }
    Component.onCompleted: { if (visible) { TopProcesses.requestWatch(); _watching = true; } }  // made on first use, already visible
    Component.onDestruction: if (_watching) TopProcesses.releaseWatch()
    // the apps holding the most memory, by name, from the process list
    readonly property var heavy: {
        const by = {};
        for (const p of TopProcesses.list) by[p.name] = (by[p.name] || 0) + Number(p.mem || 0);
        return Object.keys(by).map(n => ({ name: n, mem: by[n] })).sort((a, b) => b.mem - a.mem).slice(0, 3);
    }

    component Meter: ColumnLayout {
        id: m
        property string label
        property string value
        property real fraction: 0
        Layout.fillWidth: true
        spacing: Theme.px(4)
        RowLayout {
            Layout.fillWidth: true
            Text { text: m.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Item { Layout.fillWidth: true }
            Text { text: m.value; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; font.features: { "tnum": 1 } }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.px(6)
            radius: Theme.px(3)
            color: Theme.hover
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, m.fraction))
                height: parent.height
                radius: Theme.px(3)
                color: m.fraction > 0.85 ? Theme.danger : Theme.accent
                Behavior on width { NumberAnimation { duration: Theme.mot(300) } }
            }
        }
    }

    Glass {
        id: card
        x: 4; y: 4
        width: parent.width - 8
        implicitHeight: col.implicitHeight + 28
        strong: true
        radius: Theme.radiusLarge
        ColumnLayout {
            id: col
            x: 14; y: 14
            width: parent.width - 28
            spacing: Theme.px(10)
            Meter { label: Tr.t("Processor"); value: Math.round(SysStats.cpu * 100) + "%"; fraction: SysStats.cpu }
            Meter {
                label: Tr.t("Memory")
                value: SysStats.memTotalGb > 0 ? (SysStats.mem * SysStats.memTotalGb).toFixed(1) + " " + Tr.t("of") + " " + SysStats.memTotalGb.toFixed(1) + " GB" : Math.round(SysStats.mem * 100) + "%"
                fraction: SysStats.mem
            }
            BusyNote { visible: TopProcesses.list.length === 0; note: Tr.t("Reading…") }
            Text { visible: win.heavy.length > 0; text: Tr.t("Using the most memory"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Repeater {
                model: win.heavy
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                    Text { text: modelData.mem.toFixed(1) + "%"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; font.features: { "tnum": 1 } }
                }
            }
            ConfirmButton {
                id: closeAllConfirm
                Layout.fillWidth: true
                implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                visible: win.windows.length > 0
                text: Tr.t("Close all windows")
                armedText: Tr.t("Close %1 windows — click again", win.windows.length)
                kind: closeAllConfirm.armed ? "danger" : "outline"
                interval: 4000
                onConfirmed: {
                    for (const w of win.windows)
                        Niri.action("close-window", "--id", w.id);
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                visible: win.windows.length > 0
                text: Tr.t("Closing what you no longer use is what frees memory; apps may ask to save first.")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
        }
    }
}
