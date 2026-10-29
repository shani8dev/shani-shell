// The control centre's header (one section of Sidebar.qml).
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
    required property var sidebarClock
    spacing: 14

    RowLayout {
        Layout.fillWidth: true
        Column {
            Layout.fillWidth: true
            Text {
                text: Qt.formatDateTime(sidebarClock.date, Settings.data.use24h ? "HH:mm" : "h:mm AP")
                font.features: { "tnum": 1 }
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 34 * Theme.fontScale
                font.weight: Font.Light
            }
            Text {
                text: Qt.formatDateTime(sidebarClock.date, "dddd, d MMMM")
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
        IconButton { icon: "emblem-system"; tip: Tr.t("Settings"); Accessible.name: Tr.t("Settings"); onClicked: Ui.openSettings("") }
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
                { id: "logout", label: Tr.t("Log out"), run: () => Power.logout() },
                { id: "suspend", label: Tr.t("Suspend"), run: () => Power.suspend() },
                { id: "hibernate", label: Tr.t("Hibernate"), run: () => Power.hibernate() },
                { id: "reboot", label: Tr.t("Reboot"), run: () => Power.reboot() },
                { id: "poweroff", label: Tr.t("Power off"), run: () => Power.poweroff() },
                { id: "firmware", label: Tr.t("UEFI setup"), run: () => Power.rebootToFirmware() }
            ].filter(x => (x.id !== "hibernate" || Power.canHibernate) && (x.id !== "firmware" || Power.canFirmwareSetup))
            Button {
                required property var modelData
                Layout.fillWidth: true
                text: sidebar.confirm === modelData.id ? "Sure?" : modelData.label
                kind: sidebar.confirm === modelData.id ? "danger" : "plain"
                onClicked: {
                    // suspend and hibernate resume where they were; the others ask once more
                    if (modelData.id === "suspend" || modelData.id === "hibernate" || sidebar.confirm === modelData.id) {
                        sidebar.confirm = "";
                        Ui.closeAll();
                        modelData.run();
                    } else {
                        sidebar.confirm = modelData.id;
                    }
                }
            }
        }
    }

    // on battery: what is using the most power now (Pantheon's power indicator),
    // by processor use; a click opens the process list, where one can be ended
    Binding { target: TopProcesses; property: "watching"; value: true; when: Ui.expanded === "power" && Power.onBattery }
    ColumnLayout {
        readonly property var heavy: TopProcesses.list.filter(p => p.cpu >= 5).slice(0, 3)
        visible: Ui.expanded === "power" && Power.onBattery && heavy.length > 0
        Layout.fillWidth: true
        spacing: 2
        SectionTitle { Layout.fillWidth: true; text: Tr.t("Using the most power") }
        Repeater {
            model: parent.heavy
            ListRow {
                required property var modelData
                readonly property var app: DesktopEntries.heuristicLookup(modelData.name)
                Layout.fillWidth: true
                icon: app ? app.icon : "application-x-executable"
                title: app ? app.name : modelData.name
                subtitle: Tr.t("%1% of the processor", Math.round(modelData.cpu))
                onClicked: { Ui.closeAll(); Ui.processes = true; }
            }
        }
    }

    // ShaniOS updates (shani-deploy, as Cassini reads it)
    ListRow {
        Layout.fillWidth: true
        visible: Updates.attention
        icon: Updates.rebootNeeded ? "system-reboot" : "software-update-available"
        title: Updates.summary
        subtitle: Tr.t("Open Cassini")
        selected: true
        onClicked: { Ui.closeAll(); !Updates.available && !Updates.rebootNeeded && Updates.firmware.length ? Updates.openFirmware() : Updates.open(); }
    }
}
