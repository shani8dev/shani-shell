pragma Singleton
// Internet radio (Shortwave parity), in the Media Player: stations from the
// community directory radio-browser.info (the one Shortwave uses) - searched,
// the most played, the ones near you (your country), by genre - and your
// favourites, kept in Settings. A station plays in the Media Player like a file.
// Asked only while the Radio page is open; a play is counted with the directory,
// as it asks of the apps that use it. SHANI_RADIO_API (tests): another server.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string api: Quickshell.env("SHANI_RADIO_API") || "https://de1.api.radio-browser.info"
    readonly property string userAgent: "shani-shell-radio/1.0 (+https://github.com/shani8dev/shani-shell)"
    property var stations: []               // [{ uuid, name, url, favicon, tags, country, codec, bitrate }]
    property string showing: ""             // favourites | popular | near | genre:<tag> | search:<words>
    property bool loading: false
    property string error: ""
    readonly property var favourites: Settings.data.radioFavourites || []
    readonly property string countryCode: (Qt.locale().name.split("_")[1] || "").toUpperCase()

    function station(s) {
        return { uuid: s.stationuuid || s.uuid || "", name: (s.name || "").trim(), url: s.url_resolved || s.url || "",
                 favicon: s.favicon || "", tags: (s.tags || "").split(",").slice(0, 3).join(", "),
                 country: s.countrycode || s.country || "", codec: s.codec || "", bitrate: s.bitrate || 0 };
    }
    function show(what) {
        root.showing = what;
        root.error = "";
        if (what === "favourites") { root.stations = root.favourites; return; }
        let path;
        if (what === "popular") path = "/json/stations/topclick/60";
        else if (what === "near") path = "/json/stations/bycountrycodeexact/" + encodeURIComponent(root.countryCode || "IN") + "?order=clickcount&reverse=true&limit=60";
        else if (what.startsWith("genre:")) path = "/json/stations/bytagexact/" + encodeURIComponent(what.slice(6)) + "?order=clickcount&reverse=true&limit=60";
        else if (what.startsWith("search:")) path = "/json/stations/search?name=" + encodeURIComponent(what.slice(7)) + "&order=clickcount&reverse=true&limit=60&hidebroken=true";
        else return;
        fetch.command = ["curl", "-sf", "--max-time", "15", "-A", root.userAgent, root.api + path];
        root.loading = true;
        fetch.running = true;
    }
    Process {
        id: fetch
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                let r = [];
                try { r = JSON.parse(text); } catch (e) { root.error = Tr.t("The station list could not be reached"); r = []; }
                root.stations = (Array.isArray(r) ? r : []).map(root.station).filter(s => s.url && s.name);
            }
        }
    }

    function isFavourite(s) { return !!s && root.favourites.some(f => f.url === s.url); }
    function toggleFavourite(s) {
        if (!s) return;
        Settings.data.radioFavourites = isFavourite(s) ? root.favourites.filter(f => f.url !== s.url) : root.favourites.concat([s]);
        if (root.showing === "favourites") root.stations = root.favourites;
    }
    function play(s) {
        if (!s || !s.url) return;
        PlayQueue.playStream(s.url, s.name, s.favicon);
        // radio-browser counts plays from the apps that use it (its own request)
        if (s.uuid && !Quickshell.env("SHANI_RADIO_NO_COUNT"))
            Quickshell.execDetached(["curl", "-sf", "--max-time", "10", "-A", root.userAgent, "-o", "/dev/null", root.api + "/json/url/" + s.uuid]);
    }
}
