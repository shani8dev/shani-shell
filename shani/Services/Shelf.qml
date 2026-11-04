pragma Singleton
// The shelf (after ChromeOS's Tote and macOS's Yoink): files you parked - dropped
// on the dock's Shelf tile, kept by reference until put away, across restarts -
// then the newest screenshots, recordings, Lens snippets and downloads, a click
// from the sidebar: open, drag out into an app, convert, share.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property var recent: []             // [{ path, name, image, when }]
    property var parked: []             // paths, newest first
    readonly property var items: parked.map(p => entry(p, true)).concat(recent.filter(r => parked.indexOf(r.path) < 0))
    function entry(p, isParked) {
        const name = p.split("/").pop();
        return { path: p, name: name, image: /\.(png|jpe?g|webp|gif)$/i.test(p), parked: isParked };
    }
    // dropped on the dock's Shelf tile (or `qs ipc call shani shelfPark`)
    function park(paths) {
        const add = [].concat(paths).map(p => String(p).replace(/^file:\/\//, "")).map(p => decodeURIComponent(p)).filter(p => p !== "");
        root.parked = add.concat(root.parked.filter(p => add.indexOf(p) < 0)).slice(0, 50);
        store.setText(JSON.stringify(root.parked));
    }
    function unpark(path) {
        root.parked = root.parked.filter(p => p !== path);
        store.setText(JSON.stringify(root.parked));
    }
    FileView {
        id: store
        path: Quickshell.statePath("shelf-parked.json")
        onLoaded: { try { root.parked = JSON.parse(text()); } catch (e) {} }
    }

    function refresh() { list.running = true; }

    Process {
        id: list
        command: ["sh", "-c", 'p="${XDG_PICTURES_DIR:-$HOME/Pictures}"; v="${XDG_VIDEOS_DIR:-$HOME/Videos}"; d="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"; find "$p/Screenshots" "$v/Recordings" "$d" -maxdepth 1 -type f -mtime -7 -printf "%T@\\t%p\\n" 2>/dev/null | sort -rn | head -12']
        stdout: StdioCollector {
            onStreamFinished: {
                root.recent = text.trim().split("\n").filter(l => l.indexOf("\t") > 0).map(l => {
                    const [t, p] = l.split("\t");
                    return Object.assign(root.entry(p, false), { when: Number(t) });
                });
            }
        }
    }
}
