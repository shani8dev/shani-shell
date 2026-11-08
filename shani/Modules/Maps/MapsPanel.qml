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
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.maps
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-maps"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: Ui.maps = false }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.maps = false }

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
        const url = "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&accept-language=" + encodeURIComponent(Tr.lang || "en") + "&q=" + encodeURIComponent(q);
        geoProc.command = ["curl", "-sf", "--max-time", "10", "-H", "User-Agent: ShaniOS-Maps/1.0", url];
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

    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Math.min(900, parent.width - 80)
        height: Math.min(620, parent.height - 120)
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            x: 20; y: 20
            width: parent.width - 40
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Icon { name: "mappin"; size: 20; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: win.placeName !== "" ? win.placeName : (Location.available ? "Maps · " + (Weather.zoneCity || "current location") : "Maps")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                IconButton { icon: "location"; size: 28; tip: "Recenter"; onClicked: win.recenter(); }
                IconButton { icon: "view-refresh"; size: 28; onClicked: Location.refresh(); }
                IconButton { icon: "window-close"; size: 28; onClicked: Ui.maps = false }
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
                Button { visible: win.routeUrl !== ""; text: "Directions"; kind: "outline"; onClicked: win.openDirections() }
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

            Rectangle {
                id: grid
                Layout.fillWidth: true
                Layout.preferredHeight: 380
                radius: Theme.radiusSmall
                color: Theme.hover
                clip: true
                // 4x4 tiles centred on the location
                Grid {
                    anchors.centerIn: parent
                    columns: 4; rows: 4; spacing: 0
                    Repeater {
                        model: 16
                        Rectangle {
                            width: 256; height: 256
                            color: "transparent"
                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                source: {
                                    const dx = (index % 4) - 1.5, dy = Math.floor(index / 4) - 1.5;
                                    const n = Math.pow(2, win.z);
                                    const x = Math.floor(win.px / win.tile + dx);
                                    const y = Math.min(n - 1, Math.max(0, Math.floor(win.py / win.tile + dy)));
                                    return "https://tile.openstreetmap.org/" + win.z + "/" + x + "/" + y + ".png";
                                }
                            }
                        }
                    }
                }
                // centre marker + coordinates
                Rectangle {
                    anchors.centerIn: parent
                    width: 14; height: 14
                    radius: 7
                    color: Theme.accent
                    border.width: 2; border.color: "white"
                }
                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (win.mapLat !== 0 || win.mapLon !== 0) ? (win.mapLat.toFixed(4) + ", " + win.mapLon.toFixed(4)) : (Location.available ? (Location.lat.toFixed(4) + ", " + Location.lon.toFixed(4)) : "location off or unknown — search a place above")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Choice { text: "Zoom in"; onClicked: { win.z = Math.min(19, win.z + 1); Ui.mapsZoom = win.z; } }
                Choice { text: "Zoom out"; onClicked: { win.z = Math.max(3, win.z - 1); Ui.mapsZoom = win.z; } }
                Item { Layout.fillWidth: true }
                Text {
                    text: "© OpenStreetMap contributors"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
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
