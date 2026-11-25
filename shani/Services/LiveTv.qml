pragma Singleton
// Live TV in the Media Player, the Hypnotix idea: the person's own M3U playlist
// (a URL or a local file) becomes a channel list grouped as the playlist says.
// No channels are bundled here. A channel plays through PlayQueue like a radio
// stream; the shell's QtMultimedia player opens the URL directly.
// Asked only while the Live TV page is open. SHANI_LIVETV_TOOL (tests).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_LIVETV_TOOL"), "live-tv.py")
    property var channels: []              // [{ name, url, group, logo, id }]
    property string source: Settings.data.liveTvSource || ""
    property string group: ""              // "" = every group
    property string search: ""
    property bool loading: false
    property string error: ""
    property bool builtIn: false          // showing the free starter channels, not a saved playlist
    readonly property string freeTvUrl: "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8"

    readonly property var groups: {
        const seen = {}, out = [];
        for (const c of root.channels) {
            const g = c.group || Tr.t("Other");
            if (!seen[g]) { seen[g] = true; out.push(g); }
        }
        return out.sort();
    }
    readonly property var shown: root.channels.filter(c =>
        (!root.group || (c.group || Tr.t("Other")) === root.group)
        && (!root.search || (c.name + " " + (c.group || "")).toLowerCase().indexOf(root.search.toLowerCase()) >= 0))

    // A few free, legal public broadcaster streams so the page has something on
    // first open, like Hypnotix's default provider. No content is bundled by us.
    function loadDefaults() {
        root.builtIn = true;
        root.error = "";
        root.loading = true;
        fetch.command = ["python3", root.tool, "defaults"];
        fetch.running = true;
    }
    function load(src) {
        const s = String(src || "").trim();
        if (!s) { root.error = Tr.t("Add a playlist URL or file first"); return; }
        root.builtIn = false;
        root.source = s;
        Settings.data.liveTvSource = s;
        root.error = "";
        root.loading = true;
        fetch.command = ["python3", root.tool, s];
        fetch.running = true;
    }
    Process {
        id: fetch
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { error: Tr.t("The playlist could not be read") }; }
                if (r && !Array.isArray(r) && r.error) {
                    root.error = r.error;
                    root.channels = [];
                } else {
                    root.channels = (Array.isArray(r) ? r : []).filter(c => c.name && c.url);
                    root.error = "";
                }
            }
        }
    }

    function play(c) {
        if (!c || !c.url) return;
        PlayQueue.playStream(c.url, c.name, c.logo);
    }
}
