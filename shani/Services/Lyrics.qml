pragma Singleton
// Synced lyrics for the track playing, from LRCLIB (lrclib.net: free, no
// account). A network call to a third party, so off until switched on (Settings >
// Sound), and made only while the media card is on screen - once per track.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property bool wanted: false          // the media card is showing
    property var lines: []               // [{ t: seconds, text }]
    property string fetched: ""          // the track they are for
    readonly property string endpoint: Quickshell.env("SHANI_LYRICS_URL") || "https://lrclib.net/api/search"
    readonly property var player: Media.current
    readonly property string track: Settings.loaded && Settings.data.lyrics && wanted && player && player.trackTitle
        ? (player.trackArtist || "") + "\n" + player.trackTitle : ""
    onTrackChanged: if (track !== "" && track !== fetched) fetch()

    function fetch() {
        fetched = track;
        lines = [];
        const [artist, title] = track.split("\n");
        look.command = ["curl", "-fsS", "--max-time", "8", "-G", endpoint,
                        "-A", "shani-shell (https://github.com/shani8dev/shani-shell)",
                        "--data-urlencode", "track_name=" + title, "--data-urlencode", "artist_name=" + artist];
        look.running = true;
    }
    function parse(text) {
        try {
            const found = [].concat(JSON.parse(text)).find(x => x && x.syncedLyrics);
            lines = found ? found.syncedLyrics.split("\n")
                .map(l => /^\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$/.exec(l)).filter(m => m)
                .map(m => ({ t: Number(m[1]) * 60 + Number(m[2]), text: m[3] })) : [];
        } catch (e) {
            lines = [];
        }
    }
    // the line being sung at `pos` seconds
    function lineAt(pos) {
        let cur = "";
        for (const l of lines) {
            if (l.t > pos)
                break;
            cur = l.text;
        }
        return cur;
    }
    Process {
        id: look
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
}
