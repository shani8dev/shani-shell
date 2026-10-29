// The bar, one per screen. Left: launcher, workspaces, focused window.
// Centre: kept clear for the Island (Chronoa's companion, Modules/Island).
// Right: now playing, throughput, load, recording/privacy dots, tray, the
// status cluster (opens the sidebar), the notification bell and the clock.
// Scroll on the status cluster to change volume.
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: bar
        required property var modelData
        screen: modelData
        readonly property string output: modelData.name
        readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null

        anchors { top: true; left: true; right: true }
        margins { top: 8; left: 10; right: 10 }
        implicitHeight: Theme.barHeight
        exclusiveZone: Theme.barHeight + 8
        color: "transparent"
        WlrLayershell.namespace: "shani-panel"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        BackgroundEffect.blurRegion: Settings.data.blur ? barRegion : null
        Region { id: barRegion; item: glass; radius: Theme.radius }

        // Caffeine: an idle inhibitor needs a visible surface to hang on, and
        // the bar is always up. Only the first screen's bar holds it.
        IdleInhibitor {
            enabled: Idle.caffeine && bar.modelData === Quickshell.screens[0]
            window: bar
        }

        Glass {
            id: glass
            anchors.fill: parent

            // ---- left -----------------------------------------------------
            RowLayout {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Chip {
                    icon: "view-app-grid"
                    tint: Theme.accent
                    active: Ui.launcher
                    onClicked: Ui.toggleLauncher()
                    onRightClicked: Ui.toggleLauncher("=")
                }

                // niri workspaces of this output: one accent pill slides to the
                // active one (iOS / Android-style), the numbers sit on top
                Item {
                    implicitWidth: wsRow.implicitWidth
                    implicitHeight: 22
                    readonly property var activeItem: {
                        const ws = Niri.workspacesOn(bar.output);
                        const i = ws.findIndex(w => w.is_active);
                        return i >= 0 ? wsRepeater.itemAt(i) : null;
                    }
                    Rectangle {
                        visible: parent.activeItem !== null
                        x: parent.activeItem ? parent.activeItem.x : 0
                        width: parent.activeItem ? parent.activeItem.width : 0
                        height: 22
                        radius: 8
                        color: Theme.accentSoft
                        border.width: 1
                        border.color: Theme.accentLine
                        Behavior on x { NumberAnimation { duration: Theme.anim * 1.4; easing.type: Easing.OutCubic } }
                        Behavior on width { NumberAnimation { duration: Theme.anim * 1.4; easing.type: Easing.OutCubic } }
                    }
                Row {
                    id: wsRow
                    spacing: 4
                    Repeater {
                        id: wsRepeater
                        model: Niri.workspacesOn(bar.output)
                        Rectangle {
                            required property var modelData
                            readonly property bool occupied: modelData.active_window_id !== null
                            implicitWidth: modelData.is_active ? 30 : 22
                            implicitHeight: 22
                            radius: 8
                            color: modelData.is_active ? "transparent" : (wsArea.containsMouse ? Theme.hover : "transparent")
                            border.width: modelData.is_urgent ? 1 : 0
                            border.color: Theme.red
                            Behavior on implicitWidth { NumberAnimation { duration: Theme.anim } }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.name || modelData.idx
                                color: modelData.is_active ? Theme.accent : (parent.occupied ? Theme.text : Theme.faint)
                                font.family: Theme.font
                                font.pixelSize: 12 * Theme.fontScale
                                font.weight: modelData.is_active ? Font.DemiBold : Font.Normal
                            }
                            MouseArea {
                                id: wsArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Niri.focusWorkspace(parent.modelData)
                            }
                        }
                    }
                }
                }

                Rectangle { width: 1; height: 16; color: Theme.stroke; Layout.leftMargin: 6; Layout.rightMargin: 6 }

                // focused window: app icon + title; click for the window menu
                Row {
                    id: titleRow
                    spacing: 7
                    visible: Niri.focusedWindow !== null
                    Layout.maximumWidth: Math.max(120, bar.width * 0.22)
                    IconImage {
                        implicitSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                        source: {
                            const w = Niri.focusedWindow;
                            const e = w ? DesktopEntries.heuristicLookup(w.app_id) : null;
                            return Quickshell.iconPath(e ? e.icon : (w ? w.app_id : ""), true);
                        }
                    }
                    Text {
                        width: Math.min(implicitWidth, parent.Layout.maximumWidth - 24)
                        text: Niri.focusedWindow ? (Niri.focusedWindow.title || Niri.focusedWindow.app_id) : ""
                        color: Theme.dim
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    // a handler, not a MouseArea child: a child sized to the Row
                    // feeds the Row's own width back into itself (it hung the shell)
                    TapHandler {
                        onTapped: {
                            Ui.closeAll();
                            Ui.windowMenuX = titleRow.mapToItem(null, 0, 0).x + 10;
                            Ui.windowMenu = true;
                        }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }

            // ---- right ----------------------------------------------------
            RowLayout {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Chip {
                    visible: bar.player !== null && bar.player.trackTitle !== ""
                    icon: bar.player && bar.player.isPlaying ? "media-playback-pause" : "media-playback-start"
                    label: bar.player ? bar.player.trackTitle + (bar.player.trackArtist ? " · " + bar.player.trackArtist : "") : ""
                    maxLabelWidth: 150
                    tint: Theme.dim
                    onClicked: bar.player.togglePlaying()
                    onRightClicked: bar.player.next()
                    onMiddleClicked: bar.player.previous()
                    onScrolled: d => d > 0 ? bar.player.previous() : bar.player.next()
                }
                Chip {
                    visible: Settings.data.showNetSpeed
                    mono: true
                    tint: Theme.dim
                    label: "↓ " + SysStats.rate(SysStats.rxRate) + "  ↑ " + SysStats.rate(SysStats.txRate)
                }
                Chip {
                    visible: Settings.data.showSysStats
                    mono: true
                    active: Ui.processes
                    tint: SysStats.cpu > 0.85 || SysStats.mem > 0.9 ? Theme.amber : Theme.dim
                    label: "cpu " + Math.round(SysStats.cpu * 100) + "%  mem " + Math.round(SysStats.mem * 100) + "%"
                    onClicked: { const was = Ui.processes; Ui.closeAll(); Ui.processes = !was; }
                }
                Chip {
                    visible: FocusTimer.running
                    icon: "alarm"
                    tint: Theme.accent
                    mono: true
                    label: FocusTimer.label
                    onClicked: Ui.toggleControlCenter("timer")
                }

                // recording + privacy: always visible when true, never hidden in a menu
                Chip {
                    visible: Recorder.recording
                    icon: "media-record"
                    tint: Theme.red
                    label: Recorder.elapsed
                    mono: true
                    onClicked: Recorder.stop()
                }
                Chip {
                    visible: Privacy.micInUse
                    icon: "audio-input-microphone"
                    tint: Theme.amber
                    onClicked: Ui.toggleControlCenter("audio")
                }
                Chip {
                    visible: Audio.screenShared
                    icon: "screen-shared"
                    tint: Theme.red
                    label: "Sharing"
                }
                Chip {
                    visible: Privacy.cameraInUse
                    icon: "camera-web"
                    tint: Theme.amber
                }

                // system tray
                Row {
                    spacing: 2
                    Repeater {
                        model: SystemTray.items
                        Rectangle {
                            id: trayItem
                            required property var modelData
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: 8
                            color: trayArea.containsMouse ? Theme.hover : "transparent"
                            IconImage {
                                id: trayIcon
                                anchors.centerIn: parent
                                implicitSize: 16
                                source: trayItem.modelData.icon
                            }
                            // an icon the theme cannot resolve (fcitx5's, often) still shows something
                            Icon {
                                anchors.centerIn: parent
                                visible: trayIcon.status !== Image.Ready
                                name: "application-x-executable"
                                size: 16
                                color: Theme.dim
                            }
                            QsMenuAnchor {
                                id: trayMenu
                                menu: trayItem.modelData.menu
                                anchor.item: trayItem
                                anchor.edges: Edges.Bottom
                                anchor.gravity: Edges.Bottom
                            }
                            MouseArea {
                                id: trayArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: e => {
                                    const it = trayItem.modelData;
                                    if (e.button === Qt.MiddleButton)
                                        it.secondaryActivate();
                                    else if (e.button === Qt.RightButton || it.onlyMenu)
                                        it.hasMenu && trayMenu.open();
                                    else
                                        it.activate();
                                }
                                onWheel: w => trayItem.modelData.scroll(w.angleDelta.y, false)
                            }
                        }
                    }
                }

                // status cluster: one target, opens the control center
                Chip {
                    active: Ui.controlCenter
                    onClicked: Ui.toggleControlCenter()
                    onScrolled: d => Audio.step(d * 0.05)
                    onMiddleClicked: Audio.toggleMute()

                    Text {
                        // the input method (fcitx5) when it runs, else the xkb layout
                        visible: Ime.running ? Ime.label !== "" : Niri.layouts.length > 1
                        text: Ime.running ? Ime.label : Niri.layout.slice(0, 2).toLowerCase()
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Icon { visible: Focus.on; name: Focus.mode ? Focus.mode.icon : ""; size: 15; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                    Icon { visible: Idle.caffeine; name: "preferences-desktop-screensaver"; size: 15; color: Theme.amber; anchors.verticalCenter: parent.verticalCenter }
                    Icon { visible: Net.vpnActive; name: "network-vpn"; size: 15; color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
                    Icon { name: Net.icon; size: 15; color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
                    Icon {
                        visible: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
                        name: "bluetooth-active"
                        size: 15
                        color: Bluetooth.devices.values.some(d => d.connected) ? Theme.accent : Theme.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Icon { visible: Audio.micMuted && Audio.source !== null; name: "microphone-sensitivity-muted"; size: 15; color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
                    Icon { name: Audio.icon; size: 15; color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
                    Icon {
                        visible: Power.hasBattery
                        name: Power.batteryIcon
                        size: 15
                        color: Power.percent < 0.15 && !Power.charging ? Theme.red : Theme.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        visible: Power.hasBattery && Settings.data.barBatteryPercent
                        text: Math.round(Power.percent * 100) + "%"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Chip {
                    icon: Notifs.dnd ? "notifications-disabled" : "preferences-system-notifications"
                    tint: Notifs.dnd ? Theme.dim : (Notifs.count > 0 ? Theme.accent : Theme.text)
                    label: Notifs.count > 0 ? String(Notifs.count) : ""
                    onClicked: Ui.toggleControlCenter("notifications")
                    onRightClicked: Notifs.setDnd(!Notifs.dnd)
                }
                Chip {
                    active: Ui.controlCenter
                    onClicked: Ui.toggleControlCenter()
                    // an update waiting: a dot on the clock, the sidebar says what
                    Rectangle {
                        visible: Updates.attention
                        width: 7
                        height: 7
                        radius: 4
                        color: Theme.amber
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: Qt.formatDateTime(clock.date, Settings.data.use24h ? (Settings.data.showSeconds ? "HH:mm:ss" : "HH:mm") : (Settings.data.showSeconds ? "h:mm:ss AP" : "h:mm AP"))
                        font.features: { "tnum": 1 }
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 13 * Theme.fontScale
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        visible: Settings.data.barDate
                        text: Qt.formatDateTime(clock.date, "ddd d MMM")
                        font.features: { "tnum": 1 }
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

            }
        }

        SystemClock {
            id: clock
            precision: Settings.data.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
        }
    }
}
