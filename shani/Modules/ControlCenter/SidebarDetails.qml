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
    spacing: Theme.px(14)

    ColumnLayout {
        id: wifiList
        visible: Ui.expanded === "wifi" && Net.hasWifi
        Layout.fillWidth: true
        spacing: 2
        onVisibleChanged: Net.scan(visible)
        property string pending: ""     // network waiting for a password
        property string failed: ""      // the network that failed to connect
        property string failedReason: "" // friendly copy + one next step for that failure
        property bool hiddenOpen: false
        property bool hiddenDetailsOpen: false  // raw nmcli error only on request

        // Quickshell's ConnectionFailReason is a numeric enum (1 = NoSecrets,
        // 3 = supplicant failed, 4 = auth timeout, 5 = SSID not found); message
        // strings are also recognised so the copy survives a backend change.
        function failureText(reason) {
            const r = String(reason);
            if (r === "1" || /secret|password|passphrase|psk|key/i.test(r))
                return Tr.t("Wrong password — check it and try again");
            if (r === "3" || /supplicant|802\.1x|eap|rejected/i.test(r))
                return Tr.t("Sign-in was rejected (802.1X) — check the username and password");
            if (r === "4" || r === "5" || /timeout|range|not found|lost|ssid/i.test(r))
                return Tr.t("Network out of range — move closer and try again");
            if (/dhcp|lease|address/i.test(r))
                return Tr.t("Couldn't get an address from the router — try again");
            if (r === "2" || /disconnect/i.test(r))
                return Tr.t("Connection dropped — try again");
            return Tr.t("Couldn't connect — try again");
        }

        SectionTitle {
            text: Tr.t("Wi-Fi networks")
            IconButton { icon: "view-paged"; size: Theme.px(24); visible: Net.activeWifi !== null; Accessible.name: Tr.t("Share this Wi-Fi as a QR code"); onClicked: { Ui.closeAll(); Qr.shareWifi(); } }
            IconButton { icon: "preferences-system"; tip: Tr.t("Network settings"); size: Theme.px(24); onClicked: { Ui.closeAll(); Net.editConnections(); } }
        }
        // a sign-in page in the way of the internet (a hotel's, a café's)
        Button {
            visible: Net.portal
            Layout.fillWidth: true
            text: Tr.t("Sign in to this network")
            onClicked: { Ui.closeAll(); Net.openPortal(); }
        }
        Repeater {
            model: Net.networks
            ColumnLayout {
                id: netRow
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.px(4)
                readonly property bool secured: modelData.security !== WifiSecurityType.Open
                ListRow {
                    Layout.fillWidth: true
                    icon: modelData.signalStrength > 0.75 ? "network-wireless-signal-excellent" : modelData.signalStrength > 0.5 ? "network-wireless-signal-good" : modelData.signalStrength > 0.25 ? "network-wireless-signal-ok" : "network-wireless-signal-weak"
                    title: modelData.name
                    subtitle: modelData.connected ? "Connected" : modelData.stateChanging ? "Connecting…"
                        : wifiList.failed === modelData.name ? (wifiList.failedReason || Tr.t("Couldn't connect — try again"))
                        : (modelData.known ? "Saved" : netRow.secured ? "" : "Open network")
                    selected: modelData.connected
                    onClicked: {
                        wifiList.failed = "";
                        wifiList.failedReason = "";
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
                        size: Theme.px(24)
                        Accessible.name: "Forget " + netRow.modelData.name
                        onClicked: netRow.modelData.forget()
                    }
                }
                // a refused password: ask again, in place
                Connections {
                    target: netRow.modelData
                    function onConnectionFailed(reason) {
                        wifiList.failed = netRow.modelData.name;
                        wifiList.failedReason = wifiList.failureText(reason);
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
            icon: "view-conceal"
            title: Tr.t("Hidden network…")
            subtitle: Net.hiddenStatus === "connecting" ? "Connecting…" : Net.hiddenStatus.startsWith("failed") ? Net.hiddenStatus.slice(8) : ""
            onClicked: wifiList.hiddenOpen = !wifiList.hiddenOpen
        }
        // the raw nmcli line is useful for bug reports, but not as a status line
        ListRow {
            visible: Net.hiddenStatus.startsWith("failed") && Net.hiddenRaw !== ""
            Layout.fillWidth: true
            icon: "dialog-information"
            title: Tr.t("Show error details")
            onClicked: wifiList.hiddenDetailsOpen = !wifiList.hiddenDetailsOpen
        }
        Text {
            visible: wifiList.hiddenDetailsOpen && Net.hiddenRaw !== ""
            Layout.fillWidth: true
            Layout.leftMargin: Theme.px(40)
            text: Net.hiddenRaw
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
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
        id: btPanel
        visible: Ui.expanded === "bluetooth" && sidebar.bt !== null
        Layout.fillWidth: true
        spacing: 2
        property bool discoverWanted: false     // explicit opt-in, off by default
        property int discoverLeft: 0            // seconds left in the 2-minute window
        // searching while the panel is open is harmless; discoverability is not
        onVisibleChanged: if (sidebar.bt) sidebar.bt.discovering = visible && sidebar.bt.enabled
        function setDiscoverable(on) {
            discoverWanted = on;
            discoverLeft = on ? 120 : 0;
            if (sidebar.bt) sidebar.bt.discoverable = on;
        }
        Timer {
            id: discoverTimer
            interval: 1000
            repeat: true
            running: btPanel.discoverLeft > 0
            onTriggered: {
                btPanel.discoverLeft--;
                if (btPanel.discoverLeft <= 0 && sidebar.bt) {
                    sidebar.bt.discoverable = false;
                    btPanel.discoverWanted = false;
                }
            }
        }
        SectionTitle {
            text: sidebar.bt && sidebar.bt.discovering ? "Bluetooth · searching" : "Bluetooth"
        }
        SwitchRow {
            Layout.fillWidth: true
            enabled: sidebar.bt && sidebar.bt.enabled
            text: Tr.t("Discoverable for 2 minutes")
            hint: btPanel.discoverWanted ? Tr.t("Others can find this computer for %1 s more").arg(btPanel.discoverLeft)
                                 : Tr.t("Off — others cannot find this computer")
            checked: btPanel.discoverWanted
            onToggled: on => setDiscoverable(on)
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
                    size: Theme.px(24)
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
        EmptyState {
            Layout.fillWidth: true
            visible: !Net.hasTailscale
            icon: "network-vpn"
            title: Tr.t("No VPN configured")
            subtitle: Tr.t("Add one in Settings → Network")
        }
        ListRow {
            Layout.fillWidth: true
            visible: Net.hasTailscale
            icon: "network-vpn"
            title: Tr.t("Tailscale")
            subtitle: Net.tailscaleNote || (Net.tailscaleUp ? "Connected" : "")
            selected: Net.tailscaleUp
            onClicked: Net.setTailscale(!Net.tailscaleUp)
        }
        // where everything leaves from: one of the tailnet's exit nodes, or none
        Text {
            visible: Net.tailscaleUp && Net.exitNodes.length > 0
            Layout.fillWidth: true
            Layout.topMargin: Theme.px(4)
            text: Tr.t("Exit node")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        ListRow {
            visible: Net.tailscaleUp && Net.exitNodes.length > 0
            Layout.fillWidth: true
            icon: "network-wired"
            title: Tr.t("None - straight out")
            selected: !Net.exitNodes.some(n => n.on)
            onClicked: Net.setExitNode("")
        }
        Repeater {
            model: Net.tailscaleUp ? Net.exitNodes : []
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: "network-vpn"
                title: modelData.name
                subtitle: modelData.online ? modelData.ip : Tr.t("Offline")
                enabled: modelData.online
                selected: modelData.on
                onClicked: Net.setExitNode(modelData.ip)
            }
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
        spacing: Theme.px(6)
        onVisibleChanged: if (visible) Displays.refresh()
        SectionTitle { text: Tr.t("Displays") }
        Repeater {
            model: Displays.outputs
            ColumnLayout {
                id: out
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text { text: out.modelData.label + "  ·  " + out.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
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
        SectionTitle { text: Tr.t("Send %1 to").arg(BtSend.file.split("/").pop()) }
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
        spacing: Theme.px(6)
        SectionTitle { text: Tr.t("Screen recording") }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(6)
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
            spacing: Theme.px(6)
            Repeater {
                model: [{ label: Tr.t("No sound"), v: "none" }, { label: Tr.t("Computer sound"), v: "desktop" }, { label: Tr.t("Microphone"), v: "mic" }, { label: Tr.t("Both"), v: "both" }]
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: Settings.data.recordSound === modelData.v
                    onClicked: Settings.data.recordSound = modelData.v
                }
            }
        }
    }

    // Do Not Disturb, for how long (after macOS and Android): it ends by itself
    ColumnLayout {
        visible: Ui.expanded === "dnd"
        Layout.fillWidth: true
        spacing: 2
        SectionTitle { text: Tr.t("Do Not Disturb") }
        ListRow { Layout.fillWidth: true; icon: "alarm"; title: Tr.t("For 1 hour")
            onClicked: Notifs.setDndUntil(Date.now() + 3600000) }
        ListRow {
            visible: Notifs.meetingNow !== null
            Layout.fillWidth: true; icon: "x-office-calendar"
            title: Tr.t("Until this meeting ends")
            subtitle: Notifs.meetingNow ? Notifs.meetingNow.summary + " · " + Qt.formatDateTime(new Date(Notifs.meetingNow.end * 1000), Settings.data.use24h ? "HH:mm" : "h:mm AP") : ""
            onClicked: Notifs.setDndUntil(Notifs.meetingNow.end * 1000)
        }
        ListRow { Layout.fillWidth: true; icon: "weather-clear-night"; title: Tr.t("Until tomorrow morning"); subtitle: Tr.t("8:00")
            onClicked: Notifs.setDndUntil(Notifs.tomorrowMorning()) }
        ListRow { Layout.fillWidth: true; icon: "notifications-disabled"; title: Tr.t("Until I turn it off")
            selected: Notifs.dnd && Settings.data.dndUntil === 0
            onClicked: Notifs.setDnd(true) }
        ListRow { visible: Notifs.dnd; Layout.fillWidth: true; icon: "window-close"; title: Tr.t("Turn it off now")
            onClicked: Notifs.setDnd(false) }
    }

    // a screenshot on a timer: time to open the menu or tooltip it is for
    ColumnLayout {
        visible: Ui.expanded === "screenshot"
        Layout.fillWidth: true
        spacing: 2
        SectionTitle { text: Tr.t("Screenshot") }
        Repeater {
            model: [3, 10]
            ListRow {
                required property int modelData
                Layout.fillWidth: true
                icon: "alarm"
                title: Tr.t("Whole screen in %1 seconds").arg(modelData)
                onClicked: { Ui.closeAll(); Screenshots.later(modelData); }
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

    // Connecting a phone uses what the phone already has: Bluetooth pairing, or
    // adb over Wi-Fi debugging (pairing code or QR). Nothing is installed on it.
    ColumnLayout {
        id: phoneDetails
        visible: Ui.expanded === "phone"
        Layout.fillWidth: true
        spacing: 2
        property string connectKind: "bluetooth"  // bluetooth | android
        property string pairAddress: ""
        property string pairCode: ""

        onVisibleChanged: if (visible) { Devices.refresh(); Link.refresh(); }
        SectionTitle {
            text: Tr.t("Phones")
            IconButton { icon: "view-refresh"; size: Theme.px(24); Accessible.name: Tr.t("Look for phones again"); onClicked: { Devices.refresh(); Link.refresh(); } }
        }
        Repeater {
            model: Link.devices
            ColumnLayout {
                id: devRow
                required property var modelData
                readonly property var linkDev: Link.devices.find(d => d.id === devRow.modelData.id)
                Layout.fillWidth: true
                spacing: 2
                ListRow {
                    Layout.fillWidth: true
                    icon: "phone"
                    title: devRow.modelData.name || devRow.modelData.id
                    subtitle: devRow.modelData.reachable ? Tr.t("Connected")
                        : devRow.modelData.paired ? Tr.t("Paired · not nearby") : Tr.t("Nearby")
                    trailing: Phone.batteryText(devRow.linkDev)
                    selected: devRow.modelData.paired && devRow.modelData.reachable
                    onClicked: Ui.openDevices()
                }
            }
        }
        EmptyState {
            visible: Link.devices.length === 0
            icon: "phone"
            title: Tr.t("No phone connected yet")
            subtitle: Tr.t("Pair one below with Bluetooth or Wi-Fi debugging")
        }
        SettingsSection {
            Layout.fillWidth: true
            title: Tr.t("Connect a phone")
            hint: Tr.t("Both ways use what the phone already has. Nothing to install on it.")
            Picks {
                label: Tr.t("How to connect")
                options: [
                    { label: Tr.t("Bluetooth"), value: "bluetooth" },
                    { label: Tr.t("Wi-Fi debugging"), value: "android" }
                ]
                current: phoneDetails.connectKind
                onPicked: v => phoneDetails.connectKind = v
            }
            ColumnLayout {
                visible: phoneDetails.connectKind === "bluetooth"
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("On the phone, turn on Bluetooth and leave its Settings screen open. Then pick the phone here.")
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Repeater {
                    model: Bluetooth.devices.values.slice().sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired))
                    ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        icon: modelData.icon || "bluetooth-active"
                        title: modelData.name || modelData.address
                        subtitle: modelData.connected ? Tr.t("Connected") : modelData.pairing ? Tr.t("Pairing…") : modelData.paired ? Tr.t("Paired") : Tr.t("Available")
                        selected: modelData.connected
                        onClicked: {
                            if (modelData.paired) modelData.connect();
                            else Devices.connect("bluetooth", modelData.address);
                        }
                    }
                }
                EmptyState {
                    visible: Bluetooth.devices.values.length === 0
                    icon: "bluetooth-active"
                    title: Tr.t("No Bluetooth devices nearby")
                    subtitle: Tr.t("Turn Bluetooth on here and on the phone, then look again")
                }
            }
            ColumnLayout {
                visible: phoneDetails.connectKind === "android"
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("On the phone, open Settings → Developer options → Wireless debugging. Pair it with a code or a QR code; it then connects without a cable.")
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                ColumnLayout {
                    visible: phoneDetails.pairKind === "code"
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    TextField {
                        Layout.fillWidth: true
                        label: Tr.t("Address")
                        placeholder: Tr.t("The address shown on the phone, like 192.168.1.20:37099")
                        text: phoneDetails.pairAddress
                        onTextChanged: phoneDetails.pairAddress = text
                    }
                    TextField {
                        Layout.fillWidth: true
                        label: Tr.t("Code")
                        placeholder: Tr.t("The six-digit code shown on the phone")
                        text: phoneDetails.pairCode
                        onTextChanged: phoneDetails.pairCode = text
                    }
                    Button {
                        text: Tr.t("Pair over Wi-Fi")
                        kind: "primary"
                        enabled: !Devices.busy && phoneDetails.pairAddress.trim() !== "" && phoneDetails.pairCode.trim() !== ""
                        onClicked: Devices.connect("android", phoneDetails.pairAddress.trim(), phoneDetails.pairCode.trim())
                    }
                }
                BusyNote { visible: Devices.busy; note: Tr.t("Connecting…") }
                InfoBanner {
                    visible: Devices.note !== "" && !Devices.busy
                    Layout.fillWidth: true
                    text: Devices.note
                    tone: "info"
                }
            }
        }
    }

    // the phone's screen in a window (scrcpy), for Android phones adb can see
    ColumnLayout {
        visible: Ui.expanded === "phone" && Mirror.available
        Layout.fillWidth: true
        spacing: Theme.px(4)
        onVisibleChanged: if (visible) Mirror.refresh()
        SectionTitle {
            text: Tr.t("Phone screen")
            IconButton { icon: "view-refresh"; size: Theme.px(24); Accessible.name: Tr.t("Look for phones again"); onClicked: Mirror.refresh() }
        }
        Repeater {
            model: Mirror.devices
            RowLayout {
                id: mRow
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Icon { name: "phone"; size: Theme.px(18); color: Theme.dim }
                Text {
                    Layout.fillWidth: true
                    text: mRow.modelData.name
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                }
                Button { text: Tr.t("Mirror"); onClicked: Mirror.mirror(mRow.modelData.serial, false) }
                Button { visible: !mRow.modelData.wifi; text: Tr.t("Over Wi-Fi"); onClicked: Mirror.mirror(mRow.modelData.serial, true) }
            }
        }
        Text {
            visible: Mirror.devices.length === 0
            Layout.fillWidth: true
            text: Tr.t("Connect an Android phone by USB or Wi-Fi debugging (Developer options), then allow this computer on the phone.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
    }

    SectionTitle {
        visible: Ui.expanded === "timer"
        Layout.fillWidth: true
        text: Tr.t("Focus timer")
    }
    RowLayout {
        visible: Ui.expanded === "timer"
        Layout.fillWidth: true
        spacing: Theme.px(6)
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
        spacing: Theme.px(8)
        SectionTitle { text: Tr.t("Accessibility") }
        SwitchRow { Layout.fillWidth: true; text: Tr.t("Screen reader"); hint: Access.hasOrca ? "Orca reads the screen aloud" : "install orca"; checked: Settings.data.screenReader; onToggled: on => Settings.data.screenReader = on }
        SwitchRow { Layout.fillWidth: true; text: Tr.t("Large text"); hint: Tr.t("the shell and apps, 125 %"); checked: Settings.data.largeText; onToggled: on => Settings.data.largeText = on }
        SwitchRow { Layout.fillWidth: true; text: Tr.t("High contrast"); checked: Settings.data.highContrast; onToggled: on => Settings.data.highContrast = on }
        SwitchRow { Layout.fillWidth: true; text: Tr.t("Reduce motion"); checked: Settings.data.reduceMotion; onToggled: on => Settings.data.reduceMotion = on }
        SwitchRow { Layout.fillWidth: true; text: Tr.t("Mono audio"); hint: Tr.t("both ears hear everything"); checked: Settings.data.monoAudio; onToggled: on => Settings.data.monoAudio = on }
        SwitchRow { Layout.fillWidth: true; text: Tr.t("Screen keyboard"); checked: Osk.shown; onToggled: on => { if (on !== Osk.shown) Osk.toggle(); } }
    }
}
