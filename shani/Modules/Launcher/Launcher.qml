// The launcher: full screen, one field, every kind of answer.
//
// Before you type: frequent apps, recent files, and the whole app grid with
// category chips. As you type, one ranked list in sections — top hit, apps,
// open windows, actions (a command palette for the shell: "dark style",
// "do not disturb", "lock" …), files, calculator, emoji, clipboard, the web —
// and on the right, Chronoa, one keystroke away (Ctrl+Enter), with a preview
// of the selected file or picture.
//
//   = 2*(3+4)  calculator  (also: 5 km in miles, 100 f to c, 2 gb in mib)
//   : smile    emoji       c text  clipboard
// Files are matched by name and by what is inside them (localsearch / rg / grep).
//   > cmd      run (Shift: in a terminal)             ? text  ask Chronoa
// Apps you launch often rank first (counts in Quickshell's state dir).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.launcher
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Ui.launcher ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Ui.launcher && Settings.data.blur ? fullRegion : null
    Region { id: fullRegion; item: backdrop }

    property int sel: 0
    property string category: "All"
    readonly property string q: search.text
    property var usage: ({})              // desktop id -> launches
    property var emoji: []                // [{ e, name }], loaded on first ":"
    property string emojiPath: ""
    property var recent: []               // [{ path, name, when }]
    property var found: []                // file search hits for the current query
    property var inside: []               // files whose contents match
    property var provided: []             // apps' own search results (GNOME SearchProvider2)
    readonly property string providersTool: Quickshell.env("SHANI_SEARCH_PROVIDERS_TOOL") || "/usr/lib/shani-shell/search-providers.py"
    Process {
        id: providerSearch
        property var terms: []
        command: ["python3", win.providersTool, "query"].concat(terms)
        stdout: StdioCollector { onStreamFinished: { try { win.provided = JSON.parse(text); } catch (e) { win.provided = []; } } }
    }

    // Quick Look (after macOS): the selected file previewed in the side pane —
    // pictures as they are, text files' first lines, a PDF's first page
    readonly property string lookPath: current && current.kind === "file" ? current.path : ""
    readonly property bool lookText: /\.(txt|md|log|conf|ini|json|yaml|yml|toml|csv|py|js|qml|sh|c|h|cpp|rs|go|html|css|xml)$/i.test(lookPath)
    readonly property bool lookPdf: /\.pdf$/i.test(lookPath)
    property string lookPdfImage: ""
    FileView {
        id: lookFile
        path: win.lookText ? win.lookPath : ""
        printErrors: false
    }
    Process {
        id: pdfThumb
        command: ["sh", "-c", 'command -v pdftoppm >/dev/null && pdftoppm -png -r 40 -f 1 -l 1 -singlefile "$1" "$2" && echo "$2.png"', "sh", win.lookPath,
                  (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-quicklook"]
        stdout: StdioCollector { onStreamFinished: win.lookPdfImage = text.trim() }
    }
    onLookPathChanged: {
        lookPdfImage = "";
        if (lookPdf)
            pdfThumb.running = true;
    }

    function openSettings(cat) {
        Ui.controlCenter = true;
        Ui.expanded = "settings";
        Ui.settingsCat = cat;
    }

    // ---- what the shell itself can do, by name -----------------------------
    readonly property var actions: [
        { title: "Lock screen", words: "lock away", icon: "system-lock-screen", run: () => Lock.lock() },
        { title: "Do Not Disturb", words: "dnd quiet notifications silence", icon: "notifications-disabled", run: () => Notifs.setDnd(!Notifs.dnd), state: () => Notifs.dnd },
        { title: "Dark style", words: "dark light theme mode", icon: "weather-clear-night", run: () => Appearance.toggle(), state: () => Appearance.dark },
        { title: "Caffeine", words: "awake sleep idle stay", icon: "preferences-desktop-screensaver", run: () => Idle.setCaffeine(!Idle.caffeine), state: () => Idle.caffeine },
        { title: "Night light", words: "night warm blue light", icon: "night-light", run: () => NightLight.toggle(), state: () => NightLight.active },
        { title: "Wi-Fi", words: "wifi wireless network internet", icon: "network-wireless-signal-excellent", run: () => Net.setWifi(!Net.wifiEnabled), state: () => Net.wifiEnabled },
        { title: "Airplane mode", words: "airplane flight radio", icon: "airplane-mode", run: () => Net.setAirplane(!Net.airplane), state: () => Net.airplane },
        { title: "Screenshot", words: "screenshot capture print", icon: "applets-screenshooter", run: () => Niri.action("screenshot") },
        { title: "Screen record", words: "record video capture", icon: "media-record", run: () => Recorder.toggle(), state: () => Recorder.recording },
        { title: "Lens", words: "lens ocr read text scan qr", icon: "system-search", run: () => Lens.capture() },
        { title: "Color picker", words: "color colour pick hex", icon: "color-select", run: () => Quickshell.execDetached(["sh", "-c", "c=$(niri msg pick-color | sed -n 's/^Hex: //p'); [ -n \"$c\" ] && printf %s \"$c\" | wl-copy"]) },
        { title: "Screen keyboard", words: "keyboard osk touch", icon: "input-keyboard", run: () => Osk.toggle(), state: () => Osk.shown },
        { title: "Clipboard history", words: "clipboard paste history", icon: "edit-paste", run: () => Ui.toggleLauncher("c ") },
        { title: "Shell settings", words: "settings preferences control centre center", icon: "preferences-system", run: () => win.openSettings("") },
        // each settings category, by what people call what is in it
        { title: "Personalisation", words: "wallpaper background accent theme look blur dock bar tiles hot corners weather icons icon theme fonts font cursor pointer", icon: "preferences-desktop-wallpaper", run: () => win.openSettings("personal") },
        { title: "Notification settings", words: "notifications apps pop-ups popups quiet silent do not disturb per app", icon: "preferences-system-notifications", run: () => win.openSettings("notifications") },
        { title: "Accessibility settings", words: "accessibility screen reader orca large text contrast mono audio flash alerts captions read aloud speed", icon: "preferences-desktop-accessibility", run: () => win.openSettings("access") },
        { title: "Keyboard & input", words: "keyboard layout language input touchpad mouse tap scroll natural pointer speed repeat left-handed osk", icon: "input-keyboard", run: () => win.openSettings("input") },
        { title: "Date & language", words: "date time timezone time zone clock 24-hour ntp language locale region formats", icon: "preferences-system-time", run: () => win.openSettings("time") },
        { title: "Default apps", words: "default apps browser mail email files text pictures video music pdf open with terminal", icon: "preferences-desktop-default-applications", run: () => win.openSettings("apps") },
        { title: "Your account", words: "account user name password picture avatar photo face", icon: "system-users", run: () => win.openSettings("account") },
        { title: "Tour", words: "tour welcome help introduction tips what is new how", icon: "help-about", run: () => Ui.tour = true },
        { title: "Take a photo", words: "camera photo picture selfie snap webcam", icon: "camera-photo", run: () => Camera.photo() },
        { title: "Record a video", words: "camera video record webcam clip", icon: "camera-video", run: () => Camera.video(), state: () => Camera.phase === "recording" },
        { title: "Camera", words: "camera viewfinder webcam preview mirror qcam", icon: "camera-web", run: () => Camera.open() },
        { title: "Privacy", words: "privacy permissions camera microphone location recent files trash lock screen notifications previews", icon: "preferences-system-privacy", run: () => win.openSettings("privacy") },
        { title: "Network settings", words: "network proxy dns vpn wired ethernet ip", icon: "network-workgroup", run: () => win.openSettings("network") },
        { title: "Windows", words: "windows gaps focus ring column width animations focus follows mouse tiling", icon: "preferences-system-windows", run: () => win.openSettings("windows") },
        { title: "Keyboard shortcuts", words: "keyboard shortcuts keys hotkeys binds compose caps lock", icon: "preferences-desktop-keyboard-shortcuts", run: () => win.openSettings("input") },
        { title: "Startup apps", words: "startup apps autostart login start", icon: "system-run", run: () => win.openSettings("apps") },
        { title: "Displays", words: "displays display screens monitor monitors resolution refresh rate hz scale rotation rotate arrange arrangement external projector vrr freesync", icon: "video-display", run: () => win.openSettings("displays") },
        { title: "Sound effects", words: "sound effects equaliser equalizer eq bass boost crossfeed headphones autoeq impulse response convolver width jamesdsp viper", icon: "audio-speakers", run: () => win.openSettings("sound") },
        { title: "Users", words: "users add user new user account accounts remove user administrator admin automatic login autologin family", icon: "system-users", run: () => win.openSettings("users") },
        { title: "Power settings", words: "power battery saver idle lock suspend screen off sleep lid power button", icon: "preferences-system-power", run: () => win.openSettings("power") },
        { title: "About this computer", words: "about system computer name hostname rename version kernel memory disk cpu", icon: "help-about", run: () => win.openSettings("about") },
        { title: "Live captions", words: "captions subtitles live transcribe hearing", icon: "media-view-subtitles", run: () => Captions.toggle(), state: () => Captions.on && Captions.source === "speakers" },
        { title: "Live transcribe", words: "transcribe transcript meeting lecture microphone dictate", icon: "audio-input-microphone", run: () => Captions.transcribe(), state: () => Captions.on && Captions.source === "mic" },
        { title: "Read aloud", words: "read aloud speak tts selection voice", icon: "audio-speakers", run: () => Speak.speakSelection() },
        { title: "Magnifier", words: "magnifier zoom loupe enlarge", icon: "zoom-in", run: () => Ui.magnifier = true },
        { title: "Record a call", words: "call record recording meeting phone", icon: "call-start", run: () => CallRecorder.toggle(), state: () => CallRecorder.recording },
        { title: "Cast screen", words: "cast miracast tv display wireless project", icon: "video-display", run: () => Cast.open() },
        { title: "Clear clipboard history", words: "clipboard clear wipe history privacy", icon: "edit-clear-history", run: () => Clipboard.wipe() },
        { title: "Notifications", words: "notifications messages", icon: "preferences-system-notifications", run: () => Ui.toggleControlCenter("notifications") },
        { title: "Switch windows", words: "windows switch alt tab", icon: "focus-windows", run: () => Ui.switcherRequested(false) },
        { title: "Suspend", words: "suspend sleep", icon: "weather-clear-night", run: () => Power.suspend() },
        { title: "Log out", words: "logout log out sign out", icon: "system-log-out", run: () => Power.logout() },
        // irreversible: these open the sidebar's confirm row instead of acting
        { title: "Restart…", words: "reboot restart", icon: "system-reboot", run: () => Ui.toggleControlCenter("power") },
        { title: "Power off…", words: "shutdown power off", icon: "system-shutdown", run: () => Ui.toggleControlCenter("power") }
    ]

    // ---- sources --------------------------------------------------------------
    function launch(a) {
        const u = Object.assign({}, usage);
        u[a.id] = (u[a.id] || 0) + 1;
        usage = u;
        usageFile.setText(JSON.stringify(u));
        a.execute();
    }
    FileView {
        id: usageFile
        path: Quickshell.statePath("app-usage.json")
        printErrors: false
        onLoaded: { try { win.usage = JSON.parse(text()); } catch (e) {} }
    }
    // the path is set on the first ":" — a FileView loads when given a path;
    // a reload() of one that never had its path set loads nothing (measured)
    FileView {
        path: win.emojiPath
        printErrors: false
        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                const m = line.match(/; fully-qualified\s+# (\S+) E[\d.]+ (.+)$/);
                if (m)
                    out.push({ e: m[1], name: m[2] });
            }
            win.emoji = out;
        }
    }
    // recently used files: the desktop's shared list (GTK and most apps write it)
    FileView {
        path: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/recently-used.xbel"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const out = [];
            const re = /<bookmark href="file:\/\/([^"]+)"[^>]*modified="([^"]+)"/g;
            let m;
            while ((m = re.exec(text())) !== null) {
                const path = decodeURIComponent(m[1]);
                out.push({ path: path, name: path.split("/").pop(), when: m[2] });
            }
            win.recent = out.sort((a, b) => a.when < b.when ? 1 : -1).slice(0, 40);
        }
    }
    // files by name in the home folder: fd when installed, find otherwise
    Process {
        id: fileSearch
        property string query
        // in the folders chosen in Settings > Search (the home folder by default)
        command: ["sh", "-c", 'q="$1"; shift; if command -v fd >/dev/null; then fd -i -d 5 --max-results 15 -- "$q" "$@"; else find "$@" -maxdepth 5 -not -path "*/.*" -iname "*$q*" 2>/dev/null | head -15; fi', "sh", query]
            .concat(Array.from(Settings.data.searchFolders).map(f => f.replace(/^~/, Quickshell.env("HOME"))))
        stdout: StdioCollector { onStreamFinished: win.found = text.trim().split("\n").filter(x => x) }
    }
    // inside files: the desktop's index (localsearch) when it runs; otherwise a
    // bounded ripgrep / grep over the folders people keep documents in
    Process {
        id: contentSearch
        property string query
        command: ["sh", "-c", 'q="$1"; d="$HOME/Documents $HOME/Desktop $HOME/Downloads"; if command -v localsearch >/dev/null && localsearch status >/dev/null 2>&1; then localsearch search --limit 8 -- "$q" 2>/dev/null | sed -n "s|.*file://\\([^ ]*\\).*|\\1|p" | head -8 ; elif command -v rg >/dev/null; then rg -l -i -F --max-depth 4 --max-filesize 2M -- "$q" $d 2>/dev/null | head -8 ; else grep -rliF --exclude-dir=".*" -- "$q" $d 2>/dev/null | head -8 ; fi',"sh", query]
        stdout: StdioCollector { onStreamFinished: win.inside = text.trim().split("\n").filter(x => x).map(p => decodeURIComponent(p)) }
    }
    Timer {
        id: fileDebounce
        interval: 250
        onTriggered: {
            const t = win.q.trim();
            if (t.length >= 3 && !/^[=:c>?]/.test(t)) {
                // only what Settings > Search allows is looked at
                win.found = [];
                win.inside = [];
                win.provided = [];
                if (Settings.data.searchFiles) {
                    fileSearch.query = t;
                    fileSearch.running = true;
                }
                if (Settings.data.searchInside) {
                    contentSearch.query = t;
                    contentSearch.running = true;
                }
                if (Settings.data.searchProviders) {
                    providerSearch.terms = t.split(/\s+/);
                    providerSearch.running = true;
                }
            } else {
                win.found = [];
                win.inside = [];
                win.provided = [];
            }
        }
    }

    function calc(expr) {
        const src = expr.replace(/\s+/g, "").replace(/\^/g, "**").replace(/×/g, "*").replace(/÷/g, "/");
        if (!/^[0-9+\-*/%.()a-z,]+$/i.test(src) || !/[0-9]/.test(src) || /^[0-9.]+$/.test(src))
            return null;
        const names = src.match(/[a-z]+/gi) || [];
        const allowed = ["sqrt", "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln", "exp", "abs", "round", "floor", "ceil", "pow", "min", "max", "pi", "e"];
        if (names.some(n => allowed.indexOf(n.toLowerCase()) < 0))
            return null;
        const js = src.replace(/\bln\(/gi, "log(").replace(/\bpi\b/gi, "PI").replace(/\be\b/g, "E")
            .replace(/\b(sqrt|sin|cos|tan|asin|acos|atan|log|exp|abs|round|floor|ceil|pow|min|max|PI|E)\b/g, "Math.$1");
        try {
            const v = Function('"use strict"; return (' + js + ");")();
            return typeof v === "number" && isFinite(v) ? Number(v.toPrecision(12)) : null;
        } catch (e) {
            return null;
        }
    }
    // units: name -> [dimension, factor to the base unit]; temperatures are special
    readonly property var units: ({
        mm: ["len", 0.001], cm: ["len", 0.01], m: ["len", 1], km: ["len", 1000], in: ["len", 0.0254], inch: ["len", 0.0254],
        ft: ["len", 0.3048], feet: ["len", 0.3048], foot: ["len", 0.3048], yd: ["len", 0.9144], mi: ["len", 1609.344], mile: ["len", 1609.344], miles: ["len", 1609.344],
        mg: ["mass", 1e-6], g: ["mass", 0.001], kg: ["mass", 1], t: ["mass", 1000], oz: ["mass", 0.0283495], lb: ["mass", 0.453592], lbs: ["mass", 0.453592],
        ml: ["vol", 0.001], l: ["vol", 1], litre: ["vol", 1], liter: ["vol", 1], gal: ["vol", 3.78541], cup: ["vol", 0.24], tsp: ["vol", 0.00492892], tbsp: ["vol", 0.0147868],
        b: ["data", 1], kb: ["data", 1e3], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12], kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824], tib: ["data", 1099511627776],
        ms: ["time", 0.001], s: ["time", 1], sec: ["time", 1], min: ["time", 60], h: ["time", 3600], hr: ["time", 3600], day: ["time", 86400], days: ["time", 86400], week: ["time", 604800], weeks: ["time", 604800],
        kmh: ["speed", 1 / 3.6], "km/h": ["speed", 1 / 3.6], mph: ["speed", 0.44704], "m/s": ["speed", 1], knot: ["speed", 0.514444], knots: ["speed", 0.514444],
        m2: ["area", 1], km2: ["area", 1e6], ha: ["area", 1e4], acre: ["area", 4046.86], acres: ["area", 4046.86], sqft: ["area", 0.092903],
        c: ["temp"], f: ["temp"], k: ["temp"]
    })
    function convert(q) {
        const m = q.trim().toLowerCase().match(/^(-?[\d.]+)\s*([a-z\/0-9°]+)\s+(?:in|to|as)\s+([a-z\/0-9°]+)$/);
        if (!m)
            return null;
        const v = parseFloat(m[1]), a = m[2].replace("°", ""), b = m[3].replace("°", "");
        const ua = units[a], ub = units[b];
        if (!ua || !ub || ua[0] !== ub[0] || isNaN(v))
            return null;
        let out;
        if (ua[0] === "temp") {
            const kel = a === "c" ? v + 273.15 : a === "f" ? (v - 32) * 5 / 9 + 273.15 : v;
            out = b === "c" ? kel - 273.15 : b === "f" ? (kel - 273.15) * 9 / 5 + 32 : kel;
        } else {
            out = v * ua[1] / ub[1];
        }
        return { text: Number(out.toPrecision(8)) + " " + m[3], value: out };
    }
    // three-letter codes followed by "in/to": currency, which needs live rates —
    // Chronoa's convert_currency skill has them; the shell sends no query anywhere
    function isCurrency(q) {
        return /^-?[\d.]+\s*[a-z]{3}\s+(in|to)\s+[a-z]{3}$/i.test(q.trim()) && convert(q) === null;
    }

    function score(text, q) {
        const n = (text || "").toLowerCase();
        if (n.startsWith(q))
            return 100 - n.length / 100;
        if (n.split(/[\s\-_.]/).some(w => w.startsWith(q)))
            return 80;
        return n.indexOf(q) >= 0 ? 60 : 0;
    }
    // every word typed starts some word of the text, in any order:
    // "default browser", "time zone", "add user"
    function allWords(text, q) {
        const words = text.toLowerCase().split(/[\s\-_&]+/).filter(w => w);
        return q.split(/\s+/).filter(t => t).every(t => words.some(w => w.startsWith(t)));
    }
    function appScore(a, q) {
        const s = score(a.name, q);
        if (s > 0)
            return s;
        const g = ((a.genericName || "") + " " + [].concat(a.keywords || []).join(" ") + " " + [].concat(a.categories || []).join(" ")).toLowerCase();
        if (g.indexOf(q) >= 0)
            return 40;
        return (a.comment || "").toLowerCase().indexOf(q) >= 0 ? 20 : 0;
    }
    function fileIcon(path) {
        const ext = (path.split(".").pop() || "").toLowerCase();
        if (["png", "jpg", "jpeg", "webp", "gif", "svg"].indexOf(ext) >= 0) return "image-x-generic";
        if (["mp4", "mkv", "webm", "mov"].indexOf(ext) >= 0) return "video-x-generic";
        if (["mp3", "flac", "ogg", "opus", "wav"].indexOf(ext) >= 0) return "audio-x-generic";
        if (["pdf"].indexOf(ext) >= 0) return "x-office-document";
        return path.indexOf(".") < 0 ? "folder" : "text-x-generic";
    }

    readonly property var apps: DesktopEntries.applications.values.filter(a => !a.noDisplay)
    readonly property var categories: ["All", "Internet", "Office", "Graphics", "AudioVideo", "Development", "Utility", "System", "Game"]
    readonly property var categoryNames: ({ AudioVideo: "Media" })

    // ---- the answer, as sections; `flat` is what the keyboard walks ----------
    readonly property var sections: {
        const q = win.q.trim();
        const ql = q.toLowerCase();
        const out = [];
        const used = a => win.usage[a.id] || 0;
        const appItem = a => ({ kind: "app", app: a.icon, title: a.name, subtitle: a.genericName || a.comment || "", run: () => win.launch(a) });
        const fileItem = p => ({ kind: "file", icon: win.fileIcon(p), path: p, title: p.split("/").pop(), subtitle: p.replace(Quickshell.env("HOME"), "~"), run: () => Qt.openUrlExternally("file://" + p) });

        if (q === "") {
            const frequent = win.apps.filter(a => used(a) > 0).sort((a, b) => used(b) - used(a)).slice(0, 8);
            if (frequent.length)
                out.push({ title: "Frequent", grid: true, items: frequent.map(appItem) });
            if (win.recent.length)
                out.push({ title: "Recent files", items: win.recent.slice(0, 6).map(r => fileItem(r.path)) });
            const all = win.apps.filter(a => win.category === "All" || [].concat(a.categories || []).indexOf(win.category) >= 0)
                .sort((a, b) => a.name.localeCompare(b.name));
            out.push({ title: "All apps", grid: true, chips: true, items: all.map(appItem) });
            return out;
        }
        if (q.startsWith("?")) {
            const t = q.slice(1).trim();
            return [{ title: "Chronoa", items: [{ kind: "ask", icon: "chat-message-new", title: t ? "Ask Chronoa: " + t : "Ask Chronoa…", subtitle: "Enter", run: () => t && Chronoa.ask(t) }] }];
        }
        if (q.startsWith(">")) {
            const cmd = q.slice(1).trim();
            return [{ title: "Run", items: [{ kind: "run", icon: "utilities-terminal", title: cmd ? "Run: " + cmd : "Run a command…", subtitle: "Shift+Enter: in " + Settings.data.terminal,
                     run: shift => cmd && Quickshell.execDetached(shift ? [Settings.data.terminal, "-e", "sh", "-c", cmd + "; exec $SHELL"] : ["sh", "-c", cmd]) }] }];
        }
        if (q.startsWith(":")) {
            const f = q.slice(1).trim().toLowerCase();
            if (win.emojiPath === "")
                Qt.callLater(() => win.emojiPath = "/usr/share/unicode/emoji/emoji-test.txt");
            return [{ title: "Emoji", items: win.emoji.filter(x => f === "" || x.name.indexOf(f) >= 0).slice(0, 40)
                .map(x => ({ kind: "emoji", icon: "face-smile-big", title: x.e + "  " + x.name, subtitle: "Enter copies", run: () => Quickshell.clipboardText = x.e })) }];
        }
        if (q === "c" || q.startsWith("c ")) {
            const f = q.slice(1).trim().toLowerCase();
            const items = Clipboard.entries.filter(e => f === "" || e.text.toLowerCase().indexOf(f) >= 0).slice(0, 30)
                .map(e => ({ kind: "clip", icon: e.image ? "image-x-generic" : "edit-paste", thumb: e.image ? e.preview : "",
                             title: e.text.replace(/\s+/g, " ").slice(0, 140), subtitle: (e.image ? "Picture · Enter copies it" : "Clipboard") + " · Shift+Delete removes it",
                             run: () => Clipboard.copy(e), remove: () => Clipboard.remove(e) }));
            return [{ title: "Clipboard", items: items.length ? items : [{ kind: "none", icon: "edit-paste", title: Clipboard.available ? "Clipboard history is empty" : "cliphist is not installed", subtitle: "", run: () => {} }] }];
        }

        const math = q.startsWith("=") ? q.slice(1) : q;
        const v = math !== "" ? win.calc(math) : null;
        if (v !== null && Settings.data.searchCalc)
            out.push({ title: "Calculator", items: [{ kind: "calc", icon: "accessories-calculator", title: "= " + v, subtitle: "Enter copies the result", run: () => Quickshell.clipboardText = String(v) }] });
        const conv = Settings.data.searchCalc ? win.convert(q) : null;
        if (conv)
            out.push({ title: "Convert", items: [{ kind: "calc", icon: "accessories-calculator", title: "= " + conv.text, subtitle: "Enter copies", run: () => Quickshell.clipboardText = String(Number(conv.value.toPrecision(8))) }] });
        if (Settings.data.searchCalc && win.isCurrency(q))
            out.push({ title: "Currency", items: [{ kind: "ask", icon: "chat-message-new", title: "Convert " + q + " with Chronoa", subtitle: "live rates", run: () => Chronoa.ask("Convert " + q) }] });
        if (q.startsWith("="))
            return out;

        const ranked = win.apps.map(a => ({ a: a, s: win.appScore(a, ql) })).filter(x => x.s > 0)
            .map(x => ({ a: x.a, s: x.s + Math.min(15, used(x.a)) })).sort((x, y) => y.s - x.s).map(x => x.a);
        if (ranked.length) {
            const items = [];
            ranked.slice(0, 12).forEach((a, i) => {
                items.push(appItem(a));
                if (i === 0)        // the top match also offers its desktop actions
                    for (const act of a.actions)
                        items.push({ kind: "app", app: a.icon, title: a.name + " — " + act.name, subtitle: "action", run: () => act.execute() });
            });
            out.push({ title: "Apps", items: items });
        }
        const wins = Object.values(Niri.windows).filter(w => win.score(w.title, ql) > 0 || win.score(w.app_id, ql) > 0).slice(0, 6);
        if (wins.length)
            out.push({ title: "Windows", items: wins.map(w => {
                const e = DesktopEntries.heuristicLookup(w.app_id || "");
                return { kind: "window", app: e ? e.icon : w.app_id, title: w.title || w.app_id, subtitle: Niri.workspaceLabel(w.workspace_id), run: () => Niri.action("focus-window", "--id", w.id) };
            }) });
        const acts = win.actions.filter(a => win.score(a.title, ql) > 0 || win.allWords(a.title + " " + a.words, ql)).slice(0, 6);
        if (acts.length)
            out.push({ title: "Actions", items: acts.map(a => ({ kind: "action", icon: a.icon, title: a.title,
                subtitle: a.state ? (a.state() ? "On — Enter turns off" : "Off — Enter turns on") : "", run: a.run })) });
        const files = win.recent.filter(r => r.name.toLowerCase().indexOf(ql) >= 0).map(r => r.path);
        const allFiles = files.concat(win.found.filter(p => files.indexOf(p) < 0)).slice(0, 10);
        const byContent = win.inside.filter(p => allFiles.indexOf(p) < 0).slice(0, 6);
        if (allFiles.length || byContent.length)
            out.push({ title: "Files", items: allFiles.map(fileItem).concat(byContent.map(p => Object.assign(fileItem(p), { subtitle: "contains “" + q + "” · " + p.replace(Quickshell.env("HOME"), "~") }))) });
        // what the apps themselves found, one section per app
        for (const app of [...new Set(win.provided.map(r => r.app))].slice(0, 4))
            out.push({ title: "From " + app, items: win.provided.filter(r => r.app === app).slice(0, 4).map(r => ({
                kind: "provided", app: r.icon, title: r.name, subtitle: r.description,
                run: () => Quickshell.execDetached(["python3", win.providersTool, "activate", r.bus, r.path, r.id].concat(q.split(/\s+/))) })) });
        out.push({ title: "More", items: [
            { kind: "ask", icon: "chat-message-new", title: "Ask Chronoa: " + q, subtitle: "Ctrl+Enter from anywhere", run: () => Chronoa.ask(q) },
            { kind: "web", icon: "web-browser", title: "Search the web for “" + q + "”", subtitle: Ui.webSearchName(), run: () => Qt.openUrlExternally(Ui.webSearchUrl(q)) }
        ] });
        return out;
    }
    readonly property var flat: sections.reduce((acc, s) => acc.concat(s.items), [])
    readonly property var current: flat[Math.max(0, Math.min(sel, flat.length - 1))] || null
    onFlatChanged: Ui.topResult = flat.length > 0 ? flat[0].title : ""
    onSectionsChanged: Ui.launcherSections = sections.map(x => x.title)
    onQChanged: {
        sel = 0;
        fileDebounce.restart();
        if (q === "c" || q.startsWith("c "))
            Clipboard.refresh();
    }

    function activate(i, shift) {
        const r = flat[Math.max(0, Math.min(i, flat.length - 1))];
        if (!r)
            return;
        Ui.closeAll();
        r.run(shift);
    }
    function askChronoa() {
        const t = q.trim().replace(/^\?/, "").trim();
        const c = current;
        Ui.closeAll();
        if (c && c.kind === "file")
            Chronoa.ask((t ? t + "\n" : "What is this file, and what can I do with it?\n") + "The file: " + c.path);
        else if (t)
            Chronoa.ask(t);
        else
            Ui.askIsland();
    }

    onVisibleChanged: {
        if (visible) {
            appear.restart();
            search.text = Ui.launcherQuery;
            sel = 0;
            category = "All";
            search.forceActiveFocus();
        }
    }

    // ---- drawing ----------------------------------------------------------------
    Rectangle {
        id: backdrop
        anchors.fill: parent
        // dense enough to read without blur (blur off, or a compositor without it)
        color: Theme.alpha(Theme.bg, Settings.data.blur ? 0.78 : 0.94)
        MouseArea { anchors.fill: parent; onClicked: Ui.closeAll() }
    }

    // opens with a short fade and rise (instant with reduce motion)
    ParallelAnimation {
        id: appear
        NumberAnimation { target: body; property: "opacity"; from: 0; to: 1; duration: Theme.anim * 1.5; easing.type: Easing.OutCubic }
        NumberAnimation { target: rise; property: "y"; from: 18; to: 0; duration: Theme.anim * 1.5; easing.type: Easing.OutCubic }
    }

    ColumnLayout {
        id: body
        transform: Translate { id: rise }
        anchors.fill: parent
        anchors.topMargin: Math.max(60, parent.height * 0.08)
        anchors.bottomMargin: 40
        anchors.leftMargin: Math.max(40, (parent.width - 1280) / 2)
        anchors.rightMargin: Math.max(40, (parent.width - 1280) / 2)
        spacing: 18

        // the field
        Glass {
            Layout.fillWidth: true
            Layout.preferredWidth: 760
            Layout.maximumWidth: 760
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: 58
            strong: true
            radius: 29
            MouseArea { anchors.fill: parent }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                spacing: 12
                Icon { name: "system-search"; size: 22; color: Theme.accent }
                TextInput {
                    id: search
                    Layout.fillWidth: true
                    color: Theme.text
                    selectionColor: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 20 * Theme.fontScale
                    clip: true
                    Keys.onEscapePressed: Ui.closeAll()
                    Keys.onDownPressed: win.sel = Math.min(win.sel + (win.q === "" ? 6 : 1), win.flat.length - 1)
                    Keys.onUpPressed: win.sel = Math.max(win.sel - (win.q === "" ? 6 : 1), 0)
                    Keys.onTabPressed: win.sel = (win.sel + 1) % Math.max(1, win.flat.length)
                    Keys.onBacktabPressed: win.sel = (win.sel - 1 + win.flat.length) % Math.max(1, win.flat.length)
                    Keys.onPressed: e => {
                        // Shift+Delete: a result that can be removed (a clipboard entry) goes
                        if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier) && win.flat[win.sel] && win.flat[win.sel].remove) {
                            win.flat[win.sel].remove();
                            e.accepted = true;
                            return;
                        }
                        if (win.q === "" && (e.key === Qt.Key_Right || e.key === Qt.Key_Left)) {
                            win.sel = Math.max(0, Math.min(win.flat.length - 1, win.sel + (e.key === Qt.Key_Right ? 1 : -1)));
                            e.accepted = true;
                        }
                    }
                    Keys.onReturnPressed: e => (e.modifiers & Qt.ControlModifier) ? win.askChronoa() : win.activate(win.sel, e.modifiers & Qt.ShiftModifier)
                    Keys.onEnterPressed: e => (e.modifiers & Qt.ControlModifier) ? win.askChronoa() : win.activate(win.sel, e.modifiers & Qt.ShiftModifier)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text === ""
                        text: "Search apps, files, windows and actions — or ask Chronoa"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 17 * Theme.fontScale
                    }
                }
                Text {
                    text: "Ctrl+Enter  Chronoa"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 18

            // results
            Flickable {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: resultCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: resultCol
                    width: list.width
                    spacing: 14

                    Repeater {
                        model: win.sections
                        ColumnLayout {
                            id: section
                            required property var modelData
                            required property int index
                            // where this section's items start in `flat`
                            readonly property int base: win.sections.slice(0, index).reduce((n, s) => n + s.items.length, 0)
                            Layout.fillWidth: true
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: section.modelData.title
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 12 * Theme.fontScale
                                    font.weight: Font.DemiBold
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 1
                                }
                                Item { Layout.fillWidth: true }
                                Repeater {
                                    model: section.modelData.chips ? win.categories : []
                                    Choice {
                                        required property string modelData
                                        text: win.categoryNames[modelData] || modelData
                                        selected: win.category === modelData
                                        onClicked: { win.category = modelData; search.forceActiveFocus(); }
                                    }
                                }
                            }

                            // apps as a grid
                            GridLayout {
                                visible: !!section.modelData.grid
                                Layout.fillWidth: true
                                columns: Math.max(4, Math.floor(list.width / 132))
                                columnSpacing: 8
                                rowSpacing: 8
                                Repeater {
                                    model: section.modelData.grid ? section.modelData.items : []
                                    Rectangle {
                                        id: tile
                                        required property var modelData
                                        required property int index
                                        readonly property bool isSel: win.sel === section.base + index
                                        Layout.fillWidth: true
                                        implicitHeight: 112
                                        radius: 18
                                        color: isSel ? Theme.accentSoft : (tileArea.containsMouse ? Theme.hover : "transparent")
                                        border.width: isSel ? 1 : 0
                                        border.color: Theme.accentLine
                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            width: parent.width - 16
                                            spacing: 8
                                            IconImage {
                                                Layout.alignment: Qt.AlignHCenter
                                                implicitSize: 54
                                                source: Quickshell.iconPath(tile.modelData.app, "application-x-executable")
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: tile.modelData.title
                                                color: Theme.text
                                                elide: Text.ElideRight
                                                font.family: Theme.font
                                                font.pixelSize: 12 * Theme.fontScale
                                            }
                                        }
                                        MouseArea {
                                            id: tileArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onEntered: win.sel = section.base + tile.index
                                            onClicked: win.activate(section.base + tile.index, false)
                                        }
                                    }
                                }
                            }

                            // everything else as rows
                            Repeater {
                                model: section.modelData.grid ? [] : section.modelData.items
                                Rectangle {
                                    id: row
                                    required property var modelData
                                    required property int index
                                    readonly property bool isSel: win.sel === section.base + index
                                    Layout.fillWidth: true
                                    implicitHeight: 48
                                    radius: 14
                                    color: isSel ? Theme.accentSoft : (rowArea.containsMouse ? Theme.hover : "transparent")
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 12
                                        IconImage {
                                            visible: !!row.modelData.app
                                            implicitSize: 28
                                            source: row.modelData.app ? Quickshell.iconPath(row.modelData.app, "application-x-executable") : ""
                                        }
                                        ClippingRectangle {
                                            visible: !!row.modelData.thumb
                                            implicitWidth: 56
                                            implicitHeight: 36
                                            radius: 6
                                            color: Theme.hover
                                            Image {
                                                anchors.fill: parent
                                                source: row.modelData.thumb ? "file://" + row.modelData.thumb : ""
                                                sourceSize: Qt.size(112, 72)
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                cache: false
                                            }
                                        }
                                        Icon {
                                            visible: !row.modelData.app && !row.modelData.thumb
                                            name: row.modelData.icon || ""
                                            size: 20
                                            color: row.modelData.kind === "ask" ? Theme.accent : Theme.text
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: row.modelData.title
                                            color: Theme.text
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: 14 * Theme.fontScale
                                        }
                                        Text {
                                            Layout.maximumWidth: list.width * 0.4
                                            text: row.modelData.subtitle
                                            color: Theme.dim
                                            elide: Text.ElideMiddle
                                            font.family: Theme.font
                                            font.pixelSize: 11 * Theme.fontScale
                                        }
                                    }
                                    MouseArea {
                                        id: rowArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onEntered: win.sel = section.base + row.index
                                        onClicked: win.activate(section.base + row.index, false)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Chronoa, one keystroke away, with a preview of what is selected
            Glass {
                visible: win.q !== "" || (win.current && win.current.kind === "file")
                Layout.preferredWidth: 340
                Layout.fillHeight: true
                strong: true
                radius: Theme.radiusLarge
                MouseArea { anchors.fill: parent }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12
                    RowLayout {
                        Icon { name: "face-smile-big"; size: 20; color: Chronoa.color }
                        Text {
                            text: "Chronoa"
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 15 * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text { text: "· " + Chronoa.label; color: Chronoa.color; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 220
                        visible: win.lookText && lookFile.loaded
                        radius: 12
                        color: Theme.hover
                        clip: true
                        Text {
                            anchors.fill: parent
                            anchors.margins: 10
                            text: lookFile.loaded ? lookFile.text().split("\n").slice(0, 16).join("\n").slice(0, 1500) : ""
                            textFormat: Text.PlainText
                            color: Theme.dim
                            font.family: Theme.mono
                            font.pixelSize: 10 * Theme.fontScale
                            wrapMode: Text.NoWrap
                        }
                    }
                    ClippingRectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 240
                        visible: win.lookPdfImage !== ""
                        radius: 12
                        color: Theme.hover
                        Image {
                            anchors.fill: parent
                            source: win.lookPdfImage ? "file://" + win.lookPdfImage : ""
                            cache: false
                            fillMode: Image.PreserveAspectFit
                        }
                    }
                    ClippingRectangle {
                        id: imagePreview
                        Layout.fillWidth: true
                        Layout.preferredHeight: 180
                        visible: win.current && win.current.kind === "file" && win.current.icon === "image-x-generic"
                        radius: 12
                        color: Theme.hover
                        Image {
                            anchors.fill: parent
                            source: imagePreview.visible ? "file://" + win.current.path : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize: Qt.size(640, 360)
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        // the query is only shown when it says more than the file's own name
                        text: win.current && win.current.kind === "file"
                            ? "Ask about " + win.current.title + (win.q.trim() && win.current.title.toLowerCase().indexOf(win.q.trim().toLowerCase()) < 0 ? ": “" + win.q.trim() + "”" : "")
                            : "“" + win.q.trim() + "”"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 14 * Theme.fontScale
                    }
                    Button {
                        text: "Ask Chronoa  (Ctrl+Enter)"
                        kind: "primary"
                        onClicked: win.askChronoa()
                    }
                    Item { Layout.fillHeight: true }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "=  calc    :  emoji    c  clipboard\n>  run     ?  ask"
                        color: Theme.faint
                        font.family: Theme.mono
                        font.pixelSize: 10 * Theme.fontScale
                    }
                }
            }
        }
    }
}
