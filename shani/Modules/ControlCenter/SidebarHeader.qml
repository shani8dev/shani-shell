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
    id: header
    required property var sidebar
    required property var sidebarClock
    spacing: Theme.px(14)

    RowLayout {
        Layout.fillWidth: true
        Column {
            Layout.fillWidth: true
            Text {
                text: Qt.formatDateTime(sidebarClock.date, Settings.data.use24h ? "HH:mm" : "h:mm AP")
                font.features: { "tnum": 1 }
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(34) * Theme.fontScale
                font.weight: Font.Light
            }
            Text {
                text: Qt.formatDateTime(sidebarClock.date, "dddd, d MMMM")
                      + (Power.hasBattery ? "  ·  " + Math.round(Power.percent * 100) + "%" + (Power.timeLeft ? " · " + Power.timeLeft : "") : "")
                font.features: { "tnum": 1 }
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            // the batteries of the mouse, the headphones, the phone …
            Flow {
                visible: Power.peripherals.length > 0
                width: Theme.px(300)
                spacing: Theme.px(10)
                Repeater {
                    model: Power.peripherals
                    Row {
                        required property var modelData
                        readonly property real pct: modelData.percentage <= 1 ? modelData.percentage * 100 : modelData.percentage
                        spacing: Theme.px(4)
                        Accessible.role: Accessible.StaticText
                        Accessible.name: modelData.model + " battery " + Math.round(pct) + " percent"
                        Icon { name: parent.modelData.iconName || "battery-good"; size: Theme.px(14); color: parent.pct < 15 ? Theme.red : Theme.dim; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: parent.modelData.model.split(" ").slice(0, 2).join(" ") + " " + Math.round(parent.pct) + "%"
                            color: parent.pct < 15 ? Theme.red : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                    }
                }
            }
            // no weather yet: offered in one click, not hidden in Settings - from this
            // computer's location (GeoClue, or a GPS through gpsd) or the time zone's city
            Row {
                visible: Weather.summary === "" && Settings.data.weatherCity === "" && !Settings.data.useLocation
                spacing: Theme.px(8)
                Icon { name: "weather-few-clouds"; size: Theme.px(14); color: Theme.dim; anchors.verticalCenter: parent.verticalCenter }
                Text { text: Tr.t("Weather for"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; anchors.verticalCenter: parent.verticalCenter }
                Choice { text: Tr.t("where I am"); onClicked: { Settings.data.useLocation = true; Location.refresh(); }
                    Hint { text: Tr.t("Uses this computer's location (Wi-Fi, GPS) - you can turn it off in Settings > Privacy") } }
                Choice { visible: Weather.zoneCity !== ""; text: Weather.zoneCity; onClicked: Settings.data.weatherCity = Weather.zoneCity
                    Hint { text: Tr.t("The city of your time zone - no location shared") } }
            }
            Row {
                visible: Weather.summary !== ""
                spacing: Theme.px(6)
                Icon { name: Weather.icon; size: Theme.px(14); color: Theme.dim; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: Weather.summary + "  ·  " + (Settings.data.weatherCity || Tr.t("here"))
                    color: weatherArea.containsMouse ? Theme.text : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                    font.underline: weatherArea.containsMouse
                    // the whole forecast: the Weather app
                    MouseArea { id: weatherArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Ui.openWeather() }
                    KeyFocus { name: Tr.t("Weather") + ": " + parent.text; onActivated: Ui.openWeather() }
                }
            }
            // 7-day strip (Weather.forecast): today + the next six days
            ColumnLayout {
                visible: Weather.summary !== "" && Weather.forecast.length > 0
                Layout.fillWidth: true
                spacing: Theme.px(4)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Repeater {
                        model: Weather.forecast
                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.day
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(10) * Theme.fontScale
                                font.weight: Font.DemiBold
                            }
                            Icon {
                                Layout.alignment: Qt.AlignHCenter
                                name: Weather.iconFor(modelData.code)
                                size: Theme.px(16)
                                color: Theme.text
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: Math.round(modelData.hi) + "°/" + Math.round(modelData.lo) + "°"
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(10) * Theme.fontScale
                                font.features: { "tnum": 1 }
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: Weather.describe(modelData.code) !== ""
                                text: Weather.describe(modelData.code).split(" ")[0]
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: Theme.px(9) * Theme.fontScale
                            }
                        }
                    }
                }
                // next 24 hours (Weather.hourly), a compact strip
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(34)
                    Layout.minimumHeight: Theme.px(34)
                    contentWidth: hourRow.implicitWidth
                    contentHeight: 34
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Row {
                        id: hourRow
                        height: Theme.px(34)
                        spacing: Theme.px(8)
                        Repeater {
                            model: Weather.hourly
                            Column {
                                required property var modelData
                                width: Theme.px(36)
                                spacing: 0
                                Text {
                                    width: Theme.px(36)
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.hour
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(9) * Theme.fontScale
                                    font.features: { "tnum": 1 }
                                }
                                Text {
                                    width: Theme.px(36)
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Math.round(modelData.temp) + "°"
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(11) * Theme.fontScale
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }
                    }
                }
            }
        }
        // help: the tour again, and every shortcut from its last page
        IconButton { icon: "help-about"; tip: Tr.t("Help: a short tour, and every keyboard shortcut"); onClicked: { Ui.closeAll(); Ui.tour = true; } }
        IconButton { icon: "emblem-system"; tip: Tr.t("Settings"); Accessible.name: Tr.t("Settings"); onClicked: Ui.openSettings("") }
        IconButton { icon: "system-lock-screen"; tip: Tr.t("Lock the screen (Super + L)"); onClicked: { Ui.closeAll(); Lock.lock(); } }
        IconButton {
            icon: "system-shutdown"
            tip: Tr.t("Log out, restart or shut down")
            on: Ui.expanded === "power"
            onClicked: Ui.expanded = Ui.expanded === "power" ? "" : "power"
        }
    }

    // up to six (hibernate, UEFI setup where the machine can): three a row
    GridLayout {
        visible: Ui.expanded === "power"
        Layout.fillWidth: true
        columns: 3
        columnSpacing: Theme.px(6)
        rowSpacing: Theme.px(6)
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
    property bool powerWatching: false
    onPowerWatchingChanged: {
        if (powerWatching) TopProcesses.requestWatch();
        else TopProcesses.releaseWatch();
    }
    Binding { target: header; property: "powerWatching"; value: Ui.expanded === "power" && Power.onBattery }
    Component.onDestruction: if (powerWatching) TopProcesses.releaseWatch()
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
                icon: AppIconPath.nameFor(app, "application-x-executable")
                title: app ? app.name : modelData.name
                subtitle: Tr.t("%1% of the processor", Math.round(modelData.cpu))
                onClicked: { Ui.closeAll(); Ui.processes = true; }
            }
        }
    }

    // ShaniOS updates (shani-deploy)
    ListRow {
        Layout.fillWidth: true
        visible: Updates.attention
        icon: Updates.rebootNeeded ? "system-reboot" : "software-update-available"
        title: Updates.summary
        subtitle: Tr.t("Updates")
        selected: true
        onClicked: Ui.openSettings("updates")
    }
}
