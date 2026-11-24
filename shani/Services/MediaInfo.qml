pragma Singleton
// What a media file is made of, for the Media Player's header and its
// properties panel: the picture size, the codec and the bitrate — the first
// thing a person checks when a video looks wrong or a file will not play
// elsewhere. The one probe's JSON is parsed once here and shared; the player
// never starts a second probe of the same file.
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
    property bool loading: false
    property var raw: ({})            // the parsed JSON of the one probe
    property var details: []          // [{ label, value }] for the properties panel

    // the file changed: look again (only for a real file, not a stream)
    onFileChanged: {
        root.raw = ({});
        root.details = [];
        if (!file || /^https?:/.test(file)) { line = ""; loading = false; return; }
        info.running = false;
        info.running = true;
        loading = true;
    }

    function rate(bits) {
        if (!bits) return "";
        return bits >= 1000000 ? Math.round(bits / 100000) / 10 + " Mb/s" : Math.round(bits / 1000) + " kb/s";
    }

    function clock(ms) {
        const t = Math.round((Number(ms) || 0) / 1000);
        const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
        return (h ? h + ":" + String(m).padStart(2, "0") : String(m)) + ":" + String(s).padStart(2, "0");
    }

    // every row the panel can show comes from the tracks already parsed below
    function detailsFor(data) {
        const tracks = ((data || {}).media || {}).track || [];
        const one = type => tracks.filter(t => t["@type"] === type)[0] || null;
        const general = one("General"), video = one("Video"), audio = one("Audio");
        const main = video || audio || general || ({});
        const out = [];
        if (general.Format) out.push({ label: Tr.t("Container"), value: general.Format });
        if (video && video.Width && video.Height)
            out.push({ label: Tr.t("Resolution"), value: video.Width + "×" + video.Height + " px" });
        if (main.Format) out.push({ label: Tr.t("Codec"), value: main.Format });
        const bits = main.BitRate || general.BitRate;
        if (bits) out.push({ label: Tr.t("Bitrate"), value: rate(bits) });
        if (main.Duration) out.push({ label: Tr.t("Duration"), value: clock(main.Duration) });
        if (video && video.FrameRate) out.push({ label: Tr.t("Frame rate"), value: video.FrameRate + " fps" });
        if (audio && audio.Channels) out.push({ label: Tr.t("Channels"), value: audio.Channels });
        if (audio && audio.SamplingRate) out.push({ label: Tr.t("Sample rate"), value: audio.SamplingRate + " Hz" });
        if (general.Title) out.push({ label: Tr.t("Title"), value: general.Title });
        return out;
    }

    // "--Output=JSON" keeps the parse small and locale-free
    Process {
        id: info
        command: ["sh", "-c", 'command -v "$1" >/dev/null 2>&1 || exit 3; "$1" --Output=JSON "$2" 2>/dev/null', "sh", root.tool, root.file]
        stdout: StdioCollector {
            onStreamFinished: {
                let data = null;
                try { data = JSON.parse(text); } catch (e) { root.line = ""; root.details = []; root.loading = false; return; }
                root.raw = data || ({});
                root.details = root.detailsFor(data);
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
                root.loading = false;
            }
        }
        onExited: code => {
            if (code === 3) root.available = false;
            if (code !== 0) { root.details = []; root.loading = false; }
        }
    }
}
