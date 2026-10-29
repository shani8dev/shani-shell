// The control centre's detail lists (one section of Sidebar.qml).
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
            text: Tr.t("Wi-Fi networks")
            IconButton { icon: "view-barcode-qr"; size: 24; visible: Net.activeWifi !== null; Accessible.name: Tr.t("Share this Wi-Fi as a QR code"); onClicked: { Ui.closeAll(); Qr.shareWifi(); } }
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
            title: Tr.t("Hidden network…")
            subtitle: Net.hiddenStatus === "connecting" ? "Connecting…" : Net.hiddenStatus.startsWith("failed") ? Net.hiddenStatus.slice(8) : ""
            onClicked: wifiList.hiddenOpen = !wifiList.hiddenOpen
        }
        TextField {
            id: hiddenSsid
            Layout.fillWidth: true
            visible: wifiList.hiddenOpen
            placeholder: Tr.t("Network name")
            onAccepted: hiddenPsk.input.forceActiveFocus()
        }
        TextField {
            id: hiddenPsk
            Layout.fillWidth: true
            visible: wifiList.hiddenOpen
            placeholder: Tr.t("Password (empty for an open network)")
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
        visible: Ui.expanded === "bluetooth" && sidebar.bt !== null
        Layout.fillWidth: true
        spacing: 2
        // while open: searching, and visible to others (so a phone can find this computer)
        onVisibleChanged: if (sidebar.bt) {
            sidebar.bt.discovering = visible && sidebar.bt.enabled;
            sidebar.bt.discoverable = visible && sidebar.bt.enabled;
        }
        SectionTitle {
            text: sidebar.bt && sidebar.bt.discovering ? "Bluetooth · searching" : "Bluetooth"
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
        SectionTitle { text: Tr.t("VPN") }
        ListRow {
            Layout.fillWidth: true
            visible: Net.hasTailscale
            icon: "network-vpn"
            title: Tr.t("Tailscale")
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
        SectionTitle { text: Tr.t("Displays") }
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
            title: Tr.t("Display settings…")
            subtitle: Tr.t("resolution, refresh rate, rotation, arrangement")
            onClicked: Ui.openSettings("displays")
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
        SectionTitle { text: Tr.t("Screen recording") }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [{ label: Tr.t("Focused screen"), v: "screen" }, { label: Tr.t("Part of the screen"), v: "region" }]
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
                model: [{ label: Tr.t("No sound"), v: "none" }, { label: Tr.t("Computer sound"), v: "desktop" }, { label: Tr.t("Microphone"), v: "mic" }]
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
        SectionTitle { text: Tr.t("Focus") }
        ListRow {
            Layout.fillWidth: true
            icon: "window-close"
            title: Tr.t("Off")
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
            text: Tr.t("Phones · KDE Connect")
            IconButton { icon: "view-refresh"; size: 24; Accessible.name: Tr.t("Search again"); onClicked: Phone.search() }
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
                    Button { text: Tr.t("Ring"); onClicked: Phone.ring(devRow.modelData.id) }
                    Button { text: Tr.t("Ping"); onClicked: Phone.ping(devRow.modelData.id) }
                    Button { text: Tr.t("Send clipboard"); onClicked: Phone.sendClipboard(devRow.modelData.id) }
                }
            }
        }
        Text {
            visible: Phone.devices.length === 0
            Layout.fillWidth: true
            text: Tr.t("No phone found. Open KDE Connect on the phone, on the same Wi-Fi, then search again.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: 12 * Theme.fontScale
        }
    }

    // the phone's screen in a window (scrcpy), for Android phones adb can see
    ColumnLayout {
        visible: Ui.expanded === "phone" && Mirror.available
        Layout.fillWidth: true
        spacing: 4
        onVisibleChanged: if (visible) Mirror.refresh()
        SectionTitle {
            text: Tr.t("Phone screen")
            IconButton { icon: "view-refresh"; size: 24; Accessible.name: Tr.t("Look for phones again"); onClicked: Mirror.refresh() }
        }
        Repeater {
            model: Mirror.devices
            RowLayout {
                id: mRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                Icon { name: "phone"; size: 18; color: Theme.dim }
                Text {
                    Layout.fillWidth: true
                    text: mRow.modelData.name
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                }
                Button { text: Tr.t("Mirror"); onClicked: Mirror.mirror(mRow.modelData.serial, false) }
                Button { visible: !mRow.modelData.wifi; text: Tr.t("Over Wi-Fi"); onClicked: Mirror.mirror(mRow.modelData.serial, true) }
            }
        }
        Text {
            visible: Mirror.devices.length === 0
            Layout.fillWidth: true
            text: Tr.t("Connect an Android phone by USB, with USB debugging on (Developer options), and allow this computer on the phone.")
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
        Choice { visible: FocusTimer.running; text: Tr.t("Stop"); onClicked: FocusTimer.stop() }
    }

    ColumnLayout {
        visible: Ui.expanded === "access"
        Layout.fillWidth: true
        spacing: 8
        SectionTitle { text: Tr.t("Accessibility") }
        SwitchRow { Layout.fillWidth: true; text: Tr.t("Screen reader"); hint: Access.hasOrca ? "Orca reads the screen aloud" : "install orca"; checked: Settings.data.screenReader; onToggled: on => Settings.data.screenReader = on }
        SwitchRow { Layout.fillWidth: true; text: Tr.t("Large text"); hint: Tr.t("the shell and apps, 125 %"); checked: Settings.data.largeText; onToggled: on => Settings.data.largeText = on }
        SwitchRow { Layout.fillWidth: true; text: Tr.t("High contrast"); checked: Settings.data.highContrast; onToggled: on => Settings.data.highContrast = on }
        SwitchRow { Layout.fillWidth: true; text: Tr.t("Reduce motion"); checked: Settings.data.reduceMotion; onToggled: on => Settings.data.reduceMotion = on }
        SwitchRow { Layout.fillWidth: true; text: Tr.t("Mono audio"); hint: Tr.t("both ears hear everything"); checked: Settings.data.monoAudio; onToggled: on => Settings.data.monoAudio = on }
        SwitchRow { Layout.fillWidth: true; text: Tr.t("Screen keyboard"); checked: Osk.shown; onToggled: on => { if (on !== Osk.shown) Osk.toggle(); } }
    }
}
