pragma Singleton
// Weather for the sidebar header — off until a city is set in the settings,
// because it asks open-meteo.com (no key; it sees the location). The city is
// looked up once (geocoding), then the current weather every 30 minutes.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property bool enabled: Settings.data.weatherCity !== ""
    property real temp: NaN
    property int code: -1
    readonly property string summary: isNaN(temp) ? "" : Math.round(temp) + "°  " + describe(code)
    // WMO weather codes, as Open-Meteo reports them
    function describe(c) {
        return c === 0 ? "Clear" : c <= 2 ? "Partly cloudy" : c === 3 ? "Overcast" : c <= 48 ? "Fog"
             : c <= 57 ? "Drizzle" : c <= 67 ? "Rain" : c <= 77 ? "Snow" : c <= 82 ? "Showers" : c <= 86 ? "Snow showers" : "Thunderstorm";
    }
    readonly property string icon: code < 0 ? "" : code === 0 ? "weather-clear" : code <= 2 ? "weather-few-clouds"
        : code === 3 ? "weather-overcast" : code <= 48 ? "weather-fog" : code <= 67 ? "weather-showers"
        : code <= 77 ? "weather-snow" : code <= 82 ? "weather-showers-scattered" : code <= 86 ? "weather-snow" : "weather-storm"

    function lookUp() {
        if (!enabled)
            return;
        geo.command = ["curl", "-sf", "--max-time", "8", "https://geocoding-api.open-meteo.com/v1/search?count=1&name=" + encodeURIComponent(Settings.data.weatherCity)];
        geo.running = true;
    }
    function fetch() {
        if (!enabled || (Settings.data.weatherLat === 0 && Settings.data.weatherLon === 0))
            return;
        now.command = ["curl", "-sf", "--max-time", "8", "https://api.open-meteo.com/v1/forecast?current=temperature_2m,weather_code&latitude="
            + Settings.data.weatherLat + "&longitude=" + Settings.data.weatherLon];
        now.running = true;
    }
    Connections {
        target: Settings.data
        function onWeatherCityChanged() { root.lookUp(); }
    }
    Process {
        id: geo
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text).results[0];
                    Settings.data.weatherLat = r.latitude;
                    Settings.data.weatherLon = r.longitude;
                    root.fetch();
                } catch (e) {}
            }
        }
    }
    Process {
        id: now
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const c = JSON.parse(text).current;
                    root.temp = c.temperature_2m;
                    root.code = c.weather_code;
                } catch (e) {}
            }
        }
    }
    Timer {
        interval: 30 * 60 * 1000
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: Settings.data.weatherLat === 0 && Settings.data.weatherLon === 0 ? root.lookUp() : root.fetch()
    }
}
