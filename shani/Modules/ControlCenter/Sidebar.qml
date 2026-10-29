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
import Quickshell.Services.Pipewire
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
                    // back: out of a category, then out of settings
                    IconButton { icon: "go-previous"; Accessible.name: "Back"; onClicked: Ui.settingsCat !== "" ? Ui.settingsCat = "" : Ui.expanded = "" }
                    Text { text: settingsPage.catTitle; color: Theme.text; font.family: Theme.font; font.pixelSize: 16 * Theme.fontScale; font.weight: Font.DemiBold; Layout.fillWidth: true }
                }
                SettingsPage {
                    id: settingsPage
                    Layout.fillWidth: true
                    visible: Ui.expanded === "settings"
                    onVisibleChanged: if (!visible) Ui.settingsCat = ""
                }
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
                            font.features: { "tnum": 1 }
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 34 * Theme.fontScale
                            font.weight: Font.Light
                        }
                        Text {
                            text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                                  + (Power.hasBattery ? "  ·  " + Math.round(Power.percent * 100) + "%" + (Power.timeLeft ? " · " + Power.timeLeft : "") : "")
                            font.features: { "tnum": 1 }
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 12 * Theme.fontScale
                        }
                        // the batteries of the mouse, the headphones, the phone …
                        Flow {
                            visible: Power.peripherals.length > 0
                            width: 300
                            spacing: 10
                            Repeater {
                                model: Power.peripherals
                                Row {
                                    required property var modelData
                                    readonly property real pct: modelData.percentage <= 1 ? modelData.percentage * 100 : modelData.percentage
                                    spacing: 4
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: modelData.model + " battery " + Math.round(pct) + " percent"
                                    Icon { name: parent.modelData.iconName || "battery-good"; size: 14; color: parent.pct < 15 ? Theme.red : Theme.dim; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: parent.modelData.model.split(" ").slice(0, 2).join(" ") + " " + Math.round(parent.pct) + "%"
                                        color: parent.pct < 15 ? Theme.red : Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: 11 * Theme.fontScale
                                    }
                                }
                            }
                        }
                        Row {
                            visible: Weather.summary !== ""
                            spacing: 6
                            Icon { name: Weather.icon; size: 14; color: Theme.dim; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: Weather.summary + "  ·  " + Settings.data.weatherCity
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 12 * Theme.fontScale
                            }
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

                // up to six (hibernate, UEFI setup where the machine can): three a row
                GridLayout {
                    visible: Ui.expanded === "power"
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: 6
                    rowSpacing: 6
                    Repeater {
                        model: [
                            { id: "logout", label: "Log out", run: () => Power.logout() },
                            { id: "suspend", label: "Suspend", run: () => Power.suspend() },
                            { id: "hibernate", label: "Hibernate", run: () => Power.hibernate() },
                            { id: "reboot", label: "Reboot", run: () => Power.reboot() },
                            { id: "poweroff", label: "Power off", run: () => Power.poweroff() },
                            { id: "firmware", label: "UEFI setup", run: () => Power.rebootToFirmware() }
                        ].filter(x => (x.id !== "hibernate" || Power.canHibernate) && (x.id !== "firmware" || Power.canFirmwareSetup))
                        Button {
                            required property var modelData
                            Layout.fillWidth: true
                            text: win.confirm === modelData.id ? "Sure?" : modelData.label
                            kind: win.confirm === modelData.id ? "danger" : "plain"
                            onClicked: {
                                // suspend and hibernate resume where they were; the others ask once more
                                if (modelData.id === "suspend" || modelData.id === "hibernate" || win.confirm === modelData.id) {
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
                    onClicked: { Ui.closeAll(); !Updates.available && !Updates.rebootNeeded && Updates.firmware.length ? Updates.openFirmware() : Updates.open(); }
                }

                // ---- sliders --------------------------------------------------
                SliderRow {
                    Layout.fillWidth: true
                    icon: Audio.icon
                    value: Audio.volume / Audio.maxVolume
                    muted: Audio.muted
                    hasDetail: true
                    expanded: Ui.expanded === "audio"
                    onMoved: v => Audio.setVolume(v * Audio.maxVolume)
                    onIconClicked: Audio.toggleMute()
                    onDetail: Ui.expanded = Ui.expanded === "audio" ? "" : "audio"
                }
                SliderRow {
                    Layout.fillWidth: true
                    visible: Audio.source !== null
                    icon: Audio.micMuted ? "microphone-sensitivity-muted" : "audio-input-microphone"
                    value: Audio.micVolume
                    muted: Audio.micMuted
                    level: micLevel.enabled ? Math.min(1, micLevel.peak * 1.5) : -1
                    hasDetail: true
                    expanded: Ui.expanded === "audio"
                    onMoved: v => Audio.setMicVolume(v)
                    onIconClicked: Audio.toggleMic()
                    onDetail: Ui.expanded = Ui.expanded === "audio" ? "" : "audio"
                    PwNodePeakMonitor {
                        id: micLevel
                        node: Audio.source
                        enabled: win.visible && Ui.controlCenter && !Audio.micMuted
                    }
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
                                font.pixelSize: 10 * Theme.fontScale
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
                }

                // ---- tiles ----------------------------------------------------
                // tiles in the person's order (Settings: tileOrder, hiddenTiles); a tile
                // that cannot work here (no Wi-Fi, no camera …) leaves no gap
                Item {
                    id: tileGrid
                    Layout.fillWidth: true
                    readonly property real gap: 8
                    readonly property real cell: (width - gap) / 2
                    readonly property var known: ["wifi", "bluetooth", "airplane", "mobile", "hotspot", "vpn", "dnd", "focus", "phone", "timer", "caffeine", "power", "nightlight", "dark", "mic", "camera", "photo", "record", "screenshot", "lens", "colorpicker", "rotate", "flashlight", "display", "osk", "keyboard", "clipboard", "backup", "access", "captions", "transcribe", "speak", "magnifier", "callrecord", "cast", "touch", "chronoa"]
                    readonly property var order: {
                        const o = Settings.data.tileOrder.filter(t => known.indexOf(t) >= 0);
                        return o.concat(known.filter(t => o.indexOf(t) < 0));       // new tiles join at the end
                    }
                    property var can: ({})
                    readonly property var shown: order.filter(t => can[t] !== false && Settings.data.hiddenTiles.indexOf(t) < 0)
                    onShownChanged: Ui.tilesShown = shown
                    implicitHeight: Math.ceil(shown.length / 2) * (58 + gap)
                    function place(tile) {
                        const i = shown.indexOf(tile.tid);
                        tile.visible = i >= 0;
                        tile.x = (i % 2) * (cell + gap);
                        tile.y = Math.floor(i / 2) * (58 + gap);
                        tile.width = cell;
                    }

                    Tile {
                        tid: "wifi"
                        can: Net.hasWifi
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
                        tid: "bluetooth"
                        can: win.bt !== null
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
                        tid: "airplane"
                        icon: "airplane-mode"
                        title: "Airplane mode"
                        subtitle: Net.airplane ? "On" : "Off"
                        on: Net.airplane
                        onToggled: Net.setAirplane(!Net.airplane)
                    }
                    Tile {
                        tid: "mobile"
                        can: Net.hasModem
                        icon: "network-cellular-signal-good"
                        title: "Mobile data"
                        subtitle: !Net.wwanOn ? "Off" : Modem.modem && Modem.modem.locked ? "SIM locked"
                            : (Modem.modem && Modem.modem.operator ? Modem.modem.operator + " · " + Modem.modem.signal + "%" : Net.modemState === "connected" ? "Connected" : "On")
                        on: Net.wwanOn
                        onToggled: Modem.modem && Modem.modem.locked ? Ui.modemDialog = "pin" : Net.setMobile(!Net.wwanOn)
                    }
                    Tile {
                        tid: "hotspot"
                        can: Net.hasWifi
                        icon: "network-wireless-hotspot"
                        title: "Hotspot"
                        subtitle: Net.hotspotOn ? "Sharing" : "Off"
                        on: Net.hotspotOn
                        onToggled: Net.setHotspot(!Net.hotspotOn)
                    }
                    Tile {
                        tid: "vpn"
                        can: Net.vpns.length > 0 || Net.hasTailscale
                        icon: "network-vpn"
                        title: "VPN"
                        subtitle: (Net.vpns.find(v => v.active) || { name: Net.tailscaleUp ? "Tailscale" : "Off" }).name
                        on: Net.vpnActive || Net.tailscaleUp
                        hasDetail: true
                        expanded: Ui.expanded === "vpn"
                        onToggled: {
                            const a = Net.vpns.find(v => v.active);
                            a ? Net.setVpn(a.name, false) : Net.setVpn(Net.vpns[0].name, true);
                        }
                        onDetail: Ui.expanded = Ui.expanded === "vpn" ? "" : "vpn"
                    }
                    Tile {
                        tid: "dnd"
                        icon: Notifs.dnd ? "notifications-disabled" : "preferences-system-notifications"
                        title: "Do Not Disturb"
                        subtitle: Notifs.dnd ? "Only critical" : "Off"
                        on: Notifs.dnd
                        onToggled: Notifs.setDnd(!Notifs.dnd)
                    }
                    Tile {
                        tid: "focus"
                        icon: Focus.mode ? Focus.mode.icon : "weather-clear-night"
                        title: "Focus"
                        subtitle: Focus.on ? Focus.active + (Settings.data.focusMode === "" ? " · scheduled" : "") : "Off"
                        on: Focus.on
                        hasDetail: true
                        expanded: Ui.expanded === "focus"
                        onToggled: Ui.expanded = Ui.expanded === "focus" ? "" : "focus"
                        onDetail: Ui.expanded = Ui.expanded === "focus" ? "" : "focus"
                    }
                    Tile {
                        tid: "phone"
                        can: Phone.available
                        icon: "phone"
                        title: Phone.name || "Phone"
                        subtitle: !Phone.reachable ? "Pair a phone" : Phone.battery >= 0 ? Phone.battery + "% battery" : "Connected"
                        hasDetail: true
                        expanded: Ui.expanded === "phone"
                        onToggled: Ui.expanded = Ui.expanded === "phone" ? "" : "phone"
                        onDetail: Ui.expanded = Ui.expanded === "phone" ? "" : "phone"
                    }
                    Tile {
                        tid: "timer"
                        icon: "alarm"
                        title: "Focus timer"
                        subtitle: FocusTimer.running ? FocusTimer.label + " left" : "25 min of Work focus"
                        on: FocusTimer.running
                        hasDetail: true
                        expanded: Ui.expanded === "timer"
                        onToggled: FocusTimer.running ? FocusTimer.stop() : FocusTimer.start(25)
                        onDetail: Ui.expanded = Ui.expanded === "timer" ? "" : "timer"
                    }
                    Tile {
                        tid: "caffeine"
                        icon: "preferences-desktop-screensaver"
                        title: "Caffeine"
                        subtitle: Idle.caffeine ? "Staying awake" : "Off"
                        on: Idle.caffeine
                        onToggled: Idle.setCaffeine(!Idle.caffeine)
                    }
                    Tile {
                        tid: "power"
                        icon: Power.profileIcon
                        title: "Power mode"
                        subtitle: Power.profileName
                        on: Power.profileName !== "Balanced"
                        onToggled: Power.cycleProfile()
                    }
                    Tile {
                        tid: "nightlight"
                        can: NightLight.available
                        icon: "night-light"
                        title: "Night light"
                        subtitle: NightLight.active ? Settings.data.nightLightTemp + " K" : "Off"
                        on: NightLight.active
                        onToggled: NightLight.toggle()
                    }
                    Tile {
                        tid: "dark"
                        icon: "weather-clear-night"
                        title: "Dark style"
                        subtitle: Appearance.dark ? "On" : "Off"
                        on: Appearance.dark
                        onToggled: Appearance.toggle()
                    }
                    Tile {
                        tid: "mic"
                        can: Audio.source !== null
                        icon: Audio.micMuted ? "microphone-sensitivity-muted" : "audio-input-microphone"
                        title: "Microphone"
                        subtitle: Audio.micMuted ? "Muted" : (Privacy.micInUse ? "In use" : "On")
                        on: !Audio.micMuted
                        onToggled: Audio.toggleMic()
                    }
                    Tile {
                        tid: "camera"
                        can: Privacy.cameraPresent
                        icon: Privacy.cameraEnabled ? "camera-web" : "camera-disabled"
                        title: "Camera"
                        subtitle: !Privacy.cameraEnabled ? "Off" : (Privacy.cameraInUse ? "In use" : "On")
                        on: Privacy.cameraEnabled
                        onToggled: Privacy.toggleCamera()
                    }
                    Tile {
                        tid: "photo"
                        can: Camera.available && Privacy.cameraEnabled
                        icon: "camera-photo"
                        title: "Photo"
                        subtitle: Camera.phase === "recording" ? "Video · " + Camera.elapsed : "Camera"
                        on: Camera.phase === "recording"
                        hasDetail: true
                        onToggled: {
                            Ui.closeAll();
                            Camera.photo();
                        }
                        onDetail: {
                            Ui.closeAll();
                            Camera.open();
                        }
                    }
                    Tile {
                        tid: "record"
                        can: Recorder.available
                        icon: "media-record"
                        title: "Screen record"
                        subtitle: Recorder.recording ? Recorder.elapsed
                            : (Settings.data.recordArea === "region" ? "Part of the screen" : "Focused screen")
                              + (Settings.data.recordSound === "desktop" ? " · sound" : Settings.data.recordSound === "mic" ? " · mic" : "")
                        on: Recorder.recording
                        hasDetail: true
                        expanded: Ui.expanded === "record"
                        onDetail: Ui.expanded = Ui.expanded === "record" ? "" : "record"
                        onToggled: {
                            Ui.closeAll();
                            Recorder.toggle();
                        }
                    }
                    Tile {
                        tid: "screenshot"
                        icon: "applets-screenshooter"
                        title: "Screenshot"
                        subtitle: "Select or window"
                        onToggled: {
                            Ui.closeAll();
                            Niri.action("screenshot");
                        }
                    }
                    Tile {
                        tid: "lens"
                        can: Lens.available
                        icon: "system-search"
                        title: "Lens"
                        subtitle: "Read & ask about the screen"
                        onToggled: {
                            Ui.closeAll();
                            Lens.capture();
                        }
                    }
                    Tile {
                        tid: "captions"
                        icon: "media-view-subtitles"
                        title: "Live captions"
                        subtitle: Captions.on && Captions.source === "speakers" ? "On" : "What is playing"
                        on: Captions.on && Captions.source === "speakers"
                        onToggled: Captions.toggle()
                    }
                    Tile {
                        tid: "transcribe"
                        icon: "audio-input-microphone"
                        title: "Live transcribe"
                        subtitle: Captions.on && Captions.source === "mic" ? "On · saving" : "The room, as text"
                        on: Captions.on && Captions.source === "mic"
                        onToggled: Captions.transcribe()
                    }
                    Tile {
                        tid: "speak"
                        icon: "audio-speakers"
                        title: "Read aloud"
                        subtitle: Speak.speaking ? "Tap to stop" : "Selected text"
                        on: Speak.speaking
                        onToggled: Speak.speaking ? Speak.stop() : Speak.speakSelection()
                    }
                    Tile {
                        tid: "magnifier"
                        icon: "zoom-in"
                        title: "Magnifier"
                        subtitle: "Loupe"
                        onToggled: {
                            Ui.closeAll();
                            Ui.magnifier = true;
                        }
                    }
                    Tile {
                        tid: "callrecord"
                        icon: "call-start"
                        title: "Call record"
                        subtitle: CallRecorder.recording ? CallRecorder.elapsed : "Both sides"
                        on: CallRecorder.recording
                        onToggled: CallRecorder.toggle()
                    }
                    Tile {
                        tid: "cast"
                        can: Cast.available
                        icon: "video-display"
                        title: "Cast"
                        subtitle: "Miracast"
                        onToggled: {
                            Ui.closeAll();
                            Cast.open();
                        }
                    }
                    Tile {
                        tid: "touch"
                        icon: "input-touchpad"
                        title: "Smart touch"
                        subtitle: "Floating bubble"
                        on: Settings.data.assistiveTouch
                        onToggled: Settings.data.assistiveTouch = !Settings.data.assistiveTouch
                    }
                    Tile {
                        tid: "colorpicker"
                        icon: "color-select"
                        title: "Color picker"
                        subtitle: "Copies hex"
                        onToggled: {
                            Ui.closeAll();
                            Quickshell.execDetached(["sh", "-c", "c=$(niri msg pick-color | sed -n 's/^Hex: //p'); [ -n \"$c\" ] && printf %s \"$c\" | wl-copy && notify-send -a 'Color picker' \"$c\" 'Copied to clipboard'"]);
                        }
                    }
                    Tile {
                        tid: "rotate"
                        can: AutoRotate.available
                        icon: AutoRotate.active ? "rotation-allowed" : "rotation-locked"
                        title: "Auto-rotate"
                        subtitle: AutoRotate.active ? "On" : "Locked"
                        on: AutoRotate.active
                        onToggled: AutoRotate.toggle()
                    }
                    Tile {
                        tid: "flashlight"
                        can: Brightness.torch !== ""
                        icon: "media-flash"
                        title: "Flashlight"
                        subtitle: Brightness.torchOn ? "On" : "Off"
                        on: Brightness.torchOn
                        onToggled: Brightness.toggleTorch()
                    }
                    Tile {
                        tid: "display"
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
                        tid: "osk"
                        can: Osk.available
                        icon: "input-keyboard"
                        title: "Screen keyboard"
                        hasDetail: false
                        subtitle: Osk.shown ? "Shown" : "Hidden"
                        on: Osk.shown
                        onToggled: Osk.toggle()
                    }
                    Tile {
                        tid: "keyboard"
                        can: Ime.running || Niri.layouts.length > 1
                        icon: "input-keyboard"
                        title: Ime.running ? "Input method" : "Keyboard"
                        subtitle: Ime.running ? Ime.current : Niri.layout
                        on: Ime.running && !Ime.current.startsWith("keyboard-")
                        hasDetail: Ime.available
                        onToggled: Ime.running ? Ime.toggle() : Niri.action("switch-layout", "next")
                        onDetail: { Ui.closeAll(); Ime.configure(); }
                    }
                    Tile {
                        tid: "clipboard"
                        can: Clipboard.available
                        icon: "edit-paste"
                        title: "Clipboard"
                        subtitle: "History"
                        onToggled: Ui.toggleLauncher("c ")
                    }
                    Tile {
                        tid: "backup"
                        can: Backup.available
                        icon: "drive-harddisk"
                        title: Backup.running ? "Backing up…" : "Backup"
                        subtitle: Backup.summary
                        on: Backup.running
                        onToggled: if (!Backup.running) Backup.backupNow()
                    }
                    Tile {
                        tid: "access"
                        icon: "preferences-desktop-accessibility"
                        title: "Accessibility"
                        subtitle: [Settings.data.screenReader ? "Screen reader" : "", Settings.data.largeText ? "Large text" : "",
                                   Settings.data.highContrast ? "High contrast" : "", Settings.data.monoAudio ? "Mono" : ""].filter(x => x).join(" · ") || "Off"
                        on: Settings.data.screenReader || Settings.data.largeText || Settings.data.highContrast || Settings.data.monoAudio
                        hasDetail: true
                        expanded: Ui.expanded === "access"
                        onToggled: Ui.expanded = Ui.expanded === "access" ? "" : "access"
                        onDetail: Ui.expanded = Ui.expanded === "access" ? "" : "access"
                    }
                    Tile {
                        tid: "chronoa"
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
                    property string failed: ""      // the one whose password was refused
                    property bool hiddenOpen: false

                    SectionTitle {
                        text: "Wi-Fi networks"
                        IconButton { icon: "view-barcode-qr"; size: 24; visible: Net.activeWifi !== null; Accessible.name: "Share this Wi-Fi as a QR code"; onClicked: { Ui.closeAll(); Qr.shareWifi(); } }
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
                                subtitle: modelData.connected ? "Connected" : modelData.stateChanging ? "Connecting…"
                                    : wifiList.failed === modelData.name ? "Couldn’t connect — check the password"
                                    : (modelData.known ? "Saved" : netRow.secured ? "" : "Open network")
                                selected: modelData.connected
                                onClicked: {
                                    wifiList.failed = "";
                                    if (modelData.connected)
                                        modelData.disconnect();
                                    else if (modelData.known || !netRow.secured)
                                        modelData.connect();
                                    else
                                        wifiList.pending = modelData.name;
                                }
                                IconButton {
                                    visible: netRow.modelData.known
                                    icon: "edit-delete"
                                    size: 24
                                    Accessible.name: "Forget " + netRow.modelData.name
                                    onClicked: netRow.modelData.forget()
                                }
                            }
                            // a refused password: ask again, in place
                            Connections {
                                target: netRow.modelData
                                function onConnectionFailed(reason) {
                                    wifiList.failed = netRow.modelData.name;
                                    if (netRow.secured)
                                        wifiList.pending = netRow.modelData.name;
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
                                    wifiList.failed = "";
                                }
                            }
                        }
                    }
                    ListRow {
                        Layout.fillWidth: true
                        icon: "network-wireless-hidden"
                        title: "Hidden network…"
                        subtitle: Net.hiddenStatus === "connecting" ? "Connecting…" : Net.hiddenStatus.startsWith("failed") ? Net.hiddenStatus.slice(8) : ""
                        onClicked: wifiList.hiddenOpen = !wifiList.hiddenOpen
                    }
                    TextField {
                        id: hiddenSsid
                        Layout.fillWidth: true
                        visible: wifiList.hiddenOpen
                        placeholder: "Network name"
                        onAccepted: hiddenPsk.input.forceActiveFocus()
                    }
                    TextField {
                        id: hiddenPsk
                        Layout.fillWidth: true
                        visible: wifiList.hiddenOpen
                        placeholder: "Password (empty for an open network)"
                        secret: true
                        onAccepted: {
                            if (hiddenSsid.text.trim() === "")
                                return;
                            Net.connectHidden(hiddenSsid.text.trim(), text);
                            text = "";
                            wifiList.hiddenOpen = false;
                        }
                    }
                }

                ColumnLayout {
                    visible: Ui.expanded === "bluetooth" && win.bt !== null
                    Layout.fillWidth: true
                    spacing: 2
                    // while open: searching, and visible to others (so a phone can find this computer)
                    onVisibleChanged: if (win.bt) {
                        win.bt.discovering = visible && win.bt.enabled;
                        win.bt.discoverable = visible && win.bt.enabled;
                    }
                    SectionTitle {
                        text: win.bt && win.bt.discovering ? "Bluetooth · searching" : "Bluetooth"
                    }
                    Repeater {
                        model: Bluetooth.devices.values.slice().sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired))
                        ListRow {
                            id: btRow
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
                            IconButton {
                                visible: btRow.modelData.paired
                                icon: "edit-delete"
                                size: 24
                                Accessible.name: "Forget " + (btRow.modelData.name || btRow.modelData.address)
                                onClicked: btRow.modelData.forget()
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: Ui.expanded === "vpn"
                    Layout.fillWidth: true
                    spacing: 2
                    SectionTitle { text: "VPN" }
                    ListRow {
                        Layout.fillWidth: true
                        visible: Net.hasTailscale
                        icon: "network-vpn"
                        title: "Tailscale"
                        subtitle: Net.tailscaleNote || (Net.tailscaleUp ? "Connected" : "")
                        selected: Net.tailscaleUp
                        onClicked: Net.setTailscale(!Net.tailscaleUp)
                    }
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
                            Text { text: out.modelData.label + "  ·  " + out.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
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
                    ListRow {
                        Layout.fillWidth: true
                        icon: "preferences-desktop-display"
                        title: "Display settings…"
                        subtitle: "resolution, refresh rate, rotation, arrangement"
                        onClicked: { Ui.expanded = "settings"; Ui.settingsCat = "displays"; }
                    }
                }

                // sending a file over Bluetooth: to which paired device
                ColumnLayout {
                    visible: Ui.expanded === "btsend" && BtSend.file !== ""
                    Layout.fillWidth: true
                    spacing: 2
                    SectionTitle { text: "Send " + BtSend.file.split("/").pop() + " to" }
                    Repeater {
                        model: BtSend.devices
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: modelData.icon || "bluetooth-active"
                            title: modelData.name || modelData.address
                            subtitle: BtSend.busy && BtSend.target === (modelData.name || modelData.address) ? "Sending…" : (modelData.connected ? "Connected" : "Paired")
                            onClicked: BtSend.sendTo(modelData)
                        }
                    }
                }

                // screen recording: what and with which sound
                ColumnLayout {
                    visible: Ui.expanded === "record"
                    Layout.fillWidth: true
                    spacing: 6
                    SectionTitle { text: "Screen recording" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [{ label: "Focused screen", v: "screen" }, { label: "Part of the screen", v: "region" }]
                            Choice {
                                required property var modelData
                                text: modelData.label
                                selected: Settings.data.recordArea === modelData.v
                                onClicked: Settings.data.recordArea = modelData.v
                            }
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [{ label: "No sound", v: "none" }, { label: "Computer sound", v: "desktop" }, { label: "Microphone", v: "mic" }]
                            Choice {
                                required property var modelData
                                text: modelData.label
                                selected: Settings.data.recordSound === modelData.v
                                onClicked: Settings.data.recordSound = modelData.v
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: Ui.expanded === "focus"
                    Layout.fillWidth: true
                    spacing: 2
                    SectionTitle { text: "Focus" }
                    ListRow {
                        Layout.fillWidth: true
                        icon: "window-close"
                        title: "Off"
                        selected: !Focus.on
                        onClicked: Settings.data.focusMode = ""
                    }
                    Repeater {
                        model: Focus.modes
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: modelData.icon || "weather-clear-night"
                            title: modelData.name
                            subtitle: [modelData.schedule && modelData.schedule.on ? modelData.schedule.from + "–" + modelData.schedule.to : "",
                                       (modelData.allow || []).length ? "allows " + modelData.allow.join(", ") : "notifications held",
                                       modelData.nightLight ? "night light" : ""].filter(x => x).join(" · ")
                            trailing: Focus.active === modelData.name ? (Settings.data.focusMode === "" ? "scheduled" : "on") : ""
                            selected: Focus.active === modelData.name
                            onClicked: Focus.set(modelData.name)
                        }
                    }
                }

                ColumnLayout {
                    visible: Ui.expanded === "phone" && Phone.available
                    Layout.fillWidth: true
                    spacing: 2
                    onVisibleChanged: if (visible) Phone.search()
                    SectionTitle {
                        text: "Phones · KDE Connect"
                        IconButton { icon: "view-refresh"; size: 24; Accessible.name: "Search again"; onClicked: Phone.search() }
                    }
                    Repeater {
                        model: Phone.devices
                        ColumnLayout {
                            id: devRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 2
                            ListRow {
                                Layout.fillWidth: true
                                icon: "phone"
                                title: devRow.modelData.name
                                subtitle: devRow.modelData.paired ? (devRow.modelData.reachable ? "Connected" : "Paired · not nearby") : "Nearby · click to pair"
                                selected: devRow.modelData.paired && devRow.modelData.reachable
                                onClicked: if (!devRow.modelData.paired) Phone.pair(devRow.modelData.id)
                                IconButton {
                                    visible: devRow.modelData.paired
                                    icon: "edit-delete"
                                    size: 24
                                    Accessible.name: "Unpair " + devRow.modelData.name
                                    onClicked: Phone.unpair(devRow.modelData.id)
                                }
                            }
                            RowLayout {
                                visible: devRow.modelData.paired && devRow.modelData.reachable
                                Layout.leftMargin: 40
                                spacing: 6
                                Button { text: "Ring"; onClicked: Phone.ring(devRow.modelData.id) }
                                Button { text: "Ping"; onClicked: Phone.ping(devRow.modelData.id) }
                                Button { text: "Send clipboard"; onClicked: Phone.sendClipboard(devRow.modelData.id) }
                            }
                        }
                    }
                    Text {
                        visible: Phone.devices.length === 0
                        Layout.fillWidth: true
                        text: "No phone found. Open KDE Connect on the phone, on the same Wi-Fi, then search again."
                        color: Theme.dim
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                    }
                }

                RowLayout {
                    visible: Ui.expanded === "timer"
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [15, 25, 45, 60]
                        Choice {
                            required property int modelData
                            text: modelData + " min"
                            selected: FocusTimer.running && FocusTimer.total === modelData * 60
                            onClicked: FocusTimer.start(modelData)
                        }
                    }
                    Choice { visible: FocusTimer.running; text: "Stop"; onClicked: FocusTimer.stop() }
                }

                ColumnLayout {
                    visible: Ui.expanded === "access"
                    Layout.fillWidth: true
                    spacing: 8
                    SectionTitle { text: "Accessibility" }
                    SwitchRow { Layout.fillWidth: true; text: "Screen reader"; hint: Access.hasOrca ? "Orca reads the screen aloud" : "install orca"; checked: Settings.data.screenReader; onToggled: on => Settings.data.screenReader = on }
                    SwitchRow { Layout.fillWidth: true; text: "Large text"; hint: "the shell and apps, 125 %"; checked: Settings.data.largeText; onToggled: on => Settings.data.largeText = on }
                    SwitchRow { Layout.fillWidth: true; text: "High contrast"; checked: Settings.data.highContrast; onToggled: on => Settings.data.highContrast = on }
                    SwitchRow { Layout.fillWidth: true; text: "Reduce motion"; checked: Settings.data.reduceMotion; onToggled: on => Settings.data.reduceMotion = on }
                    SwitchRow { Layout.fillWidth: true; text: "Mono audio"; hint: "both ears hear everything"; checked: Settings.data.monoAudio; onToggled: on => Settings.data.monoAudio = on }
                    SwitchRow { Layout.fillWidth: true; text: "Screen keyboard"; checked: Osk.shown; onToggled: on => { if (on !== Osk.shown) Osk.toggle(); } }
                }

                // ---- quick notes ---------------------------------------------------
                SectionTitle { Layout.fillWidth: true; text: "Notes" }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Math.max(64, notes.contentHeight + 20)
                    radius: Theme.radiusSmall
                    color: Theme.hover
                    border.width: notes.activeFocus ? 1 : 0
                    border.color: Theme.accentLine
                    TextEdit {
                        id: notes
                        anchors.fill: parent
                        anchors.margins: 10
                        text: QuickNotes.text
                        color: Theme.text
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.accentInk
                        wrapMode: TextEdit.Wrap
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                        onTextChanged: if (activeFocus) QuickNotes.set(text)
                        Text {
                            visible: notes.text === ""
                            text: "Jot something down — saved to Documents/Notes/quick.md"
                            color: Theme.faint
                            font: notes.font
                        }
                    }
                }

                // ---- screen time -------------------------------------------------
                ColumnLayout {
                    visible: Settings.data.screenTime && ScreenTime.todayTotal >= 60
                    Layout.fillWidth: true
                    spacing: 6
                    SectionTitle { text: "Screen time today · " + ScreenTime.label(ScreenTime.todayTotal) }
                    Repeater {
                        model: ScreenTime.top
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                Layout.preferredWidth: 110
                                text: modelData.app
                                color: Theme.text
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 11 * Theme.fontScale
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 6
                                radius: 3
                                color: Theme.hover
                                Rectangle {
                                    width: parent.width * modelData.seconds / Math.max(1, ScreenTime.top[0].seconds)
                                    height: parent.height
                                    radius: 3
                                    color: Theme.accent
                                }
                            }
                            Text {
                                Layout.preferredWidth: 70
                                horizontalAlignment: Text.AlignRight
                                text: ScreenTime.label(modelData.seconds)
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 10 * Theme.fontScale
                            }
                        }
                    }
                }

                // ---- shelf: the newest screenshots, recordings, downloads -------
                ColumnLayout {
                    visible: Shelf.items.length > 0
                    Layout.fillWidth: true
                    spacing: 4
                    Component.onCompleted: Shelf.refresh()
                    Connections { target: Ui; function onControlCenterChanged() { if (Ui.controlCenter) Shelf.refresh(); } }
                    SectionTitle { text: "Shelf" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: Shelf.items.filter(x => x.image).slice(0, 6)
                            ClippingRectangle {
                                id: shelfItem
                                required property var modelData
                                width: 120
                                height: 72
                                radius: 10
                                color: Theme.hover
                                Image {
                                    anchors.fill: parent
                                    source: "file://" + shelfItem.modelData.path
                                    sourceSize: Qt.size(240, 144)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    // right-click: share it (phone, Bluetooth, nearby, email, clipboard)
                                    onClicked: e => {
                                        if (e.button === Qt.RightButton) { Ui.closeAll(); Share.open(shelfItem.modelData.path); }
                                        else Qt.openUrlExternally("file://" + shelfItem.modelData.path);
                                    }
                                }
                            }
                        }
                    }
                    Repeater {
                        model: Shelf.items.filter(x => !x.image).slice(0, 4)
                        ListRow {
                            id: shelfFile
                            required property var modelData
                            Layout.fillWidth: true
                            icon: /\.(mp4|mkv|webm)$/i.test(modelData.name) ? "video-x-generic" : "text-x-generic"
                            title: modelData.name
                            onClicked: Qt.openUrlExternally("file://" + modelData.path)
                            IconButton {
                                icon: "emblem-shared"
                                size: 24
                                Accessible.name: "Share " + shelfFile.modelData.name
                                onClicked: { Ui.closeAll(); Share.open(shelfFile.modelData.path); }
                            }
                        }
                    }
                }

                // ---- drives ------------------------------------------------------
                ColumnLayout {
                    id: drivesList
                    visible: Drives.drives.length > 0
                    Layout.fillWidth: true
                    spacing: 2
                    SectionTitle { text: "Drives" }
                    property string asking: ""          // the locked drive whose passphrase is being typed
                    Repeater {
                        model: Drives.drives
                        ColumnLayout {
                            id: driveRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 2
                            ListRow {
                                Layout.fillWidth: true
                                icon: driveRow.modelData.luks ? (driveRow.modelData.locked ? "changes-prevent" : "changes-allow") : "drive-removable-media"
                                title: driveRow.modelData.label
                                subtitle: driveRow.modelData.size + (driveRow.modelData.locked ? " · locked — click to unlock"
                                    : driveRow.modelData.mount ? " · " + driveRow.modelData.mount : " · not mounted")
                                onClicked: driveRow.modelData.locked ? drivesList.asking = driveRow.modelData.dev
                                    : driveRow.modelData.mount ? Drives.open(driveRow.modelData) : Drives.mount(driveRow.modelData)
                                IconButton {
                                    icon: "media-eject"
                                    size: 26
                                    Accessible.name: "Eject " + driveRow.modelData.label
                                    onClicked: Drives.eject(driveRow.modelData)
                                }
                            }
                            TextField {
                                Layout.fillWidth: true
                                visible: driveRow.modelData.locked && drivesList.asking === driveRow.modelData.dev
                                placeholder: Drives.unlockError || "Passphrase for " + driveRow.modelData.label
                                secret: true
                                onAccepted: { Drives.unlock(driveRow.modelData, text); text = ""; }
                            }
                        }
                    }
                }

                // ---- calendar --------------------------------------------------
                Calendar {
                    Layout.fillWidth: true
                    today: clock.date
                }
                // what is coming, from the person's calendars (Agenda: EDS)
                ColumnLayout {
                    Connections { target: Ui; function onControlCenterChanged() { if (Ui.controlCenter) Agenda.refresh(); } }
                    visible: Agenda.upcoming.length > 0
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: Agenda.upcoming
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "x-office-calendar"
                            title: modelData.summary
                            subtitle: Agenda.when(modelData) + (modelData.location ? " · " + modelData.location : "")
                            onClicked: { Ui.closeAll(); Agenda.openCalendar(); }
                        }
                    }
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
                                font.pixelSize: 13 * Theme.fontScale
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: win.player ? win.player.trackArtist : ""
                                color: Theme.dim
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 11 * Theme.fontScale
                            }
                            // the output level over the last second and a half
                            Row {
                                id: meter
                                spacing: 2
                                height: 14
                                property var history: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
                                PwNodePeakMonitor {
                                    id: outLevel
                                    node: Audio.sink
                                    enabled: win.visible && win.player !== null && win.player.isPlaying
                                }
                                Timer {
                                    interval: 80
                                    running: outLevel.enabled
                                    repeat: true
                                    onTriggered: meter.history = meter.history.slice(1).concat([Math.min(1, outLevel.peak * 1.5)])
                                }
                                Repeater {
                                    model: meter.history
                                    Rectangle {
                                        required property real modelData
                                        width: 4
                                        height: Math.max(2, modelData * meter.height)
                                        anchors.bottom: parent ? parent.bottom : undefined
                                        radius: 2
                                        color: Theme.alpha(Theme.accent, 0.4 + modelData * 0.6)
                                    }
                                }
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
                    IconButton { visible: Notifs.count > 1; icon: "chat-message-new"; size: 26; onClicked: { Ui.closeAll(); Notifs.summarize(); } }
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
                    font.pixelSize: 12 * Theme.fontScale
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
                                font.pixelSize: 11 * Theme.fontScale
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
