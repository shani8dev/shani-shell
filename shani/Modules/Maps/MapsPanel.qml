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

AppWindow {
    id: win
    // who is asking, as OpenStreetMap's tile and Nominatim policies require
    readonly property string userAgent: "shani-shell-maps/1.0 (+https://github.com/shani8dev/shani-shell)"
    readonly property string tileCache: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/shani-shell/map-tiles"
    appName: "Maps"
    visible: Ui.maps
    onGone: Ui.maps = false
    margins: 0
    implicitWidth: 900
    implicitHeight: 620

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
    property string searchError: ""
    property string searchField: ""
    property bool searching: false
    readonly property string routeUrl: {
        if (win.mapLat === 0 && win.mapLon === 0)
            return "";
        const from = Location.available ? (Location.lat + "," + Location.lon) : "";
        return "https://www.openstreetmap.org/directions?from=" + encodeURIComponent(from) + "&to=" + encodeURIComponent(win.mapLat + "," + win.mapLon);
    }
    // the place found (the pin), and the way to it
    property real pinLat: 0
    property real pinLon: 0
    property bool routeAsked: false
    property string routeProfile: "driving"   // driving | foot | bike (OSRM's profiles)
    property bool routing: false
    property string routeError: ""
    property var route: []                    // [[lat, lon], ...]
    property real routeDistance: 0            // metres
    property real routeDuration: 0            // seconds
    property var routeSteps: []
    property real fromLat: 0                  // a typed start, when there is no location
    property real fromLon: 0
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
        const url = routeServer + "/route/v1/" + routeProfile + "/" + sLon + "," + sLat + ";" + pinLon + "," + pinLat + "?overview=full&geometries=geojson&steps=true";
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
                                     tilesDrawn: tilesDrawn, tilesDistinct: tilesDistinct })
    onReportChanged: Ui.mapsView = report
    Connections {
        target: Ui
        function onMapsAsked(what, arg) {
            if (what === "pan") { const [dx, dy] = arg.split(",").map(Number); win.panBy(dx, dy); }
            else if (what === "zoom") win.zoomBy(Number(arg));
            else if (what === "directions") { win.routeProfile = arg || win.routeProfile; win.directions(); }
            else if (what === "from") win.directionsFrom(arg);
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
    // Nominatim geocode: search a place, zoom to it, describe it
    function geoCode(query) {
        const q = String(query || "").trim();
        if (q === "" || searching)
            return;
        searchError = "";
        searching = true;
        searchField = q;
        // fields: display_name, lat, lon, type, class
        const url = win.searchUrl + "?format=jsonv2&limit=1&accept-language=" + encodeURIComponent(Tr.lang || "en") + "&q=" + encodeURIComponent(q);
        geoProc.command = ["curl", "-sf", "--max-time", "10", "-H", "User-Agent: " + win.userAgent, url];
        geoProc.running = true;
    }
    function openDirections() {
        if (routeUrl !== "")
            Quickshell.execDetached(["xdg-open", routeUrl]);
    }

    function tileXY(cxp, cyp) {
        const tx = Math.floor((cxp - (grid.width / 2 - 0)) / tile) + Math.floor(win.px / tile);
        const ty = Math.floor(cyp / tile) + Math.floor(win.py / tile);
        return { x: Math.round(win.px / tile + (cxp - grid.width / 2) / tile), y: Math.round(win.py / tile + (cyp - grid.height / 2) / tile) };
    }

    Item {
        id: blurCard
        anchors.fill: parent

        ColumnLayout {
            id: col
            x: 20; y: 20
            width: parent.width - 40
            height: parent.height - 40
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: win.placeName !== "" ? win.placeName : (Location.available ? (Weather.zoneCity || Tr.t("Where you are")) : "")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                IconButton { icon: "mark-location"; size: 28; tip: "Recenter"; onClicked: win.recenter(); }
                IconButton { icon: "view-refresh"; size: 28; onClicked: Location.refresh(); }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: mapSearch
                    Layout.fillWidth: true
                    placeholder: "Search city or place"
                    label: "Search city or place"
                    text: win.searchField || Ui.mapsQuery || ""
                    onAccepted: { Ui.mapsQuery = text; win.geoCode(text); }
                }
                Button { text: win.searching ? "…" : "Search"; kind: "primary"; enabled: !win.searching && mapSearch.text.trim() !== ""; onClicked: { Ui.mapsQuery = mapSearch.text.trim(); win.geoCode(mapSearch.text.trim()); } }
                Button { visible: win.pinLat !== 0 || win.pinLon !== 0; text: Tr.t("Directions"); kind: "outline"; onClicked: win.directions() }
            }
            Text {
                visible: win.searchError !== ""
                Layout.fillWidth: true
                text: win.searchError
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
                wrapMode: Text.WordWrap
            }
            Text {
                visible: win.placeDesc !== ""
                Layout.fillWidth: true
                text: win.placeDesc + (win.placeType ? " · " + win.placeType : "") + " (" + win.mapLat.toFixed(4) + ", " + win.mapLon.toFixed(4) + ")"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
                wrapMode: Text.WordWrap
            }

            // ---- the map: as many tiles as fill it, dragged to pan, wheel or +/- to zoom ----
            Rectangle {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 320
                radius: Theme.radiusSmall
                color: Theme.hover
                clip: true
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
                    width: 16; height: 16; radius: 8
                    color: Theme.accent
                    border.width: 3; border.color: "white"
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
                    anchors { right: parent.right; top: parent.top; margins: 10 }
                    width: 40
                    height: zoomCol.implicitHeight + 8
                    radius: 10
                    color: Theme.alpha(Theme.bg, 0.92)
                    border.width: 1
                    border.color: Theme.border
                    ColumnLayout {
                        id: zoomCol
                        anchors.centerIn: parent
                        spacing: 2
                        IconButton { icon: "zoom-in"; size: 32; tip: Tr.t("Zoom in"); onClicked: win.zoomBy(1) }
                        IconButton { icon: "zoom-out"; size: 32; tip: Tr.t("Zoom out"); onClicked: win.zoomBy(-1) }
                    }
                }
                Text {
                    anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
                    text: "© OpenStreetMap contributors"
                    color: Theme.text
                    style: Text.Outline
                    styleColor: Theme.bg
                    font.family: Theme.font
                    font.pixelSize: 10 * Theme.fontScale
                }
            }

            // ---- directions: how, how far, how long, and the turns ----
            ColumnLayout {
                Layout.fillWidth: true
                visible: win.routeAsked
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
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
                        font.pixelSize: 12 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    IconButton { icon: "window-close"; size: 26; tip: Tr.t("Close directions"); onClicked: win.clearRoute() }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !Location.available || win.routeError !== ""
                    TextField {
                        id: fromField
                        Layout.fillWidth: true
                        placeholder: Tr.t("Start from (a place or an address)")
                        onAccepted: win.directionsFrom(text)
                    }
                    Button { text: Tr.t("Go"); onClicked: win.directionsFrom(fromField.text) }
                }
                ListView {
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
                        font.pixelSize: 11 * Theme.fontScale
                    }
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
                        win.searchError = "No place found for that search";
                        return;
                    }
                    const r = arr[0];
                    const lat = parseFloat(r.lat);
                    const lon = parseFloat(r.lon);
                    if (!isFinite(lat) || !isFinite(lon)) {
                        win.searchError = "No place found for that search";
                        return;
                    }
                    // Nominatim fields: display_name, lat, lon, type, class
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
                    Ui.mapsQuery = win.searchField;
                    Ui.mapsPlace = name;
                    Ui.mapsLat = lat;
                    Ui.mapsLon = lon;
                } catch (e) {
                    win.searchError = "Search failed — check the network and try again";
                }
            }
        }
        onExited: code => {
            if (code !== 0 && win.searching) {
                win.searching = false;
                win.searchError = "Search failed — check the network and try again";
            }
        }
    }
}
