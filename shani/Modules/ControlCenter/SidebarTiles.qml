// The control centre's tiles (one section of Sidebar.qml).
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

ColumnLayout {
    required property var sidebar
    spacing: 14
    // a section whose parts are all hidden takes no room (no double gap)
    visible: Array.from(children).some(c => c.visible)

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
            title: Tr.t("Wi-Fi")
            subtitle: Net.activeWifi ? Net.activeWifi.name : (Net.wifiEnabled ? "Not connected" : "Off")
            on: Net.wifiEnabled
            hasDetail: true
            expanded: Ui.expanded === "wifi"
            onToggled: Net.setWifi(!Net.wifiEnabled)
            onDetail: Ui.expanded = Ui.expanded === "wifi" ? "" : "wifi"
        }
        Tile {
            tid: "bluetooth"
            can: sidebar.bt !== null
            icon: sidebar.bt && sidebar.bt.enabled ? "bluetooth-active" : "bluetooth-disabled"
            title: Tr.t("Bluetooth")
            subtitle: {
                if (!sidebar.bt || !sidebar.bt.enabled)
                    return "Off";
                const c = Bluetooth.devices.values.filter(d => d.connected);
                return c.length === 0 ? "On" : c.length === 1 ? c[0].name : c.length + " devices";
            }
            on: sidebar.bt !== null && sidebar.bt.enabled
            hasDetail: true
            expanded: Ui.expanded === "bluetooth"
            onToggled: sidebar.bt.enabled = !sidebar.bt.enabled
            onDetail: Ui.expanded = Ui.expanded === "bluetooth" ? "" : "bluetooth"
        }
        Tile {
            tid: "airplane"
            icon: "airplane-mode"
            title: Tr.t("Airplane mode")
            subtitle: Net.airplane ? "On" : "Off"
            on: Net.airplane
            onToggled: Net.setAirplane(!Net.airplane)
        }
        Tile {
            tid: "mobile"
            can: Net.hasModem
            icon: "network-cellular-signal-good"
            title: Tr.t("Mobile data")
            subtitle: !Net.wwanOn ? "Off" : Modem.modem && Modem.modem.locked ? "SIM locked"
                : (Modem.modem && Modem.modem.operator ? Modem.modem.operator + " · " + Modem.modem.signal + "%" : Net.modemState === "connected" ? "Connected" : "On")
            on: Net.wwanOn
            onToggled: Modem.modem && Modem.modem.locked ? Ui.modemDialog = "pin" : Net.setMobile(!Net.wwanOn)
        }
        Tile {
            tid: "hotspot"
            can: Net.hasWifi
            icon: "network-wireless-hotspot"
            title: Tr.t("Hotspot")
            subtitle: Net.hotspotOn ? "Sharing" : "Off"
            on: Net.hotspotOn
            onToggled: Net.setHotspot(!Net.hotspotOn)
        }
        Tile {
            tid: "vpn"
            can: Net.vpns.length > 0 || Net.hasTailscale
            icon: "network-vpn"
            title: Tr.t("VPN")
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
            title: Tr.t("Do Not Disturb")
            subtitle: Notifs.dnd ? "Only critical" : "Off"
            on: Notifs.dnd
            onToggled: Notifs.setDnd(!Notifs.dnd)
        }
        Tile {
            tid: "focus"
            icon: Focus.mode ? Focus.mode.icon : "weather-clear-night"
            title: Tr.t("Focus")
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
            title: Tr.t("Focus timer")
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
            title: Tr.t("Caffeine")
            subtitle: Idle.caffeine ? "Staying awake" : "Off"
            on: Idle.caffeine
            onToggled: Idle.setCaffeine(!Idle.caffeine)
        }
        Tile {
            tid: "power"
            icon: Power.profileIcon
            title: Tr.t("Power mode")
            subtitle: Power.profileName
            on: Power.profileName !== "Balanced"
            onToggled: Power.cycleProfile()
        }
        Tile {
            tid: "nightlight"
            can: NightLight.available
            icon: "night-light"
            title: Tr.t("Night light")
            subtitle: NightLight.active ? Settings.data.nightLightTemp + " K" : "Off"
            on: NightLight.active
            onToggled: NightLight.toggle()
        }
        Tile {
            tid: "dark"
            icon: "weather-clear-night"
            title: Tr.t("Dark style")
            subtitle: Appearance.dark ? "On" : "Off"
            on: Appearance.dark
            onToggled: Appearance.toggle()
        }
        Tile {
            tid: "mic"
            can: Audio.source !== null
            icon: Audio.micMuted ? "microphone-sensitivity-muted" : "audio-input-microphone"
            title: Tr.t("Microphone")
            subtitle: Audio.micMuted ? "Muted" : (Privacy.micInUse ? "In use" : "On")
            on: !Audio.micMuted
            onToggled: Audio.toggleMic()
        }
        Tile {
            tid: "camera"
            can: Privacy.cameraPresent
            icon: Privacy.cameraEnabled ? "camera-web" : "camera-disabled"
            title: Tr.t("Camera")
            subtitle: !Privacy.cameraEnabled ? "Off" : (Privacy.cameraInUse ? "In use" : "On")
            on: Privacy.cameraEnabled
            onToggled: Privacy.toggleCamera()
        }
        Tile {
            tid: "photo"
            can: Camera.available && Privacy.cameraEnabled
            icon: "camera-photo"
            title: Tr.t("Photo")
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
            title: Tr.t("Screen record")
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
            title: Tr.t("Screenshot")
            subtitle: Tr.t("Select or window")
            onToggled: {
                Ui.closeAll();
                Niri.action("screenshot");
            }
        }
        Tile {
            tid: "lens"
            can: Lens.available
            icon: "system-search"
            title: Tr.t("Lens")
            subtitle: Tr.t("Read & ask about the screen")
            onToggled: {
                Ui.closeAll();
                Lens.capture();
            }
        }
        Tile {
            tid: "captions"
            icon: "media-view-subtitles"
            title: Tr.t("Live captions")
            subtitle: Captions.on && Captions.source === "speakers" ? "On" : "What is playing"
            on: Captions.on && Captions.source === "speakers"
            onToggled: Captions.toggle()
        }
        Tile {
            tid: "transcribe"
            icon: "audio-input-microphone"
            title: Tr.t("Live transcribe")
            subtitle: Captions.on && Captions.source === "mic" ? "On · saving" : "The room, as text"
            on: Captions.on && Captions.source === "mic"
            onToggled: Captions.transcribe()
        }
        Tile {
            tid: "speak"
            icon: "audio-speakers"
            title: Tr.t("Read aloud")
            subtitle: Speak.speaking ? "Tap to stop" : "Selected text"
            on: Speak.speaking
            onToggled: Speak.speaking ? Speak.stop() : Speak.speakSelection()
        }
        Tile {
            tid: "magnifier"
            icon: "zoom-in"
            title: Tr.t("Magnifier")
            subtitle: Tr.t("Loupe")
            onToggled: {
                Ui.closeAll();
                Ui.magnifier = true;
            }
        }
        Tile {
            tid: "callrecord"
            icon: "call-start"
            title: Tr.t("Call record")
            subtitle: CallRecorder.recording ? CallRecorder.elapsed : "Both sides"
            on: CallRecorder.recording
            onToggled: CallRecorder.toggle()
        }
        Tile {
            tid: "cast"
            can: Cast.available
            icon: "video-display"
            title: Tr.t("Cast")
            subtitle: Tr.t("Miracast")
            onToggled: {
                Ui.closeAll();
                Cast.open();
            }
        }
        Tile {
            tid: "touch"
            icon: "input-touchpad"
            title: Tr.t("Smart touch")
            subtitle: Tr.t("Floating bubble")
            on: Settings.data.assistiveTouch
            onToggled: Settings.data.assistiveTouch = !Settings.data.assistiveTouch
        }
        Tile {
            tid: "colorpicker"
            icon: "color-select"
            title: Tr.t("Color picker")
            subtitle: Tr.t("Copies hex")
            onToggled: {
                Ui.closeAll();
                Quickshell.execDetached(["sh", "-c", "c=$(niri msg pick-color | sed -n 's/^Hex: //p'); [ -n \"$c\" ] && printf %s \"$c\" | wl-copy && notify-send -a 'Color picker' \"$c\" 'Copied to clipboard'"]);
            }
        }
        Tile {
            tid: "rotate"
            can: AutoRotate.available
            icon: AutoRotate.active ? "rotation-allowed" : "rotation-locked"
            title: Tr.t("Auto-rotate")
            subtitle: AutoRotate.active ? "On" : "Locked"
            on: AutoRotate.active
            onToggled: AutoRotate.toggle()
        }
        Tile {
            tid: "flashlight"
            can: Brightness.torch !== ""
            icon: "media-flash"
            title: Tr.t("Flashlight")
            subtitle: Brightness.torchOn ? "On" : "Off"
            on: Brightness.torchOn
            onToggled: Brightness.toggleTorch()
        }
        Tile {
            tid: "display"
            icon: "video-display"
            title: Tr.t("Display")
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
            title: Tr.t("Screen keyboard")
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
            title: Tr.t("Clipboard")
            subtitle: Tr.t("History")
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
            title: Tr.t("Accessibility")
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
            title: Tr.t("Chronoa")
            subtitle: Chronoa.state === "offline" ? "Offline" : "Ask anything"
            on: Chronoa.open
            onToggled: {
                Ui.closeAll();
                Chronoa.open = !Chronoa.open;
            }
        }
    }
}
