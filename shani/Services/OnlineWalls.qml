pragma Singleton
// Wallpapers found online (noctalia's): Wallhaven's search, asked only when the
// person searches in Settings > Personal, safe-for-work and general only, at
// least 1920x1080. A picked one is saved to ~/Pictures/Wallpapers - then it is
// one of the wallpapers like any other, and works offline.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string endpoint: Quickshell.env("SHANI_WALLHAVEN_URL") || "https://wallhaven.cc/api/v1/search"
    readonly property string dir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    property var results: []             // [{ id, thumb, full, size }]
    property bool searching: look.running
    property bool fetching: get.running
    property string error: ""
    signal saved(string path)
    property string lastSaved: ""
    onSaved: path => lastSaved = path

    function search(q) {
        error = "";
        look.command = ["curl", "-fsS", "--max-time", "12", "-G", endpoint, "-A", "shani-shell",
                        "--data-urlencode", "q=" + (q || ""), "-d", "purity=100", "-d", "categories=100",
                        "-d", "sorting=" + (q ? "relevance" : "toplist"), "-d", "atleast=1920x1080"];
        look.running = true;
    }
    function fetch(item) {
        if (!item || fetching)
            return;
        const ext = (item.full.split(".").pop() || "jpg").toLowerCase();
        get.target = dir + "/wallhaven-" + item.id + "." + ext;
        get.command = ["sh", "-c", 'mkdir -p "$1" && curl -fsS --max-time 60 -A shani-shell -o "$2.part" "$3" && mv "$2.part" "$2"',
                       "sh", dir, get.target, item.full];
        get.running = true;
    }
    Process {
        id: look
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.results = (JSON.parse(text).data || []).slice(0, 24).map(w => ({
                        id: String(w.id), thumb: (w.thumbs || {}).small || "", full: w.path || "", size: w.resolution || "" }))
                        .filter(w => w.full !== "" && /^[A-Za-z0-9]+$/.test(w.id));
                } catch (e) {
                    root.results = [];
                }
            }
        }
        onExited: code => { if (code !== 0) root.error = Tr.t("Could not reach Wallhaven"); }
    }
    Process {
        id: get
        property string target: ""
        onExited: code => code === 0 ? root.saved(target) : (root.error = Tr.t("The picture did not download"))
    }
}
