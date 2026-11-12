// Weather: now, the next 24 hours and the week, for the place chosen in
// Settings (or where this computer is, with location on). Open-Meteo, through
// Services/Weather - the same forecast the sidebar and the lock screen show.
// The place is typed once here or in Settings; °C or °F is a pick.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Weather"
    doc: Settings.data.weatherCity
    visible: Ui.weather
    onGone: Ui.weather = false
    implicitWidth: 640
    implicitHeight: 600

    onVisibleChanged: if (visible) Weather.fetch()

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.weather = false

        ColumnLayout {
            anchors.fill: parent
            spacing: 14

            // ---- the place ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: place
                    Layout.fillWidth: true
                    placeholder: Tr.t("A city — Pune, Berlin, São Paulo…")
                    label: Tr.t("Weather for")
                    text: Settings.data.weatherCity
                    onAccepted: if (text.trim() !== "") { Settings.data.weatherLat = 0; Settings.data.weatherLon = 0; Settings.data.weatherCity = text.trim(); }
                }
                Choice { text: "°C"; selected: !Weather.fahrenheit; onClicked: Settings.data.weatherUnits = "celsius" }
                Choice { text: "°F"; selected: Weather.fahrenheit; onClicked: Settings.data.weatherUnits = "fahrenheit" }
                IconButton { icon: "view-refresh"; size: 30; tip: Tr.t("Refresh"); onClicked: Weather.fetch() }
            }

            EmptyState {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: Weather.summary === ""
                icon: "weather-few-clouds"
                title: Weather.enabled ? Tr.t("Getting the weather…") : Tr.t("Which place?")
                subtitle: Weather.enabled ? Tr.t("It needs the internet (Open-Meteo)") : Tr.t("Type a city above, or turn on location in Settings > Privacy")
            }

            // ---- now ----
            RowLayout {
                Layout.fillWidth: true
                visible: Weather.summary !== ""
                spacing: 18
                Icon { name: Weather.icon; size: 72; color: Theme.accent }
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: Math.round(Weather.temp) + Weather.degree
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 44 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: Weather.describe(Weather.code) + (Weather.forecast.length ? "  ·  " + Math.round(Weather.forecast[0].hi) + "° / " + Math.round(Weather.forecast[0].lo) + "°" : "")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 14 * Theme.fontScale
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // ---- the next hours ----
            SectionTitle { Layout.fillWidth: true; visible: Weather.hourly.length > 0; text: Tr.t("Next hours") }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 92
                visible: Weather.hourly.length > 0
                orientation: ListView.Horizontal
                clip: true
                spacing: 6
                model: Weather.hourly
                delegate: Rectangle {
                    required property var modelData
                    width: 62
                    height: 88
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        Text { Layout.alignment: Qt.AlignHCenter; text: modelData.hour; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
                        Icon { Layout.alignment: Qt.AlignHCenter; name: Weather.iconFor(modelData.code); size: 22; color: Theme.text }
                        Text { Layout.alignment: Qt.AlignHCenter; text: Math.round(modelData.temp) + "°"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale; font.weight: Font.DemiBold }
                    }
                }
            }

            // ---- the week ----
            SectionTitle { Layout.fillWidth: true; visible: Weather.forecast.length > 0; text: Tr.t("This week") }
            ColumnLayout {
                Layout.fillWidth: true
                visible: Weather.forecast.length > 0
                spacing: 2
                Repeater {
                    model: Weather.forecast
                    RowLayout {
                        id: dayRow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        spacing: 12
                        Text { Layout.preferredWidth: 90; text: dayRow.modelData.day; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale }
                        Icon { name: Weather.iconFor(dayRow.modelData.code); size: 20; color: Theme.text }
                        Text { Layout.fillWidth: true; text: Weather.describe(dayRow.modelData.code); color: Theme.dim; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                        Text { text: Math.round(dayRow.modelData.lo) + "°"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale; font.features: { "tnum": 1 } }
                        // the day's range on the week's scale
                        Item {
                            Layout.preferredWidth: 110
                            Layout.preferredHeight: 6
                            readonly property real low: Math.min(...Weather.forecast.map(f => f.lo))
                            readonly property real high: Math.max(...Weather.forecast.map(f => f.hi))
                            readonly property real span: Math.max(1, high - low)
                            Rectangle { anchors.fill: parent; radius: 3; color: Theme.surface3 }
                            Rectangle {
                                x: parent.width * (dayRow.modelData.lo - parent.low) / parent.span
                                width: Math.max(6, parent.width * (dayRow.modelData.hi - dayRow.modelData.lo) / parent.span)
                                height: parent.height
                                radius: 3
                                color: Theme.accent
                            }
                        }
                        Text { text: Math.round(dayRow.modelData.hi) + "°"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale; font.features: { "tnum": 1 } }
                    }
                }
            }
            Item { Layout.fillHeight: true }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Forecast by Open-Meteo")
                color: Theme.faint
                horizontalAlignment: Text.AlignRight
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
        }
    }
}
