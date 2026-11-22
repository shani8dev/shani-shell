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
    readonly property bool enabled: places.length > 0 || Settings.data.weatherCity !== "" || (Settings.data.useLocation && (Settings.data.weatherLat !== 0 || Settings.data.weatherLon !== 0))

    // ---- saved locations: several places, searched and picked in the window --
    property var places: []                // [{ name, lat, lon }]
    property int activePlace: 0
    property var searchResults: []         // [{ name, lat, lon, country }]
    property string searchError: ""
    property int forecastDays: 7           // open-meteo allows up to 16
    property var dayparts: []              // morning / afternoon / evening / night

    FileView {
        id: placesStore
        path: Quickshell.statePath("weather-places.json")
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text()) || {};
                root.places = o.places || [];
                root.activePlace = o.active || 0;
            } catch (e) {}
        }
    }
    Timer { id: placesSave; interval: 800; onTriggered: placesStore.setText(JSON.stringify({ places: root.places, active: root.activePlace })) }
    function currentLat() { return places.length > activePlace ? Number(places[activePlace].lat) : Settings.data.weatherLat; }
    function currentLon() { return places.length > activePlace ? Number(places[activePlace].lon) : Settings.data.weatherLon; }
    function currentName() { return places.length > activePlace ? places[activePlace].name : Settings.data.weatherCity; }
    function placeName() { return places.length > activePlace ? places[activePlace].name : (zoneCity || Settings.data.weatherCity); }
    function selectPlace(i) {
        if (i < 0 || i >= places.length) return;
        activePlace = i;
        placesSave.restart();
        fetch();
    }
    function addPlace(r) {
        if (!r) return;
        const m = places.slice();
        m.push({ name: String(r.name || ""), lat: Number(r.lat) || 0, lon: Number(r.lon) || 0 });
        places = m;
        activePlace = m.length - 1;
        searchResults = [];
        searchError = "";
        placesSave.restart();
        fetch();
    }
    function removePlace(i) {
        if (i < 0 || i >= places.length) return;
        const m = places.slice();
        m.splice(i, 1);
        places = m;
        if (activePlace >= m.length) activePlace = Math.max(0, m.length - 1);
        placesSave.restart();
        fetch();
    }
    function searchCity(q) {
        const query = String(q || "").trim();
        if (query === "") { searchResults = []; searchError = Tr.t("Type a city name"); return; }
        searchError = "";
        geoSearch.command = ["curl", "-sf", "--max-time", "8", "https://geocoding-api.open-meteo.com/v1/search?count=5&name=" + encodeURIComponent(query)];
        geoSearch.running = true;
    }
    Process {
        id: geoSearch
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const rs = (JSON.parse(text) || {}).results || [];
                    root.searchResults = rs.map(r => ({ name: r.name, lat: r.latitude, lon: r.longitude, country: r.country || "" }));
                    root.searchError = root.searchResults.length ? "" : Tr.t("No city found");
                } catch (e) { root.searchError = Tr.t("City search failed"); }
            }
        }
    }

    // four parts of today, from the hourly points already fetched
    function buildDayparts(h) {
        if (!h || !h.time || !h.temperature_2m) return [];
        const out = [
            { part: "morning", label: Tr.t("Morning"), hi: -Infinity, lo: Infinity, code: -1 },
            { part: "afternoon", label: Tr.t("Afternoon"), hi: -Infinity, lo: Infinity, code: -1 },
            { part: "evening", label: Tr.t("Evening"), hi: -Infinity, lo: Infinity, code: -1 },
            { part: "night", label: Tr.t("Night"), hi: -Infinity, lo: Infinity, code: -1 }
        ];
        for (let i = 0; i < h.time.length; i++) {
            const hh = parseInt(String(h.time[i]).slice(11, 13), 10);
            if (!isFinite(hh)) continue;
            const hour = hh < 5 ? hh + 24 : hh;      // night wraps past midnight
            const g = hour >= 21 ? out[3] : hour >= 17 ? out[2] : hour >= 12 ? out[1] : out[0];
            const t = h.temperature_2m[i];
            if (t > g.hi) { g.hi = t; g.code = (h.weather_code || [])[i]; }
            if (t < g.lo) g.lo = t;
        }
        return out.filter(g => isFinite(g.hi));
    }

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
    // current conditions beyond the temperature (Open-Meteo `current=` fields)
    property real feelsLike: NaN
    property real humidity: NaN
    property real wind: NaN
    property real pressure: NaN
    property real visibility: NaN
    property string sunrise: ""
    property string sunset: ""
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
    // ---- advisories ---------------------------------------------------------
    // open-meteo has no official warning feed, so these are read from the next
    // 12 hours of the forecast and say plainly what they are ("likely", not an
    // official warning). Empty when nothing stands out.
    readonly property string advisory: {
        const next = hourly.slice(0, 12);
        if (!next.length) return "";
        const rain = Math.max.apply(null, next.map(h => h.rain || 0));
        const wind = Math.max.apply(null, next.map(h => h.wind || 0));
        const hot = Math.max.apply(null, next.map(h => h.temp));
        if (rain >= 70) return Tr.t("Rain is likely in the next few hours");
        if (wind >= 40) return Tr.t("Strong wind — %1 km/h", Math.round(wind));
        if (!fahrenheit && hot >= 35) return Tr.t("Very hot — %1°", Math.round(hot));
        return "";
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
        geo.command = ["curl", "-sf", "--max-time", "8", "https://geocoding-api.open-meteo.com/v1/search?count=1&name=" + encodeURIComponent(currentName())];
        geo.running = true;
    }
    function fetch() {
        const lat = currentLat(), lon = currentLon();
        if (!enabled || (!lat && !lon))
            return;
        now.command = ["curl", "-sf", "--max-time", "8", "https://api.open-meteo.com/v1/forecast?current=temperature_2m,weather_code,apparent_temperature,relative_humidity_2m,wind_speed_10m,surface_pressure,visibility"
            + "&daily=temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset"
            + "&hourly=temperature_2m,weather_code,precipitation_probability,wind_speed_10m"
            + "&past_days=0&forecast_days=" + forecastDays
            + "&temperature_unit=" + (fahrenheit ? "fahrenheit" : "celsius")
            + "&timezone=auto"
            + "&latitude=" + lat
            + "&longitude=" + lon];
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
                    root.feelsLike = c.apparent_temperature;
                    root.humidity = c.relative_humidity_2m;
                    root.wind = c.wind_speed_10m;
                    root.pressure = c.surface_pressure;
                    root.visibility = c.visibility;
                    // 7-day forecast
                    const d = rootObj.daily;
                    if (d && d.sunrise && d.sunrise.length) {
                        root.sunrise = String(d.sunrise[0]).slice(11, 16);
                        root.sunset = String(d.sunset[0]).slice(11, 16);
                    }
                    if (d && d.time) {
                        const days = [];
                        const n = Math.min(d.time.length, root.forecastDays);
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
                                             code: h.weather_code[i],
                                             rain: (h.precipitation_probability || [])[i] || 0,
                                             wind: (h.wind_speed_10m || [])[i] || 0 });
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
                        root.dayparts = root.buildDayparts(h);
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
        onTriggered: currentLat() === 0 && currentLon() === 0 ? root.lookUp() : root.fetch()
    }
}
