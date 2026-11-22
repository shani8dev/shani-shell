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

    // ---- password / secret exclusion -------------------------------------------
    // Text that looks like a password or token is never stored in the history.
    // Checked by the launcher before pinning, and by the `wl-paste --watch`
    // wrapper (bridge/clipboard-watch.sh) before `cliphist store`.
    readonly property bool excludeSecrets: Settings.data.clipboardExcludeSecrets !== false  // on by default
    // a simple heuristic: long random-looking strings, API keys, "password", etc.
    function looksSecret(text) {
        const t = String(text || "");
        if (t.length < 8) return false;
        // common secret patterns
        if (/^(sk-|pk-|ghp_|xox[baprs]-|AKIA|AIza)/i.test(t)) return true;  // API keys
        if (/^password\s*[:=]/i.test(t)) return true;                       // "password: …"
        if (/^Bearer\s+/i.test(t)) return true;                             // bearer token
        // long base64/hex string (32+ chars, no spaces)
        if (/^[A-Za-z0-9+/=]{32,}$/.test(t)) return true;
        // a line that is just a long random-looking string
        if (/^[A-Za-z0-9!@#$%^&*()_+-=]{20,}$/.test(t) && !/\s/.test(t)) {
            // has a mix of upper, lower, and numbers — likely a password
            const hasUpper = /[A-Z]/.test(t), hasLower = /[a-z]/.test(t), hasNum = /\d/.test(t);
            if (hasUpper && hasLower && hasNum) return true;
        }
        return false;
    }

    // ---- quick text changes ----------------------------------------------------
    // transform a text for pasting: "plain" (strip HTML/RTF), "upper" (UPPERCASE),
    // "lower" (lowercase), "title" (Title Case), "trim" (strip whitespace)
    function transformText(text, mode) {
        let t = String(text || "");
        switch (mode) {
            case "plain":   t = t.replace(/<[^>]+>/g, "").replace(/&[a-z]+;/g, " ").trim(); break;
            case "upper":   t = t.toUpperCase(); break;
            case "lower":   t = t.toLowerCase(); break;
            case "title":   t = t.replace(/\w\S*/g, w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()); break;
            case "trim":    t = t.trim().replace(/\s+/g, " "); break;
        }
        return t;
    }
    function transformAndPaste(text, mode) {
        setAndPaste(root.transformText(text, mode));
    }

    // ---- encrypted history (optional) -------------------------------------------
    // bridge/clipboard-crypto.py keeps cliphist's DB encrypted at rest with
    // gpg; every cliphist call goes through its `wrap` command, and the
    // watcher uses bridge/clipboard-watch.sh. The key is in the keyring.
    readonly property string crypto: Quickshell.env("SHANI_CLIPBOARD_CRYPTO") || "/usr/lib/shani-shell/clipboard-crypto.py"
    // the watcher lives beside clipboard-crypto.py: bridge/clipboard-watch.sh
    readonly property string watcher: crypto.replace(/[^/]*$/, "clipboard-watch.sh")
    readonly property bool encrypted: Settings.data.clipboardEncrypted === true
    function restartWatcher() {
        // The niri session spawns `wl-paste --watch cliphist store` directly
        // (dev/niri/session.kdl:85), so toggling encryption never reaches
        // clipboard-watch.sh and the live watcher keeps writing a plaintext DB.
        // Replace it with one that feeds through the wrapper, which re-checks
        // crypto status on every store. The [t] keeps pkill -f from matching
        // this very command line. If the session wiring is fixed instead, that
        // line should become: spawn-at-startup "wl-paste" "--watch" "bridge/clipboard-watch.sh"
        Quickshell.execDetached(["sh", "-c",
            'pkill -f "wl-paste.*--watch.*cliphis[t].*store" 2>/dev/null; '
            + 'pf="$1/watcher.pid"; mkdir -p "$1"; '
            + '[ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null; '
            + 'echo $$ > "$pf"; exec wl-paste --watch "$2"',
            "sh", cache, watcher]);
    }
    function setEncrypted(on) {
        Settings.data.clipboardEncrypted = on;
        Quickshell.execDetached(["python3", crypto, on ? "enable" : "disable"]);
        restartWatcher();
        notifyEncrypted(on);
    }
    function notifyEncrypted(on) {
        Quickshell.execDetached(["notify-send", "-a", Tr.t("Clipboard"),
            on ? Tr.t("Clipboard history is now encrypted at rest")
               : Tr.t("Clipboard history is no longer encrypted")]);
    }
    // Run a cliphist command, wrapped when encryption is on.
    function clip(args) {
        return encrypted ? ["python3", crypto, "wrap"].concat(args) : ["cliphist"].concat(args);
    }

    function refresh() {
        // a watch on a file that is not there yet never fires: read it again each time
        originFile.reload();
        // restart the process: setting running=true when it is already true is a no-op
        list.running = false;
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
        Quickshell.execDetached(["sh", "-c", '"$@" decode "$2" | wl-copy; sleep 0.35; shift 2; exec wtype "$@"'].concat(clip([]), ["sh", entry.id]).concat(pasteKeys()));
    }
    function setAndPaste(text) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy; sleep 0.35; shift; exec wtype "$@"', "sh", text].concat(pasteKeys()));
    }
    // typed where the person was, the clipboard left as it is (an emoji, Win+.'s way)
    function typeText(text) {
        Quickshell.execDetached(["sh", "-c", 'sleep 0.35; exec wtype -- "$1"', "sh", text]);
    }
    function copy(entry) {
        Quickshell.execDetached(["sh", "-c", '"$@" decode "$2" | wl-copy'].concat(clip([]), ["sh", entry.id]));
    }
    // pinned texts (Settings.clipPins): above the history, kept through clearing it
    function pin(entry) {
        pinDecode.command = clip(["decode", entry.id]);
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
        // list through the wrapper, then feed the exact line to `wrap delete`
        Quickshell.execDetached(["sh", "-c",
            'line=$("$@" list | grep -m1 "^$2\\t") || exit 0; printf "%s\\n" "$line" | python3 "$3" wrap delete'
        ].concat(clip([]), ["sh", entry.id, crypto]));
        entries = entries.filter(e => e.id !== entry.id);
    }
    // the history and what is on the clipboard now. Not --clear: wl-clip-persist
    // restores the last contents when the clipboard empties, and the secret is
    // back in the history at once. An empty text replaces it (cliphist stores
    // nothing empty), then the history goes once that has settled.
    function wipe() {
        Quickshell.execDetached(["sh", "-c", "printf '' | wl-copy; printf '' | wl-copy --primary; sleep 0.5; \"$@\"", "sh"].concat(clip(["wipe"])));
        entries = [];
    }

    Process {
        id: list
        command: root.clip(["list"])
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
                    // keep the cliphist/python command in "$@" and pass the
                    // id:path list separately, or the loop would decode the
                    // command's own tokens (e.g. `cliphist decode cliphist`)
                    // and leave stray files behind
                    thumbs.command = ["sh", "-c",
                        'd="$1"; list="$2"; shift 2; mkdir -p "$d"; '
                        + 'printf "%s\\n" "$list" | while IFS= read -r e; do '
                        + '[ -z "$e" ] && continue; id="${e%%:*}"; out="${e#*:}"; '
                        + '[ -f "$out" ] || "$@" decode "$id" > "$out"; done',
                        "sh", root.cache, imgs.map(e => e.id + ":" + e.preview).join("\n")]
                        .concat(root.clip([]));
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
