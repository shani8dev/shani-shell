pragma Singleton
// Clipboard history from cliphist (fed by `wl-paste --watch cliphist store`,
// started by the niri session). Picking an entry puts it back on the clipboard.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property var entries: []        // [{ id, text, image, preview }]; originOf(text) says where one came from
    // where an entry came from, when Shani Link put it there from the paired phone
    // (shani-link's clipboard_sync.py writes it, keyed by the text's first 60
    // characters with whitespace collapsed - what cliphist's list shows can match)
    property var origins: ({})
    function originOf(text) {
        const o = origins[String(text).split(/\s+/).filter(x => x).join(" ").slice(0, 60)];
        return o ? o.device : "";
    }
    FileView {
        id: originFile
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/shani-link/clipboard-origin.json"
        watchChanges: true
        printErrors: false                 // none until something comes from the phone
        onFileChanged: reload()
        onLoaded: { try { root.origins = JSON.parse(text()) || {}; } catch (e) {} }
    }
    readonly property string cache: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-clip"
    property bool available: false

    function refresh() {
        // a watch on a file that is not there yet never fires: read it again each time
        originFile.reload();
        list.running = true;
    }
    // the keys that paste in the window being typed into: terminals take
    // Ctrl+Shift+V (Ctrl+V is their own key there), everything else Ctrl+V
    readonly property var terminals: ["foot", "footclient", "kitty", "alacritty", "org.gnome.ptyxis", "org.gnome.console",
        "org.kde.konsole", "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "xterm", "shani-pad-terminal"]
    function pasteKeys() {
        // the window the launcher was opened over: while the launcher holds the
        // keyboard niri reports no window focused, so the last one is it
        const w = Niri.focusedWindow || Niri.mru()[0];
        const id = ((w && w.app_id) || "").toLowerCase();
        return terminals.indexOf(id) >= 0 || /term/.test(id)
            ? ["-M", "ctrl", "-M", "shift", "-k", "v", "-m", "shift", "-m", "ctrl"] : ["-M", "ctrl", "-k", "v", "-m", "ctrl"];
    }
    // picked in the launcher (Win+V's way): onto the clipboard, then pasted into the
    // window the person was in - pictures and formatting too, which typing can't
    function copyAndPaste(entry) {
        Quickshell.execDetached(["sh", "-c", 'cliphist decode "$1" | wl-copy; sleep 0.35; shift; exec wtype "$@"', "sh", entry.id].concat(pasteKeys()));
    }
    function setAndPaste(text) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy; sleep 0.35; shift; exec wtype "$@"', "sh", text].concat(pasteKeys()));
    }
    // typed where the person was, the clipboard left as it is (an emoji, Win+.'s way)
    function typeText(text) {
        Quickshell.execDetached(["sh", "-c", 'sleep 0.35; exec wtype -- "$1"', "sh", text]);
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
        Quickshell.execDetached(["sh", "-c", 'sleep 0.35; t=$(wl-paste --no-newline --type text 2>/dev/null) || exit 0; printf "%s" "$t" | wl-copy; sleep 0.1; shift; exec wtype "$@"', "sh"].concat(pasteKeys()));
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
