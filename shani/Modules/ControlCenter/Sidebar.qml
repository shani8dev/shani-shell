// The sidebar (after Budgie's Raven): one column sliding in from the right edge,
// everything you reach for without opening an app. Top to bottom: the hour and
// the power row, sliders, the quick-settings tiles and their detail lists, a
// calendar, what is playing, and the notifications — each with "Ask Chronoa".
// A tile appears only where it can work (no flashlight on a desktop, no
// auto-rotate without an accelerometer).
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Bluetooth
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Modules.Notifications

PanelWindow {
    id: win
    screen: Ui.screen
    visible: Ui.controlCenter || slide.x < width
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-sidebar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Ui.controlCenter ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.data.blur && Ui.controlCenter ? sideRegion : null
    Region { id: sideRegion; item: slide; radius: Theme.radiusLarge }

    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
    readonly property var bt: Bluetooth.defaultAdapter
    property string confirm: ""        // the power action waiting for a second click

    // click outside closes
    MouseArea {
        anchors.fill: parent
        onClicked: Ui.closeAll()
    }

    Glass {
        id: slide
        strong: true
        width: 420
        y: Theme.barHeight + 18
        height: parent.height - y - 10
        x: Ui.controlCenter ? parent.width - width - 10 : parent.width + 10
        radius: Theme.radiusLarge
        Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        focus: Ui.controlCenter
        Keys.onEscapePressed: Ui.closeAll()

        MouseArea { anchors.fill: parent }   // swallow clicks so they don't close

        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            visible: Ui.expanded === "settings"
            contentHeight: settingsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: settingsCol
                width: parent.width
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    IconButton { icon: "go-previous"; onClicked: Ui.expanded = "" }
                    Text { text: "Shell settings"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                }
                SettingsPage { Layout.fillWidth: true; visible: Ui.expanded === "settings" }
            }
        }

        Flickable {
            id: flick
            visible: Ui.expanded !== "settings"
            anchors.fill: parent
            anchors.margins: 16
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: col
                width: flick.width
                spacing: 14

                // ---- header ---------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Column {
                        Layout.fillWidth: true
                        Text {
                            text: Qt.formatDateTime(clock.date, Settings.data.use24h ? "HH:mm" : "h:mm AP")
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 34
                            font.weight: Font.Light
                        }
                        Text {
                            text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                                  + (Power.hasBattery ? "  ·  " + Math.round(Power.percent * 100) + "%" + (Power.timeLeft ? " · " + Power.timeLeft : "") : "")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 12
                        }
                    }
                    IconButton { icon: "preferences-system"; onClicked: Ui.expanded = "settings" }
                    IconButton { icon: "system-lock-screen"; onClicked: { Ui.closeAll(); Lock.lock(); } }
                    IconButton {
                        icon: "system-shutdown"
                        on: Ui.expanded === "power"
                        onClicked: Ui.expanded = Ui.expanded === "power" ? "" : "power"
                    }
                }

                RowLayout {
                    visible: Ui.expanded === "power"
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "logout", label: "Log out", run: () => Power.logout() },
                            { id: "suspend", label: "Suspend", run: () => Power.suspend() },
                            { id: "reboot", label: "Reboot", run: () => Power.reboot() },
                            { id: "poweroff", label: "Power off", run: () => Power.poweroff() }
                        ]
                        Button {
                            required property var modelData
                            Layout.fillWidth: true
                            text: win.confirm === modelData.id ? "Sure?" : modelData.label
                            kind: win.confirm === modelData.id ? "danger" : "plain"
                            onClicked: {
                                // suspend and log out are undoable; the others ask once more
                                if (modelData.id === "suspend" || win.confirm === modelData.id) {
                                    win.confirm = "";
                                    Ui.closeAll();
                                    modelData.run();
                                } else {
                                    win.confirm = modelData.id;
                                }
                            }
                        }
                    }
                }

                // ShaniOS updates (shani-deploy, as Cassini reads it)
                ListRow {
                    Layout.fillWidth: true
                    visible: Updates.attention
                    icon: Updates.rebootNeeded ? "system-reboot" : "software-update-available"
                    title: Updates.summary
                    subtitle: "Open Cassini"
                    selected: true
                    onClicked: { Ui.closeAll(); Updates.open(); }
                }

                // ---- sliders --------------------------------------------------
                SliderRow {
                    Layout.fillWidth: true
                    icon: Audio.icon
                    value: Audio.volume
                    muted: Audio.muted
                    hasDetail: true
                    expanded: Ui.expanded === "audio"
                    onMoved: v => Audio.setVolume(v)
                    onIconClicked: Audio.toggleMute()
                    onDetail: Ui.expanded = Ui.expanded === "audio" ? "" : "audio"
                }
                SliderRow {
                    Layout.fillWidth: true
                    visible: Brightness.available
                    icon: "display-brightness"
                    value: Brightness.value
                    onMoved: v => Brightness.set(v)
                }

                ColumnLayout {
                    visible: Ui.expanded === "audio"
                    Layout.fillWidth: true
                    spacing: 2
                    SectionTitle { text: "Output" }
                    Repeater {
                        model: Audio.sinks
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "audio-speakers"
                            title: Audio.nodeName(modelData)
                            selected: modelData === Audio.sink
                            onClicked: Audio.useSink(modelData)
                        }
                    }
                    SectionTitle { visible: Audio.players.length > 0; text: "Apps" }
                    Repeater {
                        model: Audio.players
                        SliderRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: modelData.audio && modelData.audio.muted ? "audio-volume-muted" : "audio-volume-high"
                            value: modelData.audio ? modelData.audio.volume : 0
                            muted: modelData.audio ? modelData.audio.muted : false
                            onMoved: v => modelData.audio.volume = v
                            onIconClicked: modelData.audio.muted = !modelData.audio.muted
                            Text {
                                text: Audio.streamName(modelData)
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 10
                                Layout.maximumWidth: 90
                                elide: Text.ElideRight
                            }
                        }
                    }
                    SectionTitle { text: "Input" }
                    Repeater {
                        model: Audio.sources
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "audio-input-microphone"
                            title: Audio.nodeName(modelData)
                            selected: modelData === Audio.source
                            onClicked: Audio.useSource(modelData)
                        }
                    }
                    SliderRow {
                        Layout.fillWidth: true
                        visible: Audio.source !== null
                        icon: Audio.micMuted ? "microphone-sensitivity-muted" : "audio-input-microphone"
                        value: Audio.micVolume
                        muted: Audio.micMuted
                        onMoved: v => Audio.setMicVolume(v)
                        onIconClicked: Audio.toggleMic()
                    }
                }

                // ---- tiles ----------------------------------------------------
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8

                    Tile {
                        Layout.fillWidth: true
                        visible: Net.hasWifi
                        icon: Net.wifiEnabled ? "network-wireless-signal-excellent" : "network-wireless-disabled"
                        title: "Wi-Fi"
                        subtitle: Net.activeWifi ? Net.activeWifi.name : (Net.wifiEnabled ? "Not connected" : "Off")
                        on: Net.wifiEnabled
                        hasDetail: true
                        expanded: Ui.expanded === "wifi"
                        onToggled: Net.setWifi(!Net.wifiEnabled)
                        onDetail: Ui.expanded = Ui.expanded === "wifi" ? "" : "wifi"
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: win.bt !== null
                        icon: win.bt && win.bt.enabled ? "bluetooth-active" : "bluetooth-disabled"
                        title: "Bluetooth"
                        subtitle: {
                            if (!win.bt || !win.bt.enabled)
                                return "Off";
                            const c = Bluetooth.devices.values.filter(d => d.connected);
                            return c.length === 0 ? "On" : c.length === 1 ? c[0].name : c.length + " devices";
                        }
                        on: win.bt !== null && win.bt.enabled
                        hasDetail: true
                        expanded: Ui.expanded === "bluetooth"
                        onToggled: win.bt.enabled = !win.bt.enabled
                        onDetail: Ui.expanded = Ui.expanded === "bluetooth" ? "" : "bluetooth"
                    }
                    Tile {
                        Layout.fillWidth: true
                        icon: "airplane-mode"
                        title: "Airplane mode"
                        subtitle: Net.airplane ? "On" : "Off"
                        on: Net.airplane
                        onToggled: Net.setAirplane(!Net.airplane)
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: Net.hasWifi
                        icon: "network-wireless-hotspot"
                        title: "Hotspot"
                        subtitle: Net.hotspotOn ? "Sharing" : "Off"
                        on: Net.hotspotOn
                        onToggled: Net.setHotspot(!Net.hotspotOn)
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: Net.vpns.length > 0
                        icon: "network-vpn"
                        title: "VPN"
                        subtitle: (Net.vpns.find(v => v.active) || { name: "Off" }).name
                        on: Net.vpnActive
                        hasDetail: true
                        expanded: Ui.expanded === "vpn"
                        onToggled: {
                            const a = Net.vpns.find(v => v.active);
                            a ? Net.setVpn(a.name, false) : Net.setVpn(Net.vpns[0].name, true);
                        }
                        onDetail: Ui.expanded = Ui.expanded === "vpn" ? "" : "vpn"
                    }
                    Tile {
                        Layout.fillWidth: true
                        icon: Notifs.dnd ? "notifications-disabled" : "preferences-system-notifications"
                        title: "Do Not Disturb"
                        subtitle: Notifs.dnd ? "Only critical" : "Off"
                        on: Notifs.dnd
                        onToggled: Notifs.setDnd(!Notifs.dnd)
                    }
                    Tile {
                        Layout.fillWidth: true
                        icon: "preferences-desktop-screensaver"
                        title: "Caffeine"
                        subtitle: Idle.caffeine ? "Staying awake" : "Off"
                        on: Idle.caffeine
                        onToggled: Idle.setCaffeine(!Idle.caffeine)
                    }
                    Tile {
                        Layout.fillWidth: true
                        icon: Power.profileIcon
                        title: "Power mode"
                        subtitle: Power.profileName
                        on: Power.profileName !== "Balanced"
                        onToggled: Power.cycleProfile()
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: NightLight.available
                        icon: "night-light"
                        title: "Night light"
                        subtitle: NightLight.active ? Settings.data.nightLightTemp + " K" : "Off"
                        on: NightLight.active
                        onToggled: NightLight.toggle()
                    }
                    Tile {
                        Layout.fillWidth: true
                        icon: "weather-clear-night"
                        title: "Dark style"
                        subtitle: Appearance.dark ? "On" : "Off"
                        on: Appearance.dark
                        onToggled: Appearance.toggle()
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: Audio.source !== null
                        icon: Audio.micMuted ? "microphone-sensitivity-muted" : "audio-input-microphone"
                        title: "Microphone"
                        subtitle: Audio.micMuted ? "Muted" : (Privacy.micInUse ? "In use" : "On")
                        on: !Audio.micMuted
                        onToggled: Audio.toggleMic()
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: Privacy.cameraPresent
                        icon: Privacy.cameraEnabled ? "camera-web" : "camera-disabled"
                        title: "Camera"
                        subtitle: !Privacy.cameraEnabled ? "Off" : (Privacy.cameraInUse ? "In use" : "On")
                        on: Privacy.cameraEnabled
                        onToggled: Privacy.toggleCamera()
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: Recorder.available
                        icon: "media-record"
                        title: "Screen record"
                        subtitle: Recorder.recording ? Recorder.elapsed : "Focused screen"
                        on: Recorder.recording
                        onToggled: {
                            Ui.closeAll();
                            Recorder.toggle();
                        }
                    }
                    Tile {
                        Layout.fillWidth: true
                        icon: "applets-screenshooter"
                        title: "Screenshot"
                        subtitle: "Select or window"
                        onToggled: {
                            Ui.closeAll();
                            Niri.action("screenshot");
                        }
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: Lens.available
                        icon: "system-search"
                        title: "Lens"
                        subtitle: "Read & ask about the screen"
                        onToggled: {
                            Ui.closeAll();
                            Lens.capture();
                        }
                    }
                    Tile {
                        Layout.fillWidth: true
                        icon: "color-select"
                        title: "Color picker"
                        subtitle: "Copies hex"
                        onToggled: {
                            Ui.closeAll();
                            Quickshell.execDetached(["sh", "-c", "c=$(niri msg pick-color | sed -n 's/^Hex: //p'); [ -n \"$c\" ] && printf %s \"$c\" | wl-copy && notify-send -a 'Color picker' \"$c\" 'Copied to clipboard'"]);
                        }
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: AutoRotate.available
                        icon: AutoRotate.active ? "rotation-allowed" : "rotation-locked"
                        title: "Auto-rotate"
                        subtitle: AutoRotate.active ? "On" : "Locked"
                        on: AutoRotate.active
                        onToggled: AutoRotate.toggle()
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: Brightness.torch !== ""
                        icon: "media-flash"
                        title: "Flashlight"
                        subtitle: Brightness.torchOn ? "On" : "Off"
                        on: Brightness.torchOn
                        onToggled: Brightness.toggleTorch()
                    }
                    Tile {
                        Layout.fillWidth: true
                        icon: "video-display"
                        title: "Display"
                        subtitle: Displays.mirroring ? "Mirroring" : (Displays.outputs.length > 1 ? Displays.outputs.length + " screens" : "Scale")
                        on: Displays.mirroring
                        hasDetail: true
                        expanded: Ui.expanded === "display"
                        onToggled: Ui.expanded = Ui.expanded === "display" ? "" : "display"
                        onDetail: Ui.expanded = Ui.expanded === "display" ? "" : "display"
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: Osk.available
                        icon: "input-keyboard"
                        title: "Screen keyboard"
                        hasDetail: false
                        subtitle: Osk.shown ? "Shown" : "Hidden"
                        on: Osk.shown
                        onToggled: Osk.toggle()
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: Ime.running || Niri.layouts.length > 1
                        icon: "input-keyboard"
                        title: Ime.running ? "Input method" : "Keyboard"
                        subtitle: Ime.running ? Ime.current : Niri.layout
                        on: Ime.running && !Ime.current.startsWith("keyboard-")
                        hasDetail: Ime.available
                        onToggled: Ime.running ? Ime.toggle() : Niri.action("switch-layout", "next")
                        onDetail: { Ui.closeAll(); Ime.configure(); }
                    }
                    Tile {
                        Layout.fillWidth: true
                        visible: Clipboard.available
                        icon: "edit-paste"
                        title: "Clipboard"
                        subtitle: "History"
                        onToggled: Ui.toggleLauncher("c ")
                    }
                    Tile {
                        Layout.fillWidth: true
                        icon: "face-smile-big"
                        title: "Chronoa"
                        subtitle: Chronoa.state === "offline" ? "Offline" : "Ask anything"
                        on: Chronoa.open
                        onToggled: {
                            Ui.closeAll();
                            Chronoa.open = !Chronoa.open;
                        }
                    }
                }

                // ---- detail lists -------------------------------------------
                ColumnLayout {
                    id: wifiList
                    visible: Ui.expanded === "wifi" && Net.hasWifi
                    Layout.fillWidth: true
                    spacing: 2
                    onVisibleChanged: Net.scan(visible)
                    property string pending: ""     // network waiting for a password

                    SectionTitle {
                        text: "Wi-Fi networks"
                        IconButton { icon: "preferences-system"; size: 24; onClicked: { Ui.closeAll(); Net.editConnections(); } }
                    }
                    Repeater {
                        model: Net.networks
                        ColumnLayout {
                            id: netRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4
                            readonly property bool secured: modelData.security !== WifiSecurityType.Open
                            ListRow {
                                Layout.fillWidth: true
                                icon: modelData.signalStrength > 0.75 ? "network-wireless-signal-excellent" : modelData.signalStrength > 0.5 ? "network-wireless-signal-good" : modelData.signalStrength > 0.25 ? "network-wireless-signal-ok" : "network-wireless-signal-weak"
                                title: modelData.name
                                subtitle: modelData.connected ? "Connected" : modelData.stateChanging ? "Connecting…" : (modelData.known ? "Saved" : "")
                                selected: modelData.connected
                                onClicked: {
                                    if (modelData.connected)
                                        modelData.disconnect();
                                    else if (modelData.known || !netRow.secured)
                                        modelData.connect();
                                    else
                                        wifiList.pending = modelData.name;
                                }
                            }
                            TextField {
                                Layout.fillWidth: true
                                visible: wifiList.pending === netRow.modelData.name
                                placeholder: "Password for " + netRow.modelData.name
                                secret: true
                                onAccepted: {
                                    netRow.modelData.connectWithPsk(text);
                                    text = "";
                                    wifiList.pending = "";
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: Ui.expanded === "bluetooth" && win.bt !== null
                    Layout.fillWidth: true
                    spacing: 2
                    onVisibleChanged: if (win.bt) win.bt.discovering = visible && win.bt.enabled
                    SectionTitle {
                        text: win.bt && win.bt.discovering ? "Bluetooth · searching" : "Bluetooth"
                        IconButton { icon: "preferences-system"; size: 24; onClicked: { Ui.closeAll(); Quickshell.execDetached(["blueman-manager"]); } }
                    }
                    Repeater {
                        model: Bluetooth.devices.values.slice().sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired))
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: modelData.icon || "bluetooth-active"
                            title: modelData.name || modelData.address
                            subtitle: modelData.connected ? "Connected" : modelData.pairing ? "Pairing…" : modelData.paired ? "Paired" : "Available"
                            trailing: modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : ""
                            selected: modelData.connected
                            onClicked: {
                                if (modelData.connected)
                                    modelData.disconnect();
                                else if (modelData.paired)
                                    modelData.connect();
                                else {
                                    modelData.trusted = true;
                                    modelData.pair();
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: Ui.expanded === "vpn"
                    Layout.fillWidth: true
                    spacing: 2
                    SectionTitle { text: "VPN" }
                    Repeater {
                        model: Net.vpns
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "network-vpn"
                            title: modelData.name
                            subtitle: modelData.active ? "Connected" : ""
                            selected: modelData.active
                            onClicked: Net.setVpn(modelData.name, !modelData.active)
                        }
                    }
                }

                ColumnLayout {
                    visible: Ui.expanded === "display"
                    Layout.fillWidth: true
                    spacing: 6
                    onVisibleChanged: if (visible) Displays.refresh()
                    SectionTitle { text: "Displays" }
                    Repeater {
                        model: Displays.outputs
                        ColumnLayout {
                            id: out
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: out.modelData.label + "  ·  " + out.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: [1, 1.25, 1.5, 1.75, 2]
                                    Choice {
                                        required property real modelData
                                        text: Math.round(modelData * 100) + "%"
                                        selected: Math.abs(out.modelData.scale - modelData) < 0.01
                                        onClicked: Displays.setScale(out.modelData.name, modelData)
                                    }
                                }
                                Choice {
                                    visible: Displays.canMirror && Displays.outputs.length > 1
                                    text: Displays.mirroring ? "Stop mirroring" : "Mirror this screen"
                                    selected: Displays.mirroring
                                    onClicked: Displays.toggleMirror(out.modelData.name)
                                }
                            }
                        }
                    }
                }

                // ---- drives ------------------------------------------------------
                ColumnLayout {
                    visible: Drives.drives.length > 0
                    Layout.fillWidth: true
                    spacing: 2
                    SectionTitle { text: "Drives" }
                    Repeater {
                        model: Drives.drives
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "drive-removable-media"
                            title: modelData.label
                            subtitle: modelData.size + (modelData.mount ? " · " + modelData.mount : " · not mounted")
                            onClicked: modelData.mount ? Drives.open(modelData) : Drives.mount(modelData)
                            IconButton {
                                icon: "media-eject"
                                size: 26
                                onClicked: Drives.eject(parent.parent.modelData)
                            }
                        }
                    }
                }

                // ---- calendar --------------------------------------------------
                Calendar {
                    Layout.fillWidth: true
                    today: clock.date
                }

                // ---- now playing ------------------------------------------------
                Glass {
                    visible: win.player !== null
                    Layout.fillWidth: true
                    implicitHeight: 92
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12
                        ClippingRectangle {
                            implicitWidth: 66
                            implicitHeight: 66
                            radius: 10
                            color: Theme.hover
                            Image {
                                anchors.fill: parent
                                source: win.player ? win.player.trackArtUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: win.player ? (win.player.trackTitle || win.player.identity) : ""
                                color: Theme.text
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: win.player ? win.player.trackArtist : ""
                                color: Theme.dim
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 11
                            }
                            Row {
                                spacing: 4
                                IconButton { icon: "media-skip-backward"; size: 28; onClicked: win.player.previous() }
                                IconButton { icon: win.player && win.player.isPlaying ? "media-playback-pause" : "media-playback-start"; size: 28; on: true; onClicked: win.player.togglePlaying() }
                                IconButton { icon: "media-skip-forward"; size: 28; onClicked: win.player.next() }
                            }
                        }
                    }
                }

                // ---- notifications ------------------------------------------
                SectionTitle {
                    Layout.fillWidth: true
                    text: Notifs.count > 0 ? "Notifications · " + Notifs.count : "Notifications"
                    IconButton {
                        icon: Notifs.dnd ? "notifications-disabled" : "preferences-system-notifications"
                        size: 26
                        on: Notifs.dnd
                        onClicked: Notifs.setDnd(!Notifs.dnd)
                    }
                    IconButton { visible: Notifs.count > 0; icon: "edit-clear-all"; size: 26; onClicked: Notifs.clearAll() }
                }
                Text {
                    visible: Notifs.count === 0
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    horizontalAlignment: Text.AlignHCenter
                    text: "You're all caught up"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 12
                }
                // grouped by app, newest group first; the app is named once
                Repeater {
                    model: {
                        const groups = [];
                        for (const n of Notifs.list) {
                            const key = n.appName || "Notifications";
                            let g = groups.find(x => x.app === key);
                            if (!g)
                                groups.push(g = { app: key, items: [] });
                            g.items.push(n);
                        }
                        return groups;
                    }
                    ColumnLayout {
                        id: group
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            visible: group.modelData.items.length > 1
                            Text {
                                Layout.fillWidth: true
                                text: group.modelData.app + " · " + group.modelData.items.length
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            Button {
                                text: "Clear"
                                onClicked: group.modelData.items.slice().forEach(n => n.dismiss())
                            }
                        }
                        Repeater {
                            model: group.modelData.items
                            NotificationCard {
                                required property var modelData
                                Layout.fillWidth: true
                                notification: modelData
                                showApp: group.modelData.items.length === 1
                            }
                        }
                    }
                }
                Item { implicitHeight: 4 }
            }
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
