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
    readonly property bool enabled: Settings.data.weatherCity !== "" || (Settings.data.useLocation && (Settings.data.weatherLat !== 0 || Settings.data.weatherLon !== 0))
    // the time zone's city (Asia/Kolkata -> Kolkata): offered in the sidebar, so
    // weather is one click away without typing anything or sharing a location
    property string zoneCity: ""
    Process {
        running: true
        command: ["sh", "-c", "timedatectl show -p Timezone --value 2>/dev/null || readlink /etc/localtime | sed 's|.*zoneinfo/||'"]
        stdout: StdioCollector { onStreamFinished: { const z = text.trim(); root.zoneCity = z.indexOf("/") > 0 ? z.split("/").pop().replace(/_/g, " ") : ""; } }
    }
    property real temp: NaN
    property int code: -1
    readonly property bool fahrenheit: Settings.data.weatherUnits === "fahrenheit"
    readonly property string degree: fahrenheit ? "°F" : "°C"
    readonly property string summary: isNaN(temp) ? "" : Math.round(temp) + degree + "  " + describe(code)
    // 7-day forecast: [{ day, hi, lo, code }] — day is a short weekday ("Mon")
    property var forecast: []
    // next 24 hourly points: [{ hour, temp, code }] — hour is "HH:00"
    property var hourly: []
    // WMO weather codes, as Open-Meteo reports them
    function describe(c) {
        return c === 0 ? "Clear" : c <= 2 ? "Partly cloudy" : c === 3 ? "Overcast" : c <= 48 ? "Fog"
             : c <= 57 ? "Drizzle" : c <= 67 ? "Rain" : c <= 77 ? "Snow" : c <= 82 ? "Showers" : c <= 86 ? "Snow showers" : "Thunderstorm";
    }
    readonly property string icon: code < 0 ? "" : code === 0 ? "weather-clear" : code <= 2 ? "weather-few-clouds"
        : code === 3 ? "weather-overcast" : code <= 48 ? "weather-fog" : code <= 67 ? "weather-showers"
        : code <= 77 ? "weather-snow" : code <= 82 ? "weather-showers-scattered" : code <= 86 ? "weather-snow" : "weather-storm"
    // theme icon for a WMO code (the forecast strip); same mapping as `icon`
    function iconFor(c) {
        if (c < 0) return "";
        return c === 0 ? "weather-clear" : c <= 2 ? "weather-few-clouds"
            : c === 3 ? "weather-overcast" : c <= 48 ? "weather-fog" : c <= 67 ? "weather-showers"
            : c <= 77 ? "weather-snow" : c <= 82 ? "weather-showers-scattered" : c <= 86 ? "weather-snow" : "weather-storm";
    }
    // "2026-11-08" -> "Sun" (new Date("2026-11-08") is UTC, so parse as local)
    function dayName(iso) {
        const p = String(iso || "").split("-").map(Number);
        if (p.length !== 3) return String(iso || "");
        const d = new Date(p[0], p[1] - 1, p[2]);
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()];
    }

    function lookUp() {
        if (!enabled)
            return;
        geo.command = ["curl", "-sf", "--max-time", "8", "https://geocoding-api.open-meteo.com/v1/search?count=1&name=" + encodeURIComponent(Settings.data.weatherCity)];
        geo.running = true;
    }
    function fetch() {
        if (!enabled || (Settings.data.weatherLat === 0 && Settings.data.weatherLon === 0))
            return;
        now.command = ["curl", "-sf", "--max-time", "8", "https://api.open-meteo.com/v1/forecast?current=temperature_2m,weather_code"
            + "&daily=temperature_2m_max,temperature_2m_min,weather_code"
            + "&hourly=temperature_2m,weather_code"
            + "&past_days=0&forecast_days=7"
            + "&temperature_unit=" + (fahrenheit ? "fahrenheit" : "celsius")
            + "&timezone=auto"
            + "&latitude=" + Settings.data.weatherLat
            + "&longitude=" + Settings.data.weatherLon];
        now.running = true;
    }
    Connections {
        target: Settings.data
        function onWeatherCityChanged() { root.lookUp(); }
        function onWeatherUnitsChanged() { root.fetch(); }
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
                    const rootObj = JSON.parse(text);
                    const c = rootObj.current;
                    root.temp = c.temperature_2m;
                    root.code = c.weather_code;
                    // 7-day forecast
                    const d = rootObj.daily;
                    if (d && d.time) {
                        const days = [];
                        const n = Math.min(d.time.length, 7);
                        for (let i = 0; i < n; i++) {
                            days.push({ day: root.dayName(d.time[i]),
                                        hi: d.temperature_2m_max[i],
                                        lo: d.temperature_2m_min[i],
                                        code: d.weather_code[i] });
                        }
                        root.forecast = days;
                    }
                    // next 24 hourly points from now
                    const h = rootObj.hourly;
                    if (h && h.time) {
                        const nowMs = Date.now();
                        const hours = [];
                        // hourly timestamps are in the location's local zone ("YYYY-MM-DDTHH:MM")
                        for (let i = 0; i < h.time.length && hours.length < 24; i++) {
                            const parts = String(h.time[i]).replace("T", " ").split(/[-: ]/).map(Number);
                            const when = new Date(parts[0], parts[1] - 1, parts[2], parts[3] || 0);
                            if (when.getTime() + 30 * 60 * 1000 >= nowMs) {
                                hours.push({ hour: String(h.time[i]).slice(11, 16),
                                             temp: h.temperature_2m[i],
                                             code: h.weather_code[i] });
                            }
                        }
                        if (hours.length === 0) {
                            // no future points labelled yet: take the last 24 of the day
                            const start = Math.max(0, h.time.length - 24);
                            for (let i = start; i < h.time.length; i++) {
                                hours.push({ hour: String(h.time[i]).slice(11, 16),
                                             temp: h.temperature_2m[i],
                                             code: h.weather_code[i] });
                            }
                        }
                        root.hourly = hours;
                    }
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
