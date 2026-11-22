pragma Singleton
// What a media file is made of, for the Media Player's header: the picture
// size, the codec and the bitrate — the first thing a person checks when a
// video looks wrong or a file will not play elsewhere.
//
// `mediainfo` is optional: without it the player simply shows no line.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_MEDIAINFO_TOOL") || "mediainfo"

    // the file the player has loaded; a binding, so no one has to push it
    readonly property string file: PlayQueue.current
    property string line: ""          // "1920×1080 · H.264 · 4500 kb/s"
    property bool available: true

    // the file changed: look again (only for a real file, not a stream)
    onFileChanged: {
        if (!file || /^https?:/.test(file)) { line = ""; return; }
        info.running = false;
        info.running = true;
    }

    function rate(bits) {
        if (!bits) return "";
        return bits >= 1000000 ? Math.round(bits / 100000) / 10 + " Mb/s" : Math.round(bits / 1000) + " kb/s";
    }

    // "--Output=JSON" keeps the parse small and locale-free
    Process {
        id: info
        command: ["sh", "-c", 'command -v "$1" >/dev/null 2>&1 || exit 3; "$1" --Output=JSON "$2" 2>/dev/null', "sh", root.tool, root.file]
        stdout: StdioCollector {
            onStreamFinished: {
                let data = null;
                try { data = JSON.parse(text); } catch (e) { root.line = ""; return; }
                const tracks = ((data || {}).media || {}).track || [];
                const video = tracks.filter(t => t["@type"] === "Video")[0];
                const audio = tracks.filter(t => t["@type"] === "Audio")[0];
                if (video) {
                    const size = video.Width && video.Height ? video.Width + "×" + video.Height + " · " : "";
                    root.line = size + (video.Format || "") + (video.BitRate ? " · " + root.rate(video.BitRate) : "");
                } else if (audio) {
                    root.line = (audio.Format || "") + (audio.BitRate ? " · " + root.rate(audio.BitRate) : "");
                } else {
                    const general = tracks.filter(t => t["@type"] === "General")[0];
                    root.line = (general && general.Format) || "";
                }
            }
        }
        onExited: code => { if (code === 3) root.available = false; }
    }
}