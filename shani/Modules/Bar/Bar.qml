// The bar, one per screen. Left: launcher, workspaces, focused window.
// Centre: kept clear for the Island (Chronoa's companion, Modules/Island).
// Right: now playing, throughput, load, recording/privacy dots, tray, the
// status cluster (opens the sidebar), the notification bell and the clock.
// Scroll on the status cluster to change volume.
import Quickshell
import Quickshell.Io
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
        readonly property var player: Media.current

        anchors { left: true; right: true }
        anchors.top: bar.edge === "top"
        anchors.bottom: bar.edge === "bottom"
        // which edge the bar is on: the owner's choice, else the screen's kind
        // (a classroom board's is at the bottom, within reach of someone
        // standing at it - docs/FORM-FACTORS.md). Services/FormFactor decides.
        readonly property string edge: FormFactor.barEdge(output)
        // a phone is one column: the workspaces, the world clock and the date
        // go, and the launcher, the status cluster and the clock stay
        readonly property bool narrow: FormFactor.of(output).profile === "phone"
        // the surface starts at the screen's edge, so a hidden bar can be
        // called back by resting the pointer there; the bar itself sits 8 px in
        margins { left: 10; right: 10 }
        implicitHeight: Theme.barHeight + 8
        // always | smart (in view, keeps its space, steps aside for a window over
        // it) | hide (until the pointer asks): Services/Hiding
        readonly property string mode: Settings.data.barVisibility
        exclusionMode: mode === "hide" ? ExclusionMode.Ignore : ExclusionMode.Normal
        exclusiveZone: mode === "hide" ? 0 : Theme.barHeight + 16     // as before: 8 above, the bar, 8 below
        readonly property bool covered: mode === "smart" && Hiding.covered(output, edge, Theme.barHeight + 16 + 2, modelData.height)
        // the Island rides on the bar: when it has something to ask or show, the bar comes back with it
        // the keyboard in the bar (IPC focusBar): this screen's bar, the one being worked on
        readonly property bool keyed: Ui.barFocus && output === Niri.focusedOutput
        onKeyedChanged: if (keyed) Ui.focusFirst(glass)
        // the fit test the phone part reads: on a narrow screen the two clusters
        // must still leave a gap between them (docs/FORM-FACTORS.md)
        readonly property bool overlap: rightCluster.x < leftCluster.x + leftCluster.width
        readonly property bool shown: mode === "always" || (revealed && barHover.hovered) || Niri.overviewOpen || keyed
            || Ui.controlCenter || (Ui.islandBusy && output === Niri.focusedOutput) || (mode === "smart" && !covered)
        property bool revealed: false
        Connections { target: barHover; function onHoveredChanged() { if (!barHover.hovered) bar.revealed = false; } }
        Timer { interval: 250; running: barEdgeHover.hovered && !bar.revealed; onTriggered: bar.revealed = true }
        onShownChanged: Hiding.setBarShown(output, shown)
        Component.onCompleted: { Hiding.setBarShown(output, shown); Hiding.setBarOverlap(output, bar.overlap) }
        onOverlapChanged: Hiding.setBarOverlap(output, overlap)
        HoverHandler { id: barHover }
        Item {
            id: edgeStrip
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.px(4)
            y: bar.edge === "top" ? 0 : parent.height - height
            HoverHandler { id: barEdgeHover }
        }
        mask: Region { item: bar.shown ? whole : edgeStrip }
        Item { id: whole; anchors.fill: parent }
        color: "transparent"
        WlrLayershell.namespace: "shani-panel"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: (keyed) && !Osk.remote ? WlrKeyboardFocus.Exclusive : renamingWs >= 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        property int renamingWs: -1          // the workspace (id) being named: the bar takes the keyboard
        BackgroundEffect.blurRegion: Settings.blurWanted && bar.shown ? barRegion : null
        Region { id: barRegion; item: glass; radius: Theme.radius }

        // Caffeine: an idle inhibitor needs a visible surface to hang on, and
        // the bar is always up. Only the first screen's bar holds it.
        IdleInhibitor {
            enabled: Idle.caffeine && bar.modelData === Quickshell.screens[0]
            window: bar
        }

        Glass {
            id: glass
            focus: bar.keyed
            Keys.onEscapePressed: Ui.barFocus = false
            anchors.fill: parent
            anchors.topMargin: Theme.px(8)
            anchors.bottomMargin: Theme.px(8)
            opacity: bar.shown ? 1 : 0
            // hidden, it slides out over the edge it sits on
            transform: Translate {
                y: bar.shown ? 0 : (bar.edge === "bottom" ? 1 : -1) * (Theme.barHeight + 12)
                Behavior on y { NumberAnimation { duration: Theme.mot(200); easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: Theme.mot(160) } }
            // click-through unused bar space (borrow from Noctalia)
            MouseArea {
                anchors.fill: parent
                hoverEnabled: false
                enabled: Settings.data.barClickThrough
                // no onClicked: events propagate through when enabled
            }

            // ---- left -----------------------------------------------------
            RowLayout {
                id: leftCluster
                anchors.left: parent.left
                anchors.leftMargin: Theme.px(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.px(4)

                Chip {
                    icon: "view-app-grid"
                    tint: Theme.accent
                    active: Ui.launcher
                    hint: Tr.t("Apps, files and settings - right-click for the calculator")
                    hintKeys: "Super + Space"
                    onClicked: Ui.toggleLauncher()
                    hasMenu: true
                    onRightClicked: Ui.toggleLauncher("=")
                }

                // niri workspaces of this output: one accent pill slides to the
                // active one (iOS / Android-style), the numbers sit on top
                Item {
                    visible: !bar.narrow
                    implicitWidth: wsRow.implicitWidth
                    implicitHeight: Theme.px(22)
                    readonly property var activeItem: {
                        const ws = Niri.workspacesOn(bar.output);
                        const i = ws.findIndex(w => w.is_active);
                        return i >= 0 ? wsRepeater.itemAt(i) : null;
                    }
                    Glass {
                        visible: parent.activeItem !== null
                        elevation: "none"
                        edge: "subtle"
                        x: parent.activeItem ? parent.activeItem.x : 0
                        width: parent.activeItem ? parent.activeItem.width : 0
                        height: Theme.px(22)
                        radius: Theme.px(11)
                        color: Theme.card
                        border.color: Theme.accentLine
                        Behavior on x { NumberAnimation { duration: Theme.anim * 1.4; easing.type: Easing.OutCubic } }
                        Behavior on width { NumberAnimation { duration: Theme.anim * 1.4; easing.type: Easing.OutCubic } }
                    }
                Row {
                    id: wsRow
                    spacing: Theme.px(4)
                    Repeater {
                        id: wsRepeater
                        model: Niri.workspacesOn(bar.output)
                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool occupied: modelData.active_window_id !== null
                            readonly property bool renaming: bar.renamingWs === modelData.id
                            implicitWidth: renaming ? 110 : modelData.is_active ? Math.max(28, wsLabel.implicitWidth + 14) : Math.max(20, wsLabel.implicitWidth + 10)
                            implicitHeight: Theme.px(20)
                            radius: Theme.px(10)
                            color: modelData.is_active ? Theme.accent : (wsArea.containsMouse ? Theme.hover : "transparent")
                            border.width: modelData.is_urgent ? 1 : 0
                            border.color: Theme.red
                            Behavior on implicitWidth { NumberAnimation { duration: Theme.anim } }

                            TextInput {
                                visible: parent.renaming
                                anchors.fill: parent
                                anchors.leftMargin: Theme.px(8); anchors.rightMargin: Theme.px(8)
                                verticalAlignment: TextInput.AlignVCenter
                                text: parent.modelData.name || ""
                                color: parent.modelData.is_active ? Theme.accentInk : Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                                maximumLength: 24
                                onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
                                onAccepted: { Niri.renameWorkspace(parent.modelData, text); bar.renamingWs = -1; }
                                Keys.onEscapePressed: bar.renamingWs = -1
                                onActiveFocusChanged: if (!activeFocus && visible) bar.renamingWs = -1
                            }
                            Text {
                                id: wsLabel
                                visible: !parent.renaming
                                anchors.centerIn: parent
                                // its place among the visible ones (the minimised one is hidden)
                                // a floating workspace (WorkspaceLayout): marked, as the layout is the workspace's own
                                text: (modelData.name || (parent.index + 1)) + (WorkspaceLayout.isFloating(modelData) ? " ◇" : "")
                                color: modelData.is_active ? Theme.accentInk : (parent.occupied ? Theme.text : Theme.dim)
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: wsArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                enabled: !parent.renaming
                                onClicked: e => {
                                    if (e.button === Qt.RightButton)
                                        bar.renamingWs = parent.modelData.id;
                                    else
                                        Niri.focusWorkspace(parent.modelData);
                                }
                            }
                            KeyFocus {
                                name: Tr.t("Workspace %1", parent.index + 1)
                                onActivated: { Niri.focusWorkspace(parent.modelData); Ui.barFocus = false; }
                                menuable: true
                                onMenu: bar.renamingWs = parent.modelData.id
                            }
                            Hint { text: Tr.t("Workspace %1", parent.index + 1) + " - " + Tr.t("right-click to name it, Super + O shows them all"); keys: "Super + " + (parent.index + 1) }
                        }
                    }
                }
                }

                Rectangle { width: 1; height: Theme.px(16); color: Theme.stroke; Layout.leftMargin: Theme.px(6); Layout.rightMargin: Theme.px(6) }

                // focused window: app icon + title in a chip; click for the window menu.
                // Its minimise, maximise and close sit right after the title, for every
                // window - including those that draw no titlebar of their own (Unity's idea)
                Glass {
                    id: titleChip
                    elevation: "none"
                    edge: "subtle"
                    visible: Niri.focusedWindow !== null
                    Layout.maximumWidth: Math.max(140, bar.width * 0.25) + 84
                    // sized by what it holds (it had no width of its own and drew no chip)
                    implicitWidth: titleRow.implicitWidth + 20
                    implicitHeight: Theme.px(28)
                    radius: Theme.px(10)
                    color: Theme.card
                    border.color: Theme.stroke
                    Row {
                        id: titleRow
                        spacing: Theme.px(8)
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(10)
                        anchors.rightMargin: Theme.px(10)
                        anchors.verticalCenter: parent.verticalCenter
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
                            width: Math.min(implicitWidth, titleChip.Layout.maximumWidth - 124)
                            text: Niri.focusedWindow ? (Niri.focusedTitle || Niri.focusedWindow.app_id) : ""
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                            font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        // minimise, maximise, close: dim at rest, plain on hover
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            opacity: titleHover.hovered ? 1 : 0.55
                            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                            // by the focused id, not the window looked up from it: the lookup can be
                            // empty for a moment while niri reports a layout change (seen under load)
                            IconButton { size: Theme.px(22); icon: "window-minimize-symbolic"; tip: Tr.t("Minimise (Super+M)"); onClicked: if (Niri.focusedWindowId !== null) Niri.minimise(Niri.focusedWindowId) }
                            IconButton { size: Theme.px(22); icon: "window-maximize-symbolic"; tip: Tr.t("Maximise"); onClicked: Niri.action("maximize-column") }
                            IconButton { size: Theme.px(22); icon: "window-close-symbolic"; tip: Tr.t("Close (Super+Q)"); onClicked: Niri.focusedWindowId !== null ? Niri.action("close-window", "--id", String(Niri.focusedWindowId)) : Niri.action("close-window") }
                        }
                    }
                    // a handler, not a MouseArea child: a child sized to the Row
                    // feeds the Row's own width back into itself (it hung the shell)
                    TapHandler {
                        onTapped: {
                            Ui.closeAll();
                            Ui.windowMenuX = titleChip.mapToItem(null, 0, 0).x + 10;
                            Ui.windowMenu = true;
                        }
                    }
                    HoverHandler { id: titleHover; cursorShape: Qt.PointingHandCursor }
                    KeyFocus {
                        name: Tr.t("This window")
                        onActivated: { Ui.closeAll(); Ui.windowMenuX = titleChip.mapToItem(null, 0, 0).x + 10; Ui.windowMenu = true; }
                    }
                    Hint { text: Tr.t("This window - click for snapping, moving and more"); keys: Tr.t("click") }
                }
            }

            // ---- right ----------------------------------------------------
            RowLayout {
                id: rightCluster
                anchors.right: parent.right
                anchors.rightMargin: Theme.px(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Chip {
                    visible: bar.player !== null && bar.player.trackTitle !== ""
                    icon: bar.player && bar.player.isPlaying ? "media-playback-pause" : "media-playback-start"
                    label: bar.player ? bar.player.trackTitle + (bar.player.trackArtist ? " · " + bar.player.trackArtist : "") : ""
                    maxLabelWidth: 150
                    tint: Theme.dim
                    onClicked: bar.player.togglePlaying()
                    hasMenu: true
                    onRightClicked: bar.player.next()
                    onMiddleClicked: bar.player.previous()
                    onScrolled: d => d > 0 ? bar.player.previous() : bar.player.next()
                }
                // your own (Settings > Bar & dock): nothing runs unless you added one
                Repeater {
                    model: Settings.data.barCommands || []
                    Chip {
                        id: own
                        required property var modelData
                        property string out: ""
                        tint: Theme.dim
                        label: out !== "" ? out : "…"
                        maxLabelWidth: 180
                        hint: modelData.click ? Tr.t("Click: %1").arg(modelData.click) : modelData.command
                        onClicked: if (modelData.click) Quickshell.execDetached(["sh", "-c", modelData.click])
                        Process {
                            id: ownRun
                            running: true
                            command: ["sh", "-c", own.modelData.command || "true"]
                            stdout: StdioCollector {
                                onStreamFinished: own.out = text.trim().split("\n").pop().slice(0, 80)
                            }
                        }
                        Timer {
                            interval: Math.max(2, Number(own.modelData.every) || 0) * 1000
                            running: Number(own.modelData.every) > 0
                            repeat: true
                            onTriggered: ownRun.running = true
                        }
                    }
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
                    tint: SysStats.cpu > 0.85 || SysStats.mem > 0.9 || SysStats.temp > 85 ? Theme.amber : Theme.dim
                    label: "cpu " + Math.round(SysStats.cpu * 100) + "%" + (SysStats.temp > 0 ? " " + Math.round(SysStats.temp) + "°" : "") + "  mem " + Math.round(SysStats.mem * 100) + "%"
                    onClicked: { const was = Ui.processes; Ui.closeAll(); Ui.processes = !was; }
                }
                Chip {
                    visible: FocusTimer.running
                    icon: "alarm"
                    tint: Theme.accent
                    mono: true
                    label: FocusTimer.label
                    onClicked: Ui.openClocks("timer")
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
                    label: Tr.t("Sharing")
                    hint: Tr.t("Your screen is being shared - click to stop")
                    onClicked: Niri.stopCasts()
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
                            implicitWidth: Theme.px(26)
                            implicitHeight: Theme.px(26)
                            radius: Theme.px(8)
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
                                size: Theme.px(16)
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
                                onClicked: e => trayItem.press(e.button)
                                onWheel: w => trayItem.modelData.scroll(w.angleDelta.y, false)
                            }
                            function press(button) {
                                const it = trayItem.modelData;
                                if (button === Qt.MiddleButton)
                                    it.secondaryActivate();
                                else if (button === Qt.RightButton || it.onlyMenu)
                                    it.hasMenu && trayMenu.open();
                                else
                                    it.activate();
                            }
                            KeyFocus { name: trayItem.modelData.tooltipTitle || trayItem.modelData.title || trayItem.modelData.id; menuable: true; onActivated: trayItem.press(Qt.LeftButton); onMenu: trayItem.press(Qt.RightButton) }
                        }
                    }
                }

                // a Bluetooth device running low (headphones, mouse, watch): in the bar until
                // it is charged, not only the one notification that may have gone by
                Chip {
                    readonly property var low: Power.peripherals.filter(d => (d.percentage <= 1 ? d.percentage * 100 : d.percentage) < 20)
                    readonly property var first: low.length ? low[0] : null
                    visible: first !== null
                    icon: first ? (first.iconName || "battery-caution") : ""
                    tint: Theme.amber
                    label: first ? first.model.split(" ").slice(0, 2).join(" ") + " " + Math.round(first.percentage <= 1 ? first.percentage * 100 : first.percentage) + "%" : ""
                    hint: low.length > 1 ? Tr.t("%1 devices running low - charge them soon", low.length) : Tr.t("Running low - charge it soon")
                    onClicked: Ui.toggleControlCenter("bluetooth")
                }
                // status cluster: one target, opens the control center
                Chip {
                    name: Tr.t("Quick settings") + (!Settings.data.hideVolumeGlyph ? (Audio.ready ? ", " + Tr.t("volume %1%", Math.round(Audio.volume * 100)) + (Audio.muted ? " " + Tr.t("muted") : "") : "") : "")
                          + (!Settings.data.hideBrightnessGlyph ? (Power.hasBattery ? ", " + Tr.t("battery %1%", Math.round(Power.percent * 100)) : "") : "")
                    active: Ui.controlCenter
                    pill: true
                    hint: Tr.t("Quick settings: Wi-Fi, sound, battery and more - scroll here for the volume")
                    hintKeys: "Super + ,"
                    onClicked: Ui.toggleControlCenter()
                    onScrolled: d => Audio.step(d * 0.05)
                    onMiddleClicked: Audio.toggleMute()

                    Text {
                        // the input method (fcitx5) when it runs, else the xkb layout
                        visible: Ime.running ? Ime.label !== "" : Niri.layouts.length > 1
                        text: Ime.running ? Ime.label : Niri.layout.slice(0, 2).toLowerCase()
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Icon { visible: Focus.on && !(Settings.data.hideVolumeGlyph || Settings.data.hideBrightnessGlyph); name: Focus.mode ? Focus.mode.icon : ""; size: Theme.px(15); color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                    Icon { visible: Idle.caffeine || Idle.keptAwake; name: "preferences-desktop-screensaver"; size: Theme.px(15); color: Theme.amber; anchors.verticalCenter: parent.verticalCenter }
                    Icon { visible: Net.vpnActive; name: "network-vpn"; size: Theme.px(15); color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
                    Icon { name: Net.icon; size: Theme.px(15); color: Net.portal ? Theme.amber : Theme.text; anchors.verticalCenter: parent.verticalCenter }
                    // the network wants a sign-in: a click opens its page
                    Icon {
                        visible: Net.portal
                        name: "dialog-warning"
                        size: Theme.px(13)
                        color: Theme.amber
                        anchors.verticalCenter: parent.verticalCenter
                        Accessible.role: Accessible.Button
                        Accessible.name: Tr.t("Sign in to this network")
                        MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: Net.openPortal() }
                    }
                    Icon {
                        visible: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
                        name: "bluetooth-active"
                        size: Theme.px(15)
                        color: Bluetooth.devices.values.some(d => d.connected) ? Theme.accent : Theme.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Icon { visible: Audio.micMuted && Audio.source !== null; name: "microphone-sensitivity-muted"; size: Theme.px(15); color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
                    Icon { name: Audio.icon; size: Theme.px(15); color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
                    Icon {
                        visible: Power.hasBattery
                        name: Power.batteryIcon
                        size: Theme.px(15)
                        color: Power.percent < 0.15 && !Power.charging ? Theme.red : Theme.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        visible: Power.hasBattery && Settings.data.barBatteryPercent
                        text: Math.round(Power.percent * 100) + "%"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Chip {
                    icon: Notifs.dnd ? "notifications-disabled" : "preferences-system-notifications"
                    tint: Notifs.dnd ? Theme.dim : (Notifs.count > 0 ? Theme.accent : Theme.text)
                    label: Notifs.count > 0 ? String(Notifs.count) : ""
                    hint: Notifs.dnd ? Tr.t("Do Not Disturb is on - right-click to turn it off") : Tr.t("Notifications - right-click for Do Not Disturb")
                    hintKeys: "Super + N"
                    onClicked: Ui.toggleControlCenter("notifications")
                    hasMenu: true
                    onRightClicked: Notifs.setDnd(!Notifs.dnd)
                }
                // the clock: a chip like the others (it had no width of its own and drew nothing)
                Chip {
                    pill: true
                    name: Qt.formatDateTime(clock.date, Settings.data.use24h ? "HH:mm, dddd d MMMM" : "h:mm AP, dddd d MMMM")
                          + (Updates.attention ? ", " + Tr.t("updates waiting") : "") + ", " + Tr.t("calendar and notes")
                    active: Ui.controlCenter && Ui.expanded === ""
                    hint: Tr.t("Calendar, notes and notifications")
                    hintKeys: "Super + ,"
                    onClicked: Ui.toggleControlCenter()
                    Text {
                        text: Qt.formatDateTime(clock.date, Settings.data.use24h ? (Settings.data.showSeconds ? "HH:mm:ss" : "HH:mm") : (Settings.data.showSeconds ? "h:mm:ss AP" : "h:mm AP"))
                        font.features: { "tnum": 1 }
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(13) * Theme.fontScale
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    // another city's time beside it (Settings > Date & language picks the cities)
                    Text {
                        visible: !bar.narrow && Settings.data.barWorldClock && WorldClock.clocks.length > 0
                        text: WorldClock.clocks.length ? WorldClock.clocks[0].city + " " + WorldClock.clocks[0].time.split(" ").pop() : ""
                        font.features: { "tnum": 1 }
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        visible: !bar.narrow && Settings.data.barDate
                        text: Qt.formatDateTime(clock.date, "ddd d MMM")
                        font.features: { "tnum": 1 }
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    // an update waiting: a dot on the clock
                    Rectangle {
                        visible: Updates.attention
                        width: Theme.px(6); height: Theme.px(6)
                        radius: Theme.px(3)
                        color: Theme.amber
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
