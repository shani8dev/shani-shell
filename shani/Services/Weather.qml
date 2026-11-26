pragma Singleton
// Weather for the sidebar header and the Weather window — off until a city is
// set in Settings, because it asks open-meteo.com (no key; it sees the
// location). The city is looked up once (geocoding), then the forecast every
// 30 minutes. The last good values stay on screen when a refresh fails.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ServiceRun.js" as ServiceRun

Singleton {
    id: root
    readonly property bool enabled: places.length > 0 || Settings.data.weatherCity !== "" || (Settings.data.useLocation && (Settings.data.weatherLat !== 0 || Settings.data.weatherLon !== 0))

    // ---- units: the service owns the pick and persists it --------------------
    // Settings still holds the shell-wide copy (sidebar, lock screen); this
    // file makes the choice survive even when that key is reset with Settings.
    property string units: Settings.data.weatherUnits === "fahrenheit" ? "fahrenheit" : "celsius"
    readonly property bool fahrenheit: units === "fahrenheit"
    readonly property string degree: fahrenheit ? "°F" : "°C"
    readonly property string windUnit: fahrenheit ? "mph" : "km/h"
    readonly property string distanceUnit: fahrenheit ? "mi" : "km"
    readonly property int refreshMinutes: 30
    function windValue(v) { return fahrenheit ? Math.round(v * 0.621371) : Math.round(v); }
    function distanceValue(v) { return fahrenheit ? Math.round(v / 1609.344 * 10) / 10 : Math.round(v / 1000); }
    function setUnits(u) {
        const next = u === "fahrenheit" ? "fahrenheit" : "celsius";
        if (next !== root.units) { root.units = next; prefsSave.restart(); }
        if (Settings.data.weatherUnits !== next) Settings.data.weatherUnits = next;
    }
    onUnitsChanged: root.fetch()
    FileView {
        id: prefsStore
        path: Quickshell.statePath("weather-prefs.json")
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text()) || {};
                if (o.units === "celsius" || o.units === "fahrenheit") root.units = o.units;
            } catch (e) {}
        }
    }
    Timer { id: prefsSave; interval: 500; onTriggered: prefsStore.setText(JSON.stringify({ units: root.units })) }

    // ---- saved locations: several places, searched and picked in the window --
    property var places: []                // [{ name, lat, lon }]
    property int activePlace: 0
    property var searchResults: []         // [{ name, lat, lon, country, region, timezone }]
    property string searchError: ""
    property bool searchBusy: false
    property int forecastDays: 7           // open-meteo allows up to 16
    property var dayparts: []              // morning / afternoon / evening / night
    property var alerts: []                // [{ label, detail, level, icon }]

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
        const name = String(r.name || "").trim();
        const lat = Number(r.lat) || 0, lon = Number(r.lon) || 0;
        if (name === "" || (!lat && !lon)) return;
        if (places.some(p => String(p.name || "").trim().toLowerCase() === name.toLowerCase())) {
            searchError = Tr.t("Already saved");
            return;
        }
        const m = places.slice();
        m.push({ name: name, lat: lat, lon: lon });
        places = m;
        activePlace = m.length - 1;
        searchResults = [];
        searchError = "";
        placesSave.restart();
        fetch();
    }
    function renamePlace(i, name) {
        if (i < 0 || i >= places.length) return;
        const n = String(name || "").trim();
        if (n === "") return;
        if (places.some((p, j) => j !== i && String(p.name || "").trim().toLowerCase() === n.toLowerCase())) {
            searchError = Tr.t("Already saved");
            return;
        }
        const m = places.slice();
        m[i] = Object.assign({}, m[i], { name: n });
        places = m;
        searchError = "";
        placesSave.restart();
    }
    function movePlace(i, delta) {
        const j = i + delta;
        if (i < 0 || i >= places.length || j < 0 || j >= places.length) return;
        const m = places.slice();
        const held = m[i];
        m[i] = m[j];
        m[j] = held;
        places = m;
        if (activePlace === i) activePlace = j;
        else if (activePlace === j) activePlace = i;
        placesSave.restart();
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
        searchBusy = true;
        root.run("search", [query]);
        geoSearch.command = ["curl", "-sf", "--max-time", "8", "https://geocoding-api.open-meteo.com/v1/search?count=5&name=" + encodeURIComponent(query)];
        geoSearch.running = true;
    }
    Process {
        id: geoSearch
        stdout: StdioCollector {
            onStreamFinished: {
                root.searchBusy = false;
                try {
                    const rs = (JSON.parse(text) || {}).results || [];
                    root.searchResults = rs.map(r => ({ name: r.name, lat: r.latitude, lon: r.longitude, country: r.country || "",
                                                         region: r.admin1 || "", timezone: r.timezone || "" }));
                    root.searchError = root.searchResults.length ? "" : Tr.t("No city found");
                } catch (e) { root.searchError = Tr.t("City search failed"); }
            }
        }
        onExited: code => {
            root.searchBusy = false;
            if (code !== 0 && root.searchError === "") root.searchError = Tr.t("City search failed");
            root.finished("search", "", code);
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
    property real uvIndex: NaN             // Open-Meteo `current=uv_index`
    property real aqi: NaN                 // US AQI from Open-Meteo's air-quality endpoint
    property real pm25: NaN
    readonly property string summary: isNaN(temp) ? "" : Math.round(temp) + degree + "  " + describe(code)
    readonly property string uvText: isNaN(uvIndex) ? "" : Tr.t("UV %1 · %2", Math.round(uvIndex), uvLevel(uvIndex))
    readonly property string aqiText: isNaN(aqi) ? "" : Tr.t("Air quality %1 · %2", Math.round(aqi), aqiLevel(aqi))
    // 7-day forecast: [{ day, hi, lo, code, rain, wind, uv, sunrise, sunset }]
    property var forecast: []
    // next 24 hourly points: [{ hour, temp, code, rain, wind }] — hour is "HH:00"
    property var hourly: []
    property string error: ""              // "" when the last look-up/fetch worked
    property bool loading: false

    // ---- uniform service status contract ---------------------------------
    // Additive status surface shared with the newer singletons: run() opens
    // the single in-flight guard, finished() closes it and records the last
    // success (note) or failure (error). Exit 127 means the tool is absent.
    property bool busy: false
    property string note: ""               // last successful look-up/fetch
    property string what: ""               // the command currently in flight
    function run(what, args) { return ServiceRun.begin(root, what); }
    function finished(what, text, code) {
        root.busy = false;
        if (code === 127) {
            root.error = Tr.t("The weather service is not installed");
            return false;
        }
        if (code !== 0) {
            // a specific handler may already have said why; keep its words
            if (root.error === "")
                root.error = Tr.t("Could not get the weather — check your internet connection");
            return false;
        }
        root.error = "";
        root.note = Tr.t("Weather updated");
        return true;
    }

    property int updatedMs: 0              // Date.now() of the last successful fetch
    property string lastUpdated: ""        // "HH:MM" (or h:mm AP) of that fetch
    readonly property bool stale: error !== "" && updatedMs > 0
    readonly property string updatedText: lastUpdated !== "" ? Tr.t("Updated %1", lastUpdated) : ""
    // WMO weather codes, as Open-Meteo reports them
    function describe(c) {
        return c === 0 ? "Clear" : c <= 2 ? "Partly cloudy" : c === 3 ? "Overcast" : c <= 48 ? "Fog"
             : c <= 57 ? "Drizzle" : c <= 67 ? "Rain" : c <= 77 ? "Snow" : c <= 82 ? "Showers" : c <= 86 ? "Snow showers" : "Thunderstorm";
    }
    function uvLevel(v) {
        return v < 3 ? Tr.t("Low") : v < 6 ? Tr.t("Moderate") : v < 8 ? Tr.t("High") : v < 11 ? Tr.t("Very high") : Tr.t("Extreme");
    }
    function aqiLevel(v) {
        return v <= 50 ? Tr.t("Good") : v <= 100 ? Tr.t("Moderate") : v <= 150 ? Tr.t("Unhealthy for sensitive groups")
             : v <= 200 ? Tr.t("Unhealthy") : v <= 300 ? Tr.t("Very unhealthy") : Tr.t("Hazardous");
    }
    // ---- alerts --------------------------------------------------------------
    // open-meteo has no official warning feed: these are read from the forecast
    // and the current UV, and the window says so. `advisory` stays as the one
    // headline for the sidebar and older callers.
    function buildAlerts(next) {
        const out = [];
        if (!next || !next.length) return out;
        const rain = Math.max.apply(null, next.map(h => h.rain || 0));
        const wind = Math.max.apply(null, next.map(h => h.wind || 0));
        const hot = Math.max.apply(null, next.map(h => h.temp));
        const cold = Math.min.apply(null, next.map(h => h.temp));
        if (rain >= 70)
            out.push({ label: Tr.t("Rain is likely in the next few hours"), detail: Tr.t("Up to %1% chance", Math.round(rain)), level: "advisory", icon: "weather-showers" });
        if (wind >= 40)
            out.push({ label: Tr.t("Strong wind — %1 %2", windValue(wind), windUnit), detail: Tr.t("In the next few hours"), level: "warning", icon: "weather-storm" });
        if (!fahrenheit && hot >= 35)
            out.push({ label: Tr.t("Very hot — %1°", Math.round(hot)), detail: Tr.t("In the next few hours"), level: "warning", icon: "weather-clear" });
        if (cold <= 0)
            out.push({ label: Tr.t("Below freezing"), detail: Tr.t("Down to %1°", Math.round(cold)), level: "warning", icon: "weather-snow" });
        if (!isNaN(root.uvIndex) && root.uvIndex >= 8)
            out.push({ label: Tr.t("Very high UV"), detail: Tr.t("UV index %1", Math.round(root.uvIndex)), level: "advisory", icon: "weather-clear" });
        return out;
    }
    readonly property string advisory: alerts.length ? alerts[0].label : ""
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
        root.run("lookup", [currentName()]);
        geo.command = ["curl", "-sf", "--max-time", "8", "https://geocoding-api.open-meteo.com/v1/search?count=1&name=" + encodeURIComponent(currentName())];
        geo.running = true;
    }
    function fetch() {
        const lat = currentLat(), lon = currentLon();
        if (!enabled || (!lat && !lon))
            return;
        root.run("fetch", [lat, lon]);
        loading = true;
        now.command = ["curl", "-sf", "--max-time", "8", "https://api.open-meteo.com/v1/forecast?current=temperature_2m,weather_code,apparent_temperature,relative_humidity_2m,wind_speed_10m,surface_pressure,visibility,uv_index"
            + "&daily=temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset,precipitation_probability_max,wind_speed_10m_max,uv_index_max"
            + "&hourly=temperature_2m,weather_code,precipitation_probability,wind_speed_10m"
            + "&past_days=0&forecast_days=" + forecastDays
            + "&temperature_unit=" + (fahrenheit ? "fahrenheit" : "celsius")
            + "&timezone=auto"
            + "&latitude=" + lat
            + "&longitude=" + lon];
        now.running = true;
        // Air quality is a separate Open-Meteo endpoint. It is optional: a
        // failure here must never throw away the forecast just fetched.
        air.command = ["curl", "-sf", "--max-time", "8", "https://air-quality-api.open-meteo.com/v1/air-quality?current=us_aqi,pm2_5"
            + "&latitude=" + lat + "&longitude=" + lon];
        air.running = true;
    }
    Connections {
        target: Settings.data
        function onWeatherCityChanged() { root.lookUp(); }
        function onWeatherUnitsChanged() { if (root.units !== Settings.data.weatherUnits) root.setUnits(Settings.data.weatherUnits); }
    }
    Process {
        id: air
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const a = (JSON.parse(text) || {}).current || {};
                    root.aqi = a.us_aqi;
                    root.pm25 = a.pm2_5;
                } catch (e) {}   // AQI is extra: keep the last good value, if any
            }
        }
    }
    Process {
        id: geo
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text).results[0];
                    Settings.data.weatherLat = r.latitude;
                    Settings.data.weatherLon = r.longitude;
                    root.error = "";
                    root.fetch();
                } catch (e) {
                    root.error = Tr.t("Could not look up that place — check your internet connection");
                }
            }
        }
        onExited: code => {
            if (code !== 0 && root.error === "")
                root.error = Tr.t("Could not look up that place — check your internet connection");
            root.finished("lookup", "", code);
        }
    }
    Process {
        id: now
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const rootObj = JSON.parse(text);
                    const c = rootObj.current;
                    root.error = "";
                    root.loading = false;
                    root.updatedMs = Date.now();
                    root.lastUpdated = Qt.formatTime(new Date(root.updatedMs), Settings.data.use24h ? "HH:mm" : "h:mm AP");
                    root.temp = c.temperature_2m;
                    root.code = c.weather_code;
                    root.feelsLike = c.apparent_temperature;
                    root.humidity = c.relative_humidity_2m;
                    root.wind = c.wind_speed_10m;
                    root.pressure = c.surface_pressure;
                    root.visibility = c.visibility;
                    root.uvIndex = c.uv_index;
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
                                        code: d.weather_code[i],
                                        rain: (d.precipitation_probability_max || [])[i] || 0,
                                        wind: (d.wind_speed_10m_max || [])[i] || 0,
                                        uv: (d.uv_index_max || [])[i] || 0,
                                        sunrise: String((d.sunrise || [])[i] || "").slice(11, 16),
                                        sunset: String((d.sunset || [])[i] || "").slice(11, 16) });
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
                                             code: h.weather_code[i],
                                             rain: (h.precipitation_probability || [])[i] || 0,
                                             wind: (h.wind_speed_10m || [])[i] || 0 });
                            }
                        }
                        root.hourly = hours;
                        root.dayparts = root.buildDayparts(h);
                        root.alerts = root.buildAlerts(hours.slice(0, 12));
                    }
                } catch (e) {
                    root.loading = false;
                    root.error = Tr.t("Could not get the weather — check your internet connection");
                }
            }
        }
        onExited: code => {
            root.loading = false;
            if (code !== 0 && root.error === "" && root.updatedMs === 0)
                root.error = Tr.t("Could not get the weather — check your internet connection");
            root.finished("fetch", "", code);
        }
    }
    Timer {
        interval: refreshMinutes * 60 * 1000
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: currentLat() === 0 && currentLon() === 0 ? root.lookUp() : root.fetch()
    }
}
