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
    doc: Weather.placeName()
    visible: Ui.weather
    onGone: Ui.weather = false
    implicitWidth: Theme.px(640)
    implicitHeight: Theme.px(640)
    property bool locShown: false
    // a typed city is only saveable once its coordinates are known (a 0,0
    // place made the forecast stop), and only once: a second copy does nothing
    readonly property bool currentCityReady: Settings.data.weatherCity !== ""
        && (Settings.data.weatherLat !== 0 || Settings.data.weatherLon !== 0)
    readonly property bool currentCitySaved: {
        const n = String(Settings.data.weatherCity || "").trim().toLowerCase();
        return n !== "" && Weather.places.some(p => String(p.name || "").trim().toLowerCase() === n);
    }

    onVisibleChanged: if (visible) Weather.fetch()

    // Sparkline wants non-negative numbers: shift the hourly temps so the
    // coldest is 1, keeping the shape of the curve for below-zero weather too.
    readonly property var tempCurve: {
        const t = Weather.hourly.map(h => h.temp);
        if (!t.length) return [];
        const lo = Math.min.apply(null, t);
        return t.map(v => v - lo + 1);
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.weather = false

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(14)

            // ---- an advisory from the next few hours ------------------------
            Rectangle {
                Layout.fillWidth: true
                visible: Weather.advisory !== ""
                implicitHeight: noteCol.implicitHeight + 20
                radius: Theme.radiusSmall
                color: Theme.alpha(Theme.amber, 0.14)
                border.width: 1
                border.color: Theme.alpha(Theme.amber, 0.5)
                ColumnLayout {
                    id: noteCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 2
                    Text {
                        text: Tr.t("Worth knowing")
                        color: Theme.amber
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Weather.advisory
                        color: Theme.text
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: Theme.px(13) * Theme.fontScale
                    }
                }
            }

            // ---- the place ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
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
                IconButton { icon: "view-refresh"; size: Theme.px(30); tip: Tr.t("Refresh"); onClicked: Weather.fetch() }
                IconButton { icon: "view-list"; size: Theme.px(30); tip: Tr.t("Locations"); on: win.locShown; onClicked: win.locShown = !win.locShown }
            }

            // ---- saved locations and in-app city search -----------------------
            Rectangle {
                Layout.fillWidth: true
                visible: win.locShown
                implicitHeight: locCol.implicitHeight + 20
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.border
                ColumnLayout {
                    id: locCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: Theme.px(6)
                    RowLayout {
                        Layout.fillWidth: true
                        TextField {
                            id: citySearch
                            Layout.fillWidth: true
                            placeholder: Tr.t("Search for a city…")
                            label: Tr.t("Add a location")
                            onAccepted: Weather.searchCity(text)
                        }
                        Button { text: Tr.t("Search"); flat: true; onClicked: Weather.searchCity(citySearch.text) }
                    }
                    Text { Layout.fillWidth: true; visible: Weather.searchError !== ""; text: Weather.searchError; color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    Repeater {
                        model: Weather.searchResults
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: modelData.name + (modelData.country ? ", " + modelData.country : ""); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                            Button { text: Tr.t("Add"); flat: true; onClicked: Weather.addPlace(modelData) }
                        }
                    }
                    SectionTitle { Layout.fillWidth: true; text: Tr.t("Saved locations") }
                    Repeater {
                        model: Weather.places
                        RowLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Button { text: modelData.name; flat: true; checked: Weather.activePlace === index; onClicked: Weather.selectPlace(index) }
                            Item { Layout.fillWidth: true }
                            IconButton { icon: "edit-delete"; size: Theme.px(24); Accessible.name: Tr.t("Remove location"); onClicked: Weather.removePlace(index) }
                        }
                    }
                    Text { Layout.fillWidth: true; visible: Weather.places.length === 0; text: Tr.t("No saved locations yet"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    Button { text: Tr.t("Save the current city"); flat: true; enabled: win.currentCityReady && !win.currentCitySaved; onClicked: Weather.addPlace({ name: Settings.data.weatherCity, lat: Settings.data.weatherLat, lon: Settings.data.weatherLon }) }
                }
            }

            EmptyState {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: Weather.summary === ""
                icon: Weather.error !== "" ? "dialog-warning" : "weather-few-clouds"
                title: Weather.error !== "" ? Tr.t("Weather unavailable")
                    : Weather.enabled || Location.running ? Tr.t("Getting the weather…") : Tr.t("Which place?")
                subtitle: Weather.error !== "" ? Weather.error
                    : Weather.enabled ? Tr.t("It needs the internet (Open-Meteo)")
                    : Location.running ? Tr.t("Find my location") + "…"
                    : Location.error !== "" ? Location.error
                    : Tr.t("Type a city above, or turn on location in Settings > Privacy")
            }

            // ---- now ----
            RowLayout {
                Layout.fillWidth: true
                visible: Weather.summary !== ""
                spacing: Theme.px(18)
                Icon { name: Weather.icon; size: Theme.px(72); color: Theme.accent }
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: Math.round(Weather.temp) + Weather.degree
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(44) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: Weather.describe(Weather.code) + (Weather.forecast.length ? "  ·  " + Math.round(Weather.forecast[0].hi) + "° / " + Math.round(Weather.forecast[0].lo) + "°" : "")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(14) * Theme.fontScale
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // ---- the rest of "now" (the API already sends these) ------------
            Text {
                Layout.fillWidth: true
                visible: Weather.summary !== ""
                wrapMode: Text.Wrap
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
                text: [
                    isNaN(Weather.feelsLike) ? "" : Tr.t("Feels like") + " " + Math.round(Weather.feelsLike) + Weather.degree,
                    isNaN(Weather.humidity) ? "" : Tr.t("Humidity") + " " + Math.round(Weather.humidity) + "%",
                    isNaN(Weather.wind) ? "" : Tr.t("Wind") + " " + Math.round(Weather.wind) + " km/h",
                    isNaN(Weather.pressure) ? "" : Tr.t("Pressure") + " " + Math.round(Weather.pressure) + " hPa",
                    isNaN(Weather.visibility) ? "" : Tr.t("Visibility") + " " + Math.round(Weather.visibility / 1000) + " km",
                    Weather.sunrise ? Tr.t("Sun") + " " + Weather.sunrise + " / " + Weather.sunset : ""
                ].filter(s => s !== "").join("   ·   ")
            }

            // ---- the four parts of today -------------------------------------
            RowLayout {
                Layout.fillWidth: true
                visible: Weather.dayparts.length > 0
                spacing: Theme.px(8)
                Repeater {
                    model: Weather.dayparts
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: dpCol.implicitHeight + 16
                        radius: Theme.radiusSmall
                        color: Theme.surface1
                        ColumnLayout {
                            id: dpCol
                            anchors.centerIn: parent
                            spacing: Theme.px(2)
                            Text { Layout.alignment: Qt.AlignHCenter; text: modelData.label; color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                            Icon { Layout.alignment: Qt.AlignHCenter; name: Weather.iconFor(modelData.code); size: Theme.px(20); color: Theme.text }
                            Text { Layout.alignment: Qt.AlignHCenter; text: Math.round(modelData.hi) + "° / " + Math.round(modelData.lo) + "°"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                        }
                    }
                }
            }

            // ---- the next hours ----
            SectionTitle { Layout.fillWidth: true; visible: Weather.hourly.length > 0; text: Tr.t("Next hours") }
            Sparkline {
                Layout.fillWidth: true
                visible: Weather.hourly.length > 1
                values: win.tempCurve
                color: Theme.accent
            }
            ListView {
                reuseItems: true
                cacheBuffer: 400
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(92)
                visible: Weather.hourly.length > 0
                orientation: ListView.Horizontal
                clip: true
                spacing: Theme.px(6)
                model: Weather.hourly
                delegate: Rectangle {
                    required property var modelData
                    width: Theme.px(62)
                    height: Theme.px(88)
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.px(4)
                        Text { Layout.alignment: Qt.AlignHCenter; text: modelData.hour; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                        Icon { Layout.alignment: Qt.AlignHCenter; name: Weather.iconFor(modelData.code); size: Theme.px(22); color: Theme.text }
                        Text { Layout.alignment: Qt.AlignHCenter; text: Math.round(modelData.temp) + "°"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.DemiBold }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            visible: (modelData.rain || 0) > 0
                            text: Math.round(modelData.rain) + "%"
                            color: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            visible: (modelData.wind || 0) > 0
                            text: Math.round(modelData.wind) + " km/h"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(9) * Theme.fontScale
                        }
                    }
                }
            }

            // ---- the week ----
            SectionTitle { Layout.fillWidth: true; visible: Weather.forecast.length > 0; text: Tr.t("This week") }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text { text: Tr.t("Days"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                Repeater {
                    model: [7, 10, 14, 16]
                    Choice {
                        required property int modelData
                        text: String(modelData)
                        selected: Weather.forecastDays === modelData
                        onClicked: { Weather.forecastDays = modelData; Weather.fetch(); }
                    }
                }
                Item { Layout.fillWidth: true }
            }
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
                        Layout.preferredHeight: Theme.px(34)
                        spacing: Theme.px(12)
                        Text { Layout.preferredWidth: Theme.px(90); text: dayRow.modelData.day; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                        Icon { name: Weather.iconFor(dayRow.modelData.code); size: Theme.px(20); color: Theme.text }
                        Text { Layout.fillWidth: true; text: Weather.describe(dayRow.modelData.code); color: Theme.dim; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                        Text { text: Math.round(dayRow.modelData.lo) + "°"; color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.features: { "tnum": 1 } }
                        // the day's range on the week's scale
                        Item {
                            Layout.preferredWidth: Theme.px(110)
                            Layout.preferredHeight: Theme.px(6)
                            readonly property real low: Math.min(...Weather.forecast.map(f => f.lo))
                            readonly property real high: Math.max(...Weather.forecast.map(f => f.hi))
                            readonly property real span: Math.max(1, high - low)
                            Rectangle { anchors.fill: parent; radius: Theme.px(3); color: Theme.surface3 }
                            Rectangle {
                                x: parent.width * (dayRow.modelData.lo - parent.low) / parent.span
                                width: Math.max(6, parent.width * (dayRow.modelData.hi - dayRow.modelData.lo) / parent.span)
                                height: parent.height
                                radius: Theme.px(3)
                                color: Theme.accent
                            }
                        }
                        Text { text: Math.round(dayRow.modelData.hi) + "°"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.features: { "tnum": 1 } }
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
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
        }
    }
}
