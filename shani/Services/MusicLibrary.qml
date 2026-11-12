pragma Singleton
// The music in ~/Music, by album and artist, and the videos in ~/Videos (bridge/music-library.py reads the
// tags with ffprobe, and keeps them, so a second look reads nothing). The
// Media Player's Library shows it and plays it through PlayQueue.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_MUSIC_LIBRARY_TOOL") || "/usr/lib/shani-shell/music-library.py"
    property var songs: []        // [{ path, title, artist, album, albumArtist, track, disc, year, duration, cover }]
    property bool scanning: false
    property bool scanned: false
    // [{ key, title, artist, year, cover, songs: [...] }], by artist then title
    readonly property var albums: {
        const by = {}, out = [];
        for (const s of songs) {
            const artist = s.albumArtist || s.artist;
            const key = artist + "\u0001" + s.album;
            if (!by[key]) {
                by[key] = { key: key, title: s.album, artist: artist, year: s.year, cover: s.cover, songs: [] };
                out.push(by[key]);
            }
            by[key].songs.push(s);
            if (!by[key].cover && s.cover) by[key].cover = s.cover;
        }
        return out;
    }
    // [{ name, albums: n, songs: n }]
    readonly property var artists: {
        const by = {};
        for (const a of albums) {
            const e = by[a.artist] || (by[a.artist] = { name: a.artist, albums: 0, songs: 0 });
            e.albums++;
            e.songs += a.songs.length;
        }
        return Object.values(by).sort((a, b) => a.name.localeCompare(b.name));
    }

    // ~/Videos, newest first: [{ path, title, folder, duration, thumb, time }]
    property var videos: []
    property bool videosScanned: false
    // a folder of them is a series or a trip: [{ name, videos: [...] }], the loose ones first
    readonly property var videoFolders: {
        const by = {}, out = [];
        for (const v of videos) {
            if (!by[v.folder]) { by[v.folder] = { name: v.folder, videos: [] }; out.push(by[v.folder]); }
            by[v.folder].videos.push(v);
        }
        for (const f of out) f.videos.sort((a, b) => a.path.localeCompare(b.path, undefined, { numeric: true }));
        return out.sort((a, b) => (a.name === "") === (b.name === "") ? 0 : a.name === "" ? -1 : 1);
    }
    function scanVideos() { if (!videoScanner.running) { scanning = true; videoScanner.running = true; } }
    Process {
        id: videoScanner
        command: ["python3", root.tool, "videos"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.videos = JSON.parse(text).videos || []; } catch (e) {}
                root.videosScanned = true;
                root.scanning = scanner.running;
            }
        }
        onExited: root.scanning = scanner.running
    }
    function scan() {
        if (scanner.running)
            return;
        scanning = true;
        scanner.running = true;
    }
    Process {
        id: scanner
        command: ["python3", root.tool, "scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.songs = JSON.parse(text).songs || []; } catch (e) {}
                root.scanning = false;
                root.scanned = true;
            }
        }
        onExited: root.scanning = false
    }
    function play(list, index) { PlayQueue.playList(list.map(s => s.path), index || 0); }
}
