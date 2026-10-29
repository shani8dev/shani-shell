pragma Singleton
// Clipboard history from cliphist (fed by `wl-paste --watch cliphist store`,
// started by the niri session). Picking an entry puts it back on the clipboard.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property var entries: []        // [{ id, text, image, preview }]
    readonly property string cache: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-clip"
    property bool available: false

    function refresh() {
        list.running = true;
    }
    function copy(entry) {
        Quickshell.execDetached(["sh", "-c", 'cliphist decode "$1" | wl-copy', "sh", entry.id]);
    }
    // pinned texts (Settings.clipPins): above the history, kept through clearing it
    function pin(entry) {
        pinDecode.command = ["cliphist", "decode", entry.id];
        pinDecode.running = true;
    }
    function unpin(text) { Settings.data.clipPins = Array.from(Settings.data.clipPins).filter(t => t !== text); }
    Process {
        id: pinDecode
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text;
                if (t && Array.from(Settings.data.clipPins).indexOf(t) < 0)
                    Settings.data.clipPins = [t].concat(Array.from(Settings.data.clipPins)).slice(0, 25);
            }
        }
    }
    // the clipboard without its formatting, pasted where the person was (the
    // launcher closes first so the window behind it has the keyboard again)
    function pastePlain() {
        Quickshell.execDetached(["sh", "-c", 'sleep 0.35; t=$(wl-paste --no-newline --type text 2>/dev/null) || exit 0; printf "%s" "$t" | wl-copy; sleep 0.1; wtype -M ctrl -k v -m ctrl']);
    }

    // one entry out of the history: cliphist deletes the line it is given
    function remove(entry) {
        Quickshell.execDetached(["sh", "-c", 'cliphist list | grep -m1 "^$1	" | cliphist delete', "sh", entry.id]);
        entries = entries.filter(e => e.id !== entry.id);
    }
    // the history and what is on the clipboard now. Not --clear: wl-clip-persist
    // restores the last contents when the clipboard empties, and the secret is
    // back in the history at once. An empty text replaces it (cliphist stores
    // nothing empty), then the history goes once that has settled.
    function wipe() {
        Quickshell.execDetached(["sh", "-c", "printf '' | wl-copy; printf '' | wl-copy --primary; sleep 0.5; cliphist wipe"]);
        entries = [];
    }

    Process {
        id: list
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = text.split("\n").filter(l => l.indexOf("\t") > 0).slice(0, 100).map(l => {
                    const i = l.indexOf("\t");
                    const t = l.slice(i + 1);
                    // cliphist lists a picture as "[[ binary data 81 KiB png 1920x1080 ]]"
                    const m = t.match(/^\[\[ binary data .* (png|jpe?g|webp|gif|bmp) (\d+x\d+) \]\]$/);
                    const id = l.slice(0, i);
                    return m ? { id: id, text: "Image " + m[2].replace("x", "×"), image: true, preview: root.cache + "/" + id + "." + m[1] }
                             : { id: id, text: t, image: false, preview: "" };
                });
                // decode the newest pictures once, for their thumbnails
                const imgs = root.entries.filter(e => e.image).slice(0, 12);
                if (imgs.length) {
                    thumbs.command = ["sh", "-c", 'd="$1"; shift; mkdir -p "$d"; for e in "$@"; do id="${e%%:*}"; out="${e#*:}"; [ -f "$out" ] || cliphist decode "$id" > "$out"; done', "sh", root.cache]
                        .concat(imgs.map(e => e.id + ":" + e.preview));
                    thumbs.running = true;
                }
            }
        }
    }
    Process { id: thumbs }
    Process {
        running: true
        command: ["sh", "-c", "command -v cliphist"]
        onExited: code => root.available = code === 0
    }
}
