pragma Singleton
// The shelf (after ChromeOS's Tote): the newest screenshots, recordings, Lens
// snippets and downloads, a click from the sidebar — open, copy the path,
// send to the phone, or ask Chronoa about one.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property var items: []              // [{ path, name, image, when }]

    function refresh() { list.running = true; }

    Process {
        id: list
        command: ["sh", "-c", 'p="${XDG_PICTURES_DIR:-$HOME/Pictures}"; v="${XDG_VIDEOS_DIR:-$HOME/Videos}"; d="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"; find "$p/Screenshots" "$v/Recordings" "$d" -maxdepth 1 -type f -mtime -7 -printf "%T@\\t%p\\n" 2>/dev/null | sort -rn | head -12']
        stdout: StdioCollector {
            onStreamFinished: {
                root.items = text.trim().split("\n").filter(l => l.indexOf("\t") > 0).map(l => {
                    const [t, p] = l.split("\t");
                    return { path: p, name: p.split("/").pop(), when: Number(t), image: /\.(png|jpe?g|webp|gif)$/i.test(p) };
                });
            }
        }
    }
}
