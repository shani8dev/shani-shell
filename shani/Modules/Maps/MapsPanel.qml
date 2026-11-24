// Maps: a tile grid centred on the current location (GeoClue) or the last
// search result — OpenStreetMap tiles over Image elements, attribution
// shown, zoom in/out, recenter. Location is opt-in (privacy): off means a
// typed city, via Weather's geocoder (shani weather set). Search geocodes
// with Nominatim (OSM) in geoCode(): a place description, zoom to the
// result, and a directions deep link (OSM route). Tiles stay
// tile.openstreetmap.org. Needs the network for tiles and search; when
// offline the tiles are blank and the centre + coordinates are what's left.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/Gestures.js" as G

AppWindow {
    id: win
    // who is asking, as OpenStreetMap's tile and Nominatim policies require
    readonly property string userAgent: "shani-shell-maps/1.0 (+https://github.com/shani8dev/shani-shell)"
    readonly property string tileCache: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/shani-shell/map-tiles"
    appName: "Maps"
    visible: Ui.maps
    onGone: Ui.maps = false
    margins: 0
    implicitWidth: Theme.px(900)
    implicitHeight: Theme.px(620)

    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.maps = false }

    // the servers (OpenStreetMap's own; the tests serve theirs offline)
    readonly property string tileUrl: Quickshell.env("SHANI_MAP_TILES") || "https://tile.openstreetmap.org/{key}.png"
    readonly property string searchUrl: Quickshell.env("SHANI_MAP_SEARCH") || "https://nominatim.openstreetmap.org/search"
    readonly property string routeServer: Quickshell.env("SHANI_MAP_ROUTE") || "https://router.project-osrm.org"

    // ---- slippy-map tile math (OSM tiles, z/x/y) ----
    property int z: Ui.mapsZoom || 14
    property int tile: 256
    // the map centre: the last search result, or the current location
    property real mapLat: 0
    property real mapLon: 0
    property string placeName: ""
    property string placeDesc: ""
    property string placeType: ""
    // a place's details from OpenStreetMap (Nominatim's extratags): GNOME Maps parity
    property string placeHours: ""
    property string placePhone: ""
    property string placeWebsite: ""
    // places saved (GNOME Maps' favourites): [{ name, desc, lat, lon }], a click each
    readonly property var saved: Settings.data.mapsSaved || []
    readonly property bool pinSaved: saved.some(p => Math.abs(p.lat - pinLat) < 1e-6 && Math.abs(p.lon - pinLon) < 1e-6)
    function toggleSaved() {
        if (pinLat === 0 && pinLon === 0) return;
        Settings.data.mapsSaved = pinSaved
            ? saved.filter(p => !(Math.abs(p.lat - pinLat) < 1e-6 && Math.abs(p.lon - pinLon) < 1e-6))
            : saved.concat([{ name: placeName || Tr.t("Saved place"), desc: placeDesc, lat: pinLat, lon: pinLon }]);
    }
    // forget one chip directly: otherwise you must select it, then toggle the
    // star, which silently changes the place you are looking at
    function removeSaved(p) {
        Settings.data.mapsSaved = saved.filter(s => !(s.name === p.name && s.lat === p.lat && s.lon === p.lon));
    }
    // share a place (GNOME Maps' Share): its OpenStreetMap link copied, and shown as a
    // QR code for a phone's camera
    readonly property string shareUrl: pinLat === 0 && pinLon === 0 ? ""
        : "https://www.openstreetmap.org/?mlat=" + pinLat.toFixed(6) + "&mlon=" + pinLon.toFixed(6) + "#map=17/" + pinLat.toFixed(6) + "/" + pinLon.toFixed(6)
    function sharePlace() {
        if (!shareUrl) return;
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", shareUrl]);
        Qr.show(placeName || Tr.t("This place"), shareUrl);
    }
    function goSaved(p) {
        mapLat = p.lat; mapLon = p.lon; pinLat = p.lat; pinLon = p.lon;
        placeName = p.name; placeDesc = p.desc || ""; placeType = ""; placeHours = ""; placePhone = ""; placeWebsite = "";
        clearRoute(); z = 16; Ui.mapsZoom = 16;
    }
    // the location buttons do nothing when location is off, GeoClue is absent
    // or the helper failed: say which instead of leaving a silent click
    property bool locationAsked: false
    readonly property string locationNote: {
        if (Location.running) return Tr.t("Find my location") + "…";
        if (Location.error !== "") return Tr.t("Location") + ": " + Location.error;
        if (!Settings.data.useLocation) return Tr.t("Type a city above, or turn on location in Settings > Privacy");
        if (!Location.available) return Tr.t("Location") + ": " + Tr.t("Not found");
        return "";
    }
    property string searchError: ""
    property string searchField: ""
    property bool searching: false
    // Nominatim asks for ≤1 request/second and the same query rarely changes:
    // remember answers in memory and queue a search that arrives too soon.
    property var geoCache: ({})
    property int lastGeoAt: 0
    property string pendingGeo: ""
    Timer {
        id: geoThrottle
        interval: 1000
        onTriggered: {
            if (win.searching) { geoThrottle.restart(); return; }
            const q = win.pendingGeo;
            win.pendingGeo = "";
            if (q) win.geoCode(q);
        }
    }
    readonly property string routeUrl: {
        if (win.mapLat === 0 && win.mapLon === 0)
            return "";
        const from = win.fromOk ? (win.fromLat + "," + win.fromLon)
            : Location.available ? (Location.lat + "," + Location.lon) : "";
        if (from === "")
            return "";      // no start yet: the browser link would open from= empty
        return "https://www.openstreetmap.org/directions?from=" + encodeURIComponent(from) + "&to=" + encodeURIComponent(win.mapLat + "," + win.mapLon);
    }
    // the place found (the pin), and the way to it
    property real pinLat: 0
    property real pinLon: 0
    property bool routeAsked: false
    property string routeProfile: "driving"   // UI tokens: driving | foot | bike
    // OSRM's demo server names its profiles driving|walking|cycling. Keep the UI
    // tokens and labels as they are, translate only when building the URL. The
    // env override is three comma-separated tokens in driving, foot, bike order.
    readonly property var routeProfiles: {
        const p = (Quickshell.env("SHANI_MAP_ROUTE_PROFILES") || "driving,walking,cycling").split(",");
        return { driving: p[0] || "driving", foot: p[1] || "walking", bike: p[2] || "cycling" };
    }
    property bool routing: false
    property string routeError: ""
    property var route: []                    // [[lat, lon], ...]
    property real routeDistance: 0            // metres
    property real routeDuration: 0            // seconds
    property var routeSteps: []
    property real fromLat: 0                  // a typed start, when there is no location
    property real fromLon: 0
    readonly property bool fromOk: fromLat !== 0 || fromLon !== 0
    property string routeFrom: ""

    function world() { return Math.pow(2, z) * tile; }
    function toScreen(lat, lon) {
        const w = world();
        const x = (lon + 180) / 360 * w;
        const y = (0.5 - Math.log(Math.tan(Math.PI / 4 + lat * Math.PI / 360)) / (2 * Math.PI)) * w;
        return { x: x - px + grid.width / 2, y: y - py + grid.height / 2 };
    }
    // the centre moved by (dx, dy) screen pixels
    function panBy(dx, dy) {
        const w = world();
        const nx = ((px + dx) % w + w) % w;
        const ny = Math.max(0, Math.min(w, py + dy));
        mapLon = nx / w * 360 - 180;
        mapLat = Math.atan(Math.sinh(Math.PI * (1 - 2 * ny / w))) * 180 / Math.PI;
    }
    function zoomBy(d) {
        z = Math.max(3, Math.min(19, z + d));
        Ui.mapsZoom = z;
    }
    function km(m) { return m >= 1000 ? (m / 1000).toFixed(m >= 10000 ? 0 : 1) + " km" : Math.round(m) + " m"; }
    function duration(s) {
        const h = Math.floor(s / 3600), mi = Math.round((s % 3600) / 60);
        return h > 0 ? Tr.t("%1 h %2 min", h, mi) : Tr.t("%1 min", Math.max(1, mi));
    }
    // a turn as a sentence, from OSRM's maneuver
    function stepText(st) {
        const m = st.maneuver || {};
        const road = st.name ? Tr.t(" onto %1", st.name) : "";
        const mod = m.modifier ? " " + m.modifier : "";
        if (m.type === "depart") return Tr.t("Start") + (st.name ? Tr.t(" on %1", st.name) : "");
        if (m.type === "arrive") return Tr.t("Arrive");
        if (m.type === "roundabout" || m.type === "rotary") return Tr.t("At the roundabout, take exit %1", m.exit || 1) + road;
        // OSRM's maneuver types, as a person says them ("new name" is the same road
        // changing its name: measured, it read "New name straight onto ...")
        const verb = { "turn": Tr.t("Turn"), "end of road": Tr.t("Turn"), "fork": Tr.t("Keep"), "new name": Tr.t("Continue"),
                       "continue": Tr.t("Continue"), "merge": Tr.t("Merge"), "on ramp": Tr.t("Take the ramp"),
                       "off ramp": Tr.t("Take the exit"), "notification": Tr.t("Continue") }[m.type]
            || (m.type ? m.type.charAt(0).toUpperCase() + m.type.slice(1) : Tr.t("Continue"));
        return verb + (m.type === "on ramp" || m.type === "off ramp" ? "" : mod) + road + (st.distance > 0 ? "  (" + km(st.distance) + ")" : "");
    }
    function directions() {
        routeAsked = true;
        routeError = "";
        const fromOk = fromLat !== 0 || fromLon !== 0;
        const sLat = fromOk ? fromLat : Location.lat, sLon = fromOk ? fromLon : Location.lon;
        if (!fromOk && !Location.available) { routeError = Tr.t("Where from? Type a start, or turn on location in Settings > Privacy"); return; }
        if (pinLat === 0 && pinLon === 0) { routeError = Tr.t("Search the place to go to first"); return; }
        routing = true;
        const profile = win.routeProfiles[routeProfile] || routeProfile;
        const url = routeServer + "/route/v1/" + profile + "/" + sLon + "," + sLat + ";" + pinLon + "," + pinLat + "?overview=full&geometries=geojson&steps=true";
        routeProc.command = ["curl", "-sf", "--max-time", "20", "-A", userAgent, url];
        routeProc.running = true;
    }
    function directionsFrom(text) {
        const q = String(text || "").trim();
        if (!q) return;
        routing = true;
        routeError = "";
        fromProc.command = ["curl", "-sf", "--max-time", "10", "-H", "User-Agent: " + userAgent,
                            searchUrl + "?format=jsonv2&limit=1&q=" + encodeURIComponent(q)];
        fromProc.query = q;
        fromProc.running = true;
    }
    // what the shell's state shows, and what IPC asks
    readonly property var report: ({ lat: Math.round(mapLat * 1e4) / 1e4, lon: Math.round(mapLon * 1e4) / 1e4, zoom: z,
                                     route: route.length, distance: Math.round(routeDistance), steps: routeSteps.length,
                                     error: routeError || searchError, routing: routing,
                                     tilesDrawn: tilesDrawn, tilesDistinct: tilesDistinct,
                                     hours: placeHours, phone: placePhone, website: placeWebsite, saved: saved.length, pinSaved: pinSaved, shareUrl: shareUrl })
    onReportChanged: Ui.mapsView = report
    Connections {
        target: Ui
        function onMapsAsked(what, arg) {
            if (what === "pan") { const [dx, dy] = arg.split(",").map(Number); win.panBy(dx, dy); }
            else if (what === "zoom") win.zoomBy(Number(arg));
            else if (what === "directions") { win.routeProfile = arg || win.routeProfile; win.directions(); }
            else if (what === "from") win.directionsFrom(arg);
            else if (what === "save") win.toggleSaved();
            else if (what === "share") win.sharePlace();
            else if (what === "go-saved") { const p = win.saved.find(s => s.name === arg); if (p) win.goSaved(p); }
        }
    }
    function clearRoute() { routeAsked = false; route = []; routeSteps = []; routeDistance = 0; routeError = ""; }
    // tile files: asked for once, shown once on disk
    property var ready: ({})
    property var asked: ({})
    // tiles drawn now, and how many different ones (the tests read both: a blank map
    // draws none, a map showing a neighbour's picture draws fewer different than drawn)
    property int tilesDrawn: 0
    property int tilesDistinct: 0
    Timer {
        id: recount
        interval: 150
        onTriggered: {
            let drawn = 0;
            const seen = {};
            for (let i = 0; i < tileRep.count; i++) {
                const t = tileRep.itemAt(i);
                const img = t ? t.children[0] : null;
                if (!img || !img.visible || img.status !== Image.Ready || !img.source.toString())
                    continue;
                drawn++;
                seen[img.source.toString()] = true;
            }
            win.tilesDrawn = drawn;
            win.tilesDistinct = Object.keys(seen).length;
        }
    }
    function fetch(file, key) {
        if (asked[file])
            return;
        asked[file] = true;
        const p = fetcher.createObject(win, { forFile: file, command: ["sh", "-c",
            '[ -s "$1" ] || { mkdir -p "${1%/*}" && curl -sf --max-time 20 -A "$3" -o "$1.part" "$2" && mv -f "$1.part" "$1"; }',
            "sh", file, tileUrl.replace("{key}", key), userAgent] });
        p.running = true;
    }
    Component {
        id: fetcher
        Process {
            property string forFile: ""
            onExited: code => {
                if (code === 0) {
                    const r = Object.assign({}, win.ready);
                    r[forFile] = true;
                    win.ready = r;
                } else {
                    delete win.asked[forFile];        // not there (offline): ask again next time
                }
                destroy();
            }
        }
    }
    Process {
        id: routeProc
        stdout: StdioCollector {
            onStreamFinished: {
                win.routing = false;
                try {
                    const r = JSON.parse(text);
                    const best = (r.routes || [])[0];
                    if (r.code !== "Ok" || !best) { win.routeError = Tr.t("No way found between these places"); return; }
                    win.route = best.geometry.coordinates.map(c => [c[1], c[0]]);
                    win.routeDistance = best.distance;
                    win.routeDuration = best.duration;
                    win.routeSteps = [].concat(...best.legs.map(l => l.steps)).map(win.stepText);
                } catch (e) { win.routeError = Tr.t("Directions failed — check the network and try again"); }
            }
        }
        onExited: code => { if (code !== 0) { win.routing = false; win.routeError = Tr.t("Directions failed — check the network and try again"); } }
    }
    Process {
        id: fromProc
        property string query: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text)[0];
                    win.fromLat = parseFloat(r.lat);
                    win.fromLon = parseFloat(r.lon);
                    win.routeFrom = String(r.display_name || fromProc.query).split(",")[0];
                    win.directions();
                } catch (e) { win.routing = false; win.routeError = Tr.t("No place found for that start"); }
            }
        }
    }

    // world pixel at center
    readonly property real px: (win.mapLon + 180) / 360 * Math.pow(2, z) * tile
    readonly property real py: (0.5 - Math.log(Math.tan(Math.PI / 4 + win.mapLat * Math.PI / 360)) / (2 * Math.PI)) * Math.pow(2, z) * tile

    onVisibleChanged: if (visible) { win.syncCenter(); if (Ui.mapsQuery !== "") win.geoCode(Ui.mapsQuery); }
    Connections { target: Ui; function onMapsQueryChanged() { if (win.visible && Ui.mapsQuery !== "") win.geoCode(Ui.mapsQuery); } }
    function syncCenter() {
        if (Ui.mapsLat !== 0 || Ui.mapsLon !== 0) {
            win.mapLat = Ui.mapsLat;
            win.mapLon = Ui.mapsLon;
            win.z = Math.max(3, Math.min(19, Ui.mapsZoom || 14));
            win.placeName = Ui.mapsPlace || "";
            win.placeDesc = Ui.mapsPlace || "";
        } else if (Location.available && (Location.lat !== 0 || Location.lon !== 0)) {
            win.mapLat = Location.lat;
            win.mapLon = Location.lon;
        }
    }
    function recenter() {
        locationAsked = true;
        if (Location.available && (Location.lat !== 0 || Location.lon !== 0)) {
            win.mapLat = Location.lat;
            win.mapLon = Location.lon;
            win.placeName = "";
            win.placeDesc = "";
            win.placeType = "";
            searchError = "";
        }
        Location.refresh();
    }
    // apply one Nominatim result (display_name, lat, lon, type, class, extratags)
    // — shared by the network and cache paths so the result shape stays identical
    function applyGeoResult(r) {
        const lat = parseFloat(r.lat);
        const lon = parseFloat(r.lon);
        if (!isFinite(lat) || !isFinite(lon)) {
            win.searchError = Tr.t("No place found for that search");
            return;
        }
        win.mapLat = lat;
        win.mapLon = lon;
        win.pinLat = lat;
        win.pinLon = lon;
        win.clearRoute();
        win.z = 16;
        Ui.mapsZoom = 16;
        const name = String(r.display_name || win.searchField || "");
        win.placeName = name.split(",")[0] || name;
        win.placeDesc = name;
        win.placeType = String(r.type || r.class || "");
        const x = r.extratags || {};
        win.placeHours = String(x.opening_hours || "");
        win.placePhone = String(x.phone || x["contact:phone"] || "");
        win.placeWebsite = String(x.website || x["contact:website"] || "");
        Ui.mapsQuery = win.searchField;
        Ui.mapsPlace = name;
        Ui.mapsLat = lat;
        Ui.mapsLon = lon;
    }
    // Nominatim geocode: search a place, zoom to it, describe it
    function geoCode(query) {
        const q = String(query || "").trim();
        if (q === "")
            return;
        searchError = "";
        // a query typed while another search is in flight waits its turn; the
        // old guard returned here, so the second search vanished
        if (searching) {
            pendingGeo = q;
            geoThrottle.restart();
            return;
        }
        searchField = q;
        // a repeat is free: answer from the in-memory cache, no network
        if (Object.prototype.hasOwnProperty.call(win.geoCache, q)) {
            win.applyGeoResult(win.geoCache[q]);
            return;
        }
        // Nominatim's policy: at most one request per second — queue anything sooner
        if (Date.now() - lastGeoAt < 1000) {
            pendingGeo = q;
            geoThrottle.restart();
            return;
        }
        searching = true;
        lastGeoAt = Date.now();
        const url = win.searchUrl + "?format=jsonv2&limit=1&extratags=1&accept-language=" + encodeURIComponent(Tr.lang || "en") + "&q=" + encodeURIComponent(q);
        geoProc.command = ["curl", "-sf", "--max-time", "10", "-H", "User-Agent: " + win.userAgent, url];
        geoProc.running = true;
    }
    function openDirections() {
        if (routeUrl !== "")
            Quickshell.execDetached(["xdg-open", routeUrl]);
    }

    Item {
        id: blurCard
        anchors.fill: parent

        ColumnLayout {
            id: col
            x: 20; y: 20
            width: parent.width - 40
            height: parent.height - 40
            spacing: Theme.px(12)

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: win.placeName !== "" ? win.placeName : (Location.available ? (Weather.zoneCity || Tr.t("Where you are")) : "")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(15) * Theme.fontScale
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                IconButton { icon: "mark-location"; size: Theme.px(28); tip: Tr.t("Recenter"); onClicked: win.recenter(); }
                IconButton { icon: "view-refresh"; size: Theme.px(28); tip: Tr.t("Find my location"); onClicked: { win.locationAsked = true; Location.refresh(); } }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                TextField {
                    id: mapSearch
                    Layout.fillWidth: true
                    placeholder: Tr.t("Search city or place")
                    label: Tr.t("Search city or place")
                    text: win.searchField || Ui.mapsQuery || ""
                    onAccepted: { Ui.mapsQuery = text; win.geoCode(text); }
                }
                Button { text: win.searching ? "…" : Tr.t("Search"); kind: "primary"; enabled: !win.searching && mapSearch.text.trim() !== ""; onClicked: { Ui.mapsQuery = mapSearch.text.trim(); win.geoCode(mapSearch.text.trim()); } }
                Button { visible: win.pinLat !== 0 || win.pinLon !== 0; text: Tr.t("Directions"); kind: "outline"; onClicked: win.directions() }
                IconButton {
                    visible: win.pinLat !== 0 || win.pinLon !== 0
                    icon: win.pinSaved ? "starred" : "non-starred"
                    size: Theme.px(30); on: win.pinSaved
                    tip: win.pinSaved ? Tr.t("Saved - click to forget it") : Tr.t("Save this place")
                    onClicked: win.toggleSaved()
                }
                IconButton {
                    visible: win.shareUrl !== ""
                    icon: "emblem-shared"
                    size: Theme.px(30)
                    tip: Tr.t("Share: the link copied, and a code for a phone")
                    onClicked: win.sharePlace()
                }
            }
            // saved places: one click goes there
            Flow {
                Layout.fillWidth: true
                visible: win.saved.length > 0
                spacing: Theme.px(6)
                Repeater {
                    model: win.saved
                    Row {
                        required property var modelData
                        spacing: Theme.px(2)
                        Choice { text: parent.modelData.name; onClicked: win.goSaved(parent.modelData) }
                        IconButton {
                            icon: "edit-delete"
                            size: Theme.px(20)
                            tip: Tr.t("Forget %1", parent.modelData.name)
                            onClicked: win.removeSaved(parent.modelData)
                        }
                    }
                }
            }
            Text {
                visible: win.searchError !== ""
                Layout.fillWidth: true
                text: win.searchError
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                wrapMode: Text.WordWrap
            }
            Text {
                visible: win.locationNote !== "" && (win.locationAsked || win.placeDesc === "" || Location.running || Location.error !== "")
                Layout.fillWidth: true
                text: win.locationNote
                color: Location.error !== "" ? Theme.danger : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                wrapMode: Text.WordWrap
            }
            Text {
                visible: win.placeDesc !== ""
                Layout.fillWidth: true
                text: win.placeDesc + (win.placeType ? " · " + win.placeType : "") + " (" + win.mapLat.toFixed(4) + ", " + win.mapLon.toFixed(4) + ")"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
                wrapMode: Text.WordWrap
            }
            // what OpenStreetMap knows of it: open when, a phone, a website (a click opens it)
            RowLayout {
                Layout.fillWidth: true
                visible: win.placeHours !== "" || win.placePhone !== "" || win.placeWebsite !== ""
                spacing: Theme.px(12)
                Text { visible: win.placeHours !== ""; text: Tr.t("Open: %1", win.placeHours); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Button { visible: win.placePhone !== ""; flat: true; text: win.placePhone; onClicked: Quickshell.execDetached(["xdg-open", "tel:" + win.placePhone.replace(/\s/g, "")]) }
                Button { visible: win.placeWebsite !== ""; flat: true; text: Tr.t("Website"); onClicked: Quickshell.execDetached(["xdg-open", win.placeWebsite]) }
                Item { Layout.fillWidth: true }
            }

            // ---- the map: as many tiles as fill it, dragged to pan, wheel or +/- to zoom ----
            Rectangle {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Theme.px(320)
                radius: Theme.radiusSmall
                color: Theme.hover
                clip: true
                // a named pane: the surface the pan/zoom controls act on is
                // identifiable in the accessibility tree, not just a coloured box
                Accessible.role: Accessible.Pane
                Accessible.name: win.placeName !== "" ? win.placeName : (Weather.zoneCity || Tr.t("Where you are"))
                readonly property int cols: Math.ceil(width / win.tile) + 2
                readonly property int rows: Math.ceil(height / win.tile) + 2
                // the tile at the view's top left, and where it sits
                readonly property int tx0: Math.floor((win.px - width / 2) / win.tile)
                readonly property int ty0: Math.floor((win.py - height / 2) / win.tile)
                // the tiles in view, each named by its own column and row: a slot is one
                // tile for its whole life. Slots counted by index (tile = tx0 + index %
                // cols) were re-keyed while a resize or a search settled, and kept a
                // neighbour's picture - maximised, the map showed some streets twice, and
                // after a search it stayed blank until something else moved it
                readonly property var inView: {
                    const out = [];
                    for (let j = 0; j < rows; j++)
                        for (let i = 0; i < cols; i++)
                            out.push(win.z + ":" + (tx0 + i) + ":" + (ty0 + j));
                    return out;
                }
                Repeater {
                    id: tileRep
                    model: grid.inView
                    Item {
                        id: tile
                        required property string modelData
                        readonly property int tx: Number(modelData.split(":")[1])
                        readonly property int ty: Number(modelData.split(":")[2])
                        x: tx * win.tile - win.px + grid.width / 2
                        y: ty * win.tile - win.py + grid.height / 2
                        width: win.tile
                        height: win.tile
                        readonly property int n: Math.pow(2, win.z)
                        readonly property bool inside: ty >= 0 && ty < n
                        readonly property string key: win.z + "/" + (((tx % n) + n) % n) + "/" + ty
                        // OpenStreetMap's tile policy: say who is asking (Qt's own user
                        // agent is refused - every tile came back "Access blocked") and
                        // keep what was fetched: each tile once, with curl, into the cache
                        readonly property string file: win.tileCache + "/" + key + ".png"
                        // which tile files are on disk is the window's (win.ready), not this
                        // delegate's: delegates are re-keyed while the layout settles, so a
                        // download tied to one finished after it had moved on (measured: every
                        // tile "moved", none shown). Each file is fetched once (win.fetch).
                        onKeyChanged: if (inside) win.fetch(file, key)
                        Component.onCompleted: if (inside) win.fetch(file, key)
                        Image {
                            anchors.fill: parent
                            visible: tile.inside
                            asynchronous: true
                            source: win.ready[tile.file] ? "file://" + tile.file : ""
                            onStatusChanged: recount.restart()
                        }
                    }
                }
                // the route, over the tiles
                Canvas {
                    id: routeLine
                    anchors.fill: parent
                    visible: win.route.length > 1
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        if (win.route.length < 2) return;
                        ctx.lineWidth = 6;
                        ctx.lineJoin = "round";
                        ctx.lineCap = "round";
                        ctx.strokeStyle = Theme.alpha("#ffffff", 0.9);
                        const pts = win.route.map(p => win.toScreen(p[0], p[1]));
                        for (const pass of [0, 1]) {
                            ctx.beginPath();
                            ctx.moveTo(pts[0].x, pts[0].y);
                            for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y);
                            ctx.stroke();
                            ctx.lineWidth = 4;
                            ctx.strokeStyle = Theme.accent;
                        }
                    }
                    Connections { target: win; function onPxChanged() { routeLine.requestPaint(); } function onPyChanged() { routeLine.requestPaint(); } function onRouteChanged() { routeLine.requestPaint(); } }
                }
                // the place found (or where you are)
                Rectangle {
                    readonly property var at: win.toScreen(win.pinLat, win.pinLon)
                    visible: win.pinLat !== 0 || win.pinLon !== 0
                    x: at.x - width / 2; y: at.y - height / 2
                    width: Theme.px(16); height: Theme.px(16); radius: Theme.px(8)
                    color: Theme.accent
                    border.width: 3; border.color: "white"
                }
                // "you are here": a blue dot distinct from the search pin, with a
                // translucent ring sized from GeoClue's accuracy so a coarse fix
                // reads as coarse. Both use the same toScreen() projection.
                Rectangle {
                    id: hereDot
                    readonly property var at: win.toScreen(Location.lat, Location.lon)
                    // distinct from the search pin in the accessibility tree too
                    Accessible.role: Accessible.Graphic
                    Accessible.name: Tr.t("Where you are")
                    // metres per screen pixel at this latitude/zoom (256 px tiles)
                    readonly property real mPerPx: 156543.03392 * Math.cos(win.mapLat * Math.PI / 180) / Math.pow(2, win.z)
                    readonly property real ringR: Math.max(Theme.px(10), Math.min(Theme.px(80), Location.accuracy / mPerPx))
                    visible: Location.available && (Location.lat !== 0 || Location.lon !== 0)
                    x: at.x - ringR; y: at.y - ringR
                    width: ringR * 2; height: ringR * 2
                    radius: ringR
                    color: Theme.alpha("#1e90ff", 0.18)
                    border.width: 1; border.color: Theme.alpha("#1e90ff", 0.6)
                    Rectangle {
                        anchors.centerIn: parent
                        width: Theme.px(12); height: Theme.px(12); radius: Theme.px(6)
                        color: "#1e90ff"
                        border.width: 2; border.color: "white"
                    }
                }
                // two fingers: a level in or out each time they double or halve their distance
                PinchHandler {
                    target: null
                    property real base: 1
                    onActiveChanged: base = 1
                    onActiveScaleChanged: {
                        const r = G.pinchSteps(activeScale, base);
                        base = r.base;
                        if (r.steps) win.zoomBy(r.steps);
                    }
                }
                // drag to pan; wheel to zoom; double-click to zoom in
                MouseArea {
                    anchors.fill: parent
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property real lx: 0
                    property real ly: 0
                    onPressed: m => { lx = m.x; ly = m.y; }
                    onPositionChanged: m => { win.panBy(lx - m.x, ly - m.y); lx = m.x; ly = m.y; }
                    onWheel: w => win.zoomBy(w.angleDelta.y > 0 ? 1 : -1)
                    onDoubleClicked: win.zoomBy(1)
                }
                // zoom, on a backing of its own so it reads over any map
                Rectangle {
                    anchors { right: parent.right; top: parent.top; margins: Theme.px(10) }
                    width: Theme.px(40)
                    height: zoomCol.implicitHeight + 8
                    radius: Theme.px(10)
                    color: Theme.alpha(Theme.bg, 0.92)
                    border.width: 1
                    border.color: Theme.border
                    ColumnLayout {
                        id: zoomCol
                        anchors.centerIn: parent
                        spacing: 2
                        IconButton { icon: "zoom-in"; size: Theme.px(32); tip: Tr.t("Zoom in"); onClicked: win.zoomBy(1) }
                        IconButton { icon: "zoom-out"; size: Theme.px(32); tip: Tr.t("Zoom out"); onClicked: win.zoomBy(-1) }
                    }
                }
                Text {
                    anchors { right: parent.right; bottom: parent.bottom; margins: Theme.px(6) }
                    text: "© OpenStreetMap contributors"
                    color: Theme.text
                    style: Text.Outline
                    styleColor: Theme.bg
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
            }

            // ---- directions: how, how far, how long, and the turns ----
            ColumnLayout {
                Layout.fillWidth: true
                visible: win.routeAsked
                spacing: Theme.px(6)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: [["driving", Tr.t("Drive")], ["foot", Tr.t("Walk")], ["bike", Tr.t("Cycle")]]
                        Choice {
                            required property var modelData
                            text: modelData[1]
                            selected: win.routeProfile === modelData[0]
                            onClicked: { win.routeProfile = modelData[0]; win.directions(); }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: win.routing ? Tr.t("Finding the way…") : win.routeError !== "" ? win.routeError
                            : win.routeDistance > 0 ? win.km(win.routeDistance) + "  ·  " + win.duration(win.routeDuration) + (win.routeFrom ? "  ·  " + Tr.t("from %1", win.routeFrom) : "") : ""
                        color: win.routeError !== "" ? Theme.danger : Theme.text
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Close directions"); onClicked: win.clearRoute() }
                }
                RowLayout {
                    Layout.fillWidth: true
                    // keep the start editable after a route succeeds: closing
                    // and reopening directions just to change it is needless
                    visible: win.routeAsked
                    TextField {
                        id: fromField
                        Layout.fillWidth: true
                        placeholder: Tr.t("Start from (a place or an address)")
                        text: win.routeFrom
                        // emptying the field goes back to "my location"
                        onTextChanged: if (text === "" && (win.fromLat !== 0 || win.fromLon !== 0)) { win.fromLat = 0; win.fromLon = 0; win.routeFrom = ""; }
                        onAccepted: win.directionsFrom(text)
                    }
                    Button { text: Tr.t("Go"); onClicked: win.directionsFrom(fromField.text) }
                }
                ListView {
                    reuseItems: true
                    cacheBuffer: 400
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(150, contentHeight)
                    clip: true
                    model: win.routeSteps
                    delegate: Text {
                        required property var modelData
                        width: ListView.view.width
                        text: "•  " + modelData
                        color: Theme.dim
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
                Button {
                    visible: win.routeUrl !== ""
                    text: Tr.t("Open these directions in a browser")
                    flat: true
                    onClicked: win.openDirections()
                }
            }
        }
    }

    Process {
        id: geoProc
        stdout: StdioCollector {
            onStreamFinished: {
                win.searching = false;
                try {
                    const arr = JSON.parse(text);
                    if (!Array.isArray(arr) || arr.length === 0) {
                        win.searchError = Tr.t("No place found for that search");
                        return;
                    }
                    const r = arr[0];
                    const c = Object.assign({}, win.geoCache);
                    c[win.searchField] = r;              // remember this answer
                    const keys = Object.keys(c);
                    if (keys.length > 32) delete c[keys[0]];   // keep the cache small
                    win.geoCache = c;
                    win.applyGeoResult(r);
                } catch (e) {
                    win.searchError = Tr.t("Search failed — check the network and try again");
                }
            }
        }
        onExited: code => {
            if (code !== 0 && win.searching) {
                win.searching = false;
                win.searchError = Tr.t("Search failed — check the network and try again");
            }
        }
    }
}
