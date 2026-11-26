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
//   app:firefox   file:report   web:weather   clip:meeting   action:dark
// Operators (parsed in Services/LauncherEntries.qml) narrow the answer to one
// family; Home/End jump to the first/last result; results carry AT names.
// Apps you launch often rank first (counts in Quickshell's state dir).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import "../../Common/Calc.js" as Calc
import "Fuzzy.js" as Fuzzy
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/Gestures.js" as G
import "../../Common/Time.js" as Time

PanelWindow {
    id: win
    // Hide the preview when there is no room, including narrow desktop outputs.
    readonly property bool narrow: FormFactor.of(screen.name).profile === "phone" || width < Theme.px(900)
    visible: Ui.launcher
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (Ui.launcher) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Ui.launcher && Settings.blurWanted ? fullRegion : null
    Region { id: fullRegion; item: backdrop }

    property int sel: 0
    // a remote went Up past the top row: the search bar is selected, and OK
    // there brings the screen keyboard (typing, or a new query, leaves it)
    property bool searchBar: false
    // the suite reads this: how far the results stay above the screen's bottom
    readonly property real bottomGap: body.keyboardGap
    onSearchBarChanged: Ui.launcherSearchBar = searchBar
    // hover only steers the selection once the pointer really moves: on open,
    // a resting cursor would otherwise steal it from the top result, so Enter
    // launched whatever happened to be under the pointer
    property bool hoverArmed: false
    // the app grids' column count, the same expression the grid itself uses,
    // so Up/Down move by one real row whatever the window width is
    // a phone's app drawer: four icons across, as a phone has them
    readonly property bool phone: FormFactor.of(win.screen ? win.screen.name : "").profile === "phone"
    readonly property int gridCols: phone ? 4 : Math.max(1, Math.floor(list.width / Theme.px(132)))
    readonly property real phoneCell: Math.floor((list.width - Theme.px(8) * 3) / 4)
    // a page of results for PageUp/PageDown (six grid rows when there is a grid)
    readonly property int pageRows: Math.max(1, Math.min(8, win.gridCols) * 6)
    property string category: "All"
    readonly property string q: search.text
    // the query after an operator's prefix (LauncherEntries.parseQuery), used by
    // every async search so an "app:…" query never searches files for "app:…"
    property string searchText: ""
    property var usage: ({})              // desktop id -> launches
    property var emoji: []                // [{ e, name }], loaded on first ":"
    property string emojiPath: ""
    readonly property var recent: RecentFiles.files   // [{ path, name, when, app }], newest first
    property var found: []                // file search hits for the current query
    property var inside: []               // files whose contents match
    property var provided: []             // apps' own search results (GNOME SearchProvider2)
    readonly property string providersTool: Quickshell.env("SHANI_SEARCH_PROVIDERS_TOOL") || "/usr/lib/shani-shell/search-providers.py"
    Process {
        id: providerSearch
        property var terms: []
        command: ["python3", win.providersTool, "query"].concat(terms)
        stdout: StdioCollector {
            onStreamFinished: {
                // a late answer from the previous query must not replace this one's
                // the plain-query comparison is kept too: it is the common case
                if (providerSearch.terms.join(" ") !== win.searchText.split(/\s+/).filter(x => x).join(" ")
                    && providerSearch.terms.join(" ") !== win.q.trim().split(/\s+/).join(" "))
                    return;
                try { win.provided = JSON.parse(text); } catch (e) { win.provided = []; }
            }
        }
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

    function openSettings(cat) { Ui.openSettings(cat); }

    // ---- what the shell itself can do, by name -----------------------------
    LauncherActions { id: builtIn; launcher: win }
    // an action that is also one of the shell's apps (bin/shani's APPS) is listed
    // once: as the app where its desktop entry is installed, as the action where not
    readonly property var actions: builtIn.list.filter(a => !a.app || !DesktopEntries.byId(a.app))
    // the words typos are forgiven against (Fuzzy.js), made once per list, not per key
    readonly property var actionWords: actions.map(a => Fuzzy.words(a.title))

    // ---- sources --------------------------------------------------------------
    // an app started through one of its actions ("New Window") is still that app used
    function launch(a, action) {
        const u = Object.assign({}, usage);
        u[a.id] = (u[a.id] || 0) + 1;
        usage = u;
        usageFile.setText(JSON.stringify(u));
        Launch.app(a.id, action ? { action: action } : undefined);
    }
    // "> cmd" can also be run through pkexec: the shell's polkit agent asks.
    // The command is one argv element to sh, never pasted into a shell string.
    function runAdmin(cmd) { Quickshell.execDetached(["pkexec", "sh", "-c", cmd]); }
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
    // files by name in the home folder: fd when installed, find otherwise
    Process {
        id: fileSearch
        property string query
        // in the folders chosen in Settings > Search (the home folder by default)
        // plocate's index first (instant; updated daily by plocate-updatedb), kept to
        // those folders and away from hidden ones; walking them with fd/find otherwise
        command: ["sh", "-c", 'q="$1"; shift
            if command -v plocate >/dev/null && [ -s /var/lib/plocate/plocate.db ]; then
                for d in "$@"; do plocate -i -b -l 400 -- "$q" 2>/dev/null | grep -F "$d/" | grep -v "/\\." ; done | awk "!s[\\$0]++" | head -15
            elif command -v fd >/dev/null; then fd -i -d 5 --max-results 15 -- "$q" "$@"
            else find "$@" -maxdepth 5 -not -path "*/.*" -iname "*$q*" 2>/dev/null | head -15; fi', "sh", query]
            .concat(Array.from(Settings.data.searchFolders).map(f => f.replace(/^~/, Quickshell.env("HOME"))))
        stdout: StdioCollector {
            onStreamFinished: {
                if (fileSearch.query === win.searchText || fileSearch.query === win.q.trim())     // not a stale query's answer
                    win.found = text.trim().split("\n").filter(x => x);
            }
        }
    }
    // inside files: the desktop's index (localsearch) when it runs; otherwise a
    // bounded ripgrep / grep over the folders people keep documents in
    Process {
        id: contentSearch
        property string query
        command: ["sh", "-c", 'q="$1"; shift; if command -v localsearch >/dev/null && localsearch status >/dev/null 2>&1; then localsearch search --limit 8 -- "$q" 2>/dev/null | sed -n "s|.*file://\\([^ ]*\\).*|\\1|p" | head -8 ; elif command -v rg >/dev/null; then rg -l -i -F --max-depth 4 --max-filesize 2M -- "$q" "$@" 2>/dev/null | head -8 ; else grep -rliF --exclude-dir=".*" -- "$q" "$@" 2>/dev/null | head -8 ; fi',"sh", query]
            .concat(Array.from(Settings.data.searchFolders).map(f => f.replace(/^~/, Quickshell.env("HOME"))))
        stdout: StdioCollector {
            onStreamFinished: {
                if (contentSearch.query === win.searchText || contentSearch.query === win.q.trim())  // not a stale query's answer
                    win.inside = text.trim().split("\n").filter(x => x).map(p => decodeURIComponent(p));
            }
        }
    }
    // files by meaning (Chronoa's FindFiles): [{ path, excerpt }], and how it searched
    property var meaning: []
    property string meaningHow: ""
    property int meaningSeq: 0
    Connections {
        target: Bridge
        function onMessage(msg) {
            if (msg.type !== "found" || msg.id !== "f" + win.meaningSeq)
                return;                             // an older query's answer
            win.meaning = (msg.hits || []).map(h => ({ path: h.path, excerpt: h.excerpt || "" }));
            win.meaningHow = msg.how || "";
            Ui.launcherMeaning = win.meaning.length;
        }
    }
    Timer {
        id: fileDebounce
        interval: 250
        onTriggered: {
            const p = LauncherEntries.parseQuery(win.q.trim());
            const t = p.text;
            // app:/web:/clip:/action: keep their own lane; file: still walks files
            const scope = !p.active || p.op === "file";
            if (t.length >= 3 && scope && !/^[=:c>?]/.test(t)) {
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
                // by meaning: Chronoa's own index of Documents, Downloads, Desktop
                if (Settings.data.searchMeaning !== false && t.length >= 4) {
                    win.meaningSeq++;
                    Bridge.send({ op: "findfiles", id: "f" + win.meaningSeq, query: t });
                }
            } else {
                win.found = [];
                win.inside = [];
                win.provided = [];
                win.meaning = [];
            }
        }
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
        // initials: "mp" finds Media Player, "sm" finds System Monitor
        if (Fuzzy.initials(a.name).startsWith(q))
            return 50;
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

    // Recent files read like CuboCore's activities view: one group per day,
    // newest first. xbel times are ISO, so a day is the local calendar day;
    // the key comes from the shared Time.js so a fix reaches every dated view.
    function recentDayKey(v) {
        return Time.dayKey(v);
    }
    function recentDayLabel(key, todayKey, yesterdayKey) {
        if (key === todayKey) return Tr.t("Today");
        if (key === yesterdayKey) return Tr.t("Yesterday");
        const p = key.split("-").map(Number);
        return Qt.formatDate(new Date(p[0], p[1] - 1, p[2]), "d MMM");
    }
    // Undated entries keep one flat "Recent files" group: nothing is dropped,
    // and no day is guessed for them. That is also the whole fallback when a
    // writer records no dates at all.
    function groupRecent(entries, perGroup) {
        const now = new Date();
        const todayKey = win.recentDayKey(now);
        const yesterdayKey = win.recentDayKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1));
        const groups = [];
        const byKey = {};
        let other = null;
        for (const r of entries) {
            const key = win.recentDayKey(r.when);
            if (!key) {
                if (!other) other = { key: "", label: Tr.t("Recent files"), items: [] };
                if (other.items.length < perGroup) other.items.push(r);
                continue;
            }
            let g = byKey[key];
            if (!g) {
                g = { key: key, label: win.recentDayLabel(key, todayKey, yesterdayKey), items: [] };
                byKey[key] = g;
                groups.push(g);
            }
            if (g.items.length < perGroup) g.items.push(r);
        }
        return groups.concat(other ? [other] : []);
    }

    // "web:" is an engine picker (KRunner's runners, Spotlight's web results):
    // the default engine stays the one-row answer in More, this lists them all.
    function webEngines(text) {
        const t = (text || "").trim();
        const items = Object.keys(Ui.webSearches).map(k => {
            const e = Ui.webSearches[k];
            return { kind: "web", icon: "web-browser",
                title: t ? e[0] + ": “" + t + "”" : e[0],
                subtitle: t ? Tr.t("Open in %1", e[0]) : Tr.t("Type your search after web:"),
                run: () => t && Qt.openUrlExternally(e[1] + encodeURIComponent(t)) };
        });
        return [{ title: Tr.t("Search the web"), group: "web", items: items }];
    }
    // The three "nothing matched" states: a plain dead query, a narrow operator
    // with no hits, and an operator with no term at all. Each offers a way on.
    function noResults(text, op) {
        const t = (text || "").trim();
        const hint = op ? Tr.t("Try another search, or drop the prefix") : Tr.t("Try a shorter word, or app:, file:, web: or clip:");
        return { title: Tr.t("No results"), group: "meta", items: [
            { kind: "none", icon: "edit-find",
              title: t ? Tr.t("No matches for “%1”", t) : Tr.t("Nothing to search for"),
              subtitle: hint, run: () => {} }
        ] };
    }
    function operatorHelp(op) {
        const ex = ({ app: "app:firefox", file: "file:report", web: "web:weather",
                      clip: "clip:meeting", action: "action:dark", tool: "tool:dictionary" })[op] || op + ":";
        return { title: Tr.t("Search %1", op), group: "meta", items: [
            { kind: "none", icon: "system-search", title: op + ":",
              subtitle: Tr.t("Example: %1", ex),
              run: () => { search.text = ex; search.forceActiveFocus(); } }
        ] };
    }

    // parental controls' blocked apps are left out (AppFilter)
    readonly property var apps: DesktopEntries.applications.values.filter(a => !a.noDisplay && AppFilter.allowed(a.id))
    readonly property var appWords: { const m = {}; for (const a of apps) m[a.id] = Fuzzy.words(a.name + " " + (a.genericName || "")); return m; }
    // desktop entries say "Network", the chip is called "Internet"; filter on
    // the id and only change the label, so the chip reaches Mail/Feeds/IRC etc.
    readonly property var categories: ["All", "Network", "Office", "Graphics", "AudioVideo", "Development", "Utility", "System", "Game"]
    readonly property var categoryNames: ({ AudioVideo: "Media", Network: "Internet" })
    // colored filters in the field: the families of answers — All, Apps,
    // Files. Each has a color the pill is drawn with; the launcher itself
    // answers them as section groups.
    property string filter: "all"
    readonly property var filters: [
        { id: "all", title: Tr.t("All"), color: Theme.faint },
        { id: "app", title: Tr.t("Apps"), color: Theme.accent },
        { id: "file", title: Tr.t("Files"), color: Theme.dim }
    ]

    // ---- the answer, as sections; `flat` is what the keyboard walks ----------
    readonly property var sections: {
        const parsed = LauncherEntries.parseQuery(win.q.trim());
        const op = parsed.op;
        // "clip:" is the clipboard mode by another name; every other operator
        // strips its prefix and keeps the remainder as the query. The legacy
        // = : c > ? modes still read q unchanged.
        const q = op === "clip" ? "c " + parsed.text : (op ? parsed.text : win.q.trim());
        const ql = q.toLowerCase();
        const out = [];
        const used = a => win.usage[a.id] || 0;
        // two apps can share a display name: show the desktop id to tell them apart
        const nameCount = {};
        win.apps.forEach(a => { nameCount[a.name] = (nameCount[a.name] || 0) + 1; });
        const appItem = a => ({ kind: "app", app: a.icon, did: a.id, title: a.name,
            subtitle: (a.genericName || a.comment || "") + (nameCount[a.name] > 1 ? " · " + a.id : ""),
            run: () => win.launch(a) });
        // `app` is only ever the name xbel's bookmark:application metadata gave us;
        // without it the subtitle is just the path (no guessing from extensions)
        // the same dispatcher Files' double-click uses: a .txt opens in the
        // shell's editor here too, not in whatever xdg-open picks
        const fileItem = (p, app) => ({ kind: "file", icon: win.fileIcon(p), path: p, title: p.split("/").pop(), subtitle: (app ? app + " · " : "") + p.replace(Quickshell.env("HOME"), "~"), run: () => Files.openEntry(p) });

        // One exit for every answer below: operators keep only their own family,
        // a bare operator offers an example, and a dead query says so instead of
        // hiding behind "Ask Chronoa". Each section carries the group it belongs to.
        const finish = () => {
            if (op === "web")
                return parsed.empty ? [win.operatorHelp(op)] : win.webEngines(parsed.text);
            if (op) {
                if (parsed.empty) return [win.operatorHelp(op)];
                const kept = out.filter(s => s.group === op);
                return kept.length ? kept : [win.noResults(parsed.text, op)];
            }
            if (q !== "" && !out.some(s => s.group && s.group !== "meta"))
                out.unshift(win.noResults(q, ""));
            return out;
        };

        if (q === "") {
            // a bare "app:" / "web:" / "file:" never falls through to the app grid
            if (op) return [win.operatorHelp(op)];
            // Queries submitted earlier (Spotlight's recent searches): one tap
            // re-runs one, Shift+Delete forgets it, the last row clears them all.
            const hs = LauncherEntries.searchHistory;
            if (hs.length) {
                const hitems = hs.map(h => ({ kind: "history", icon: "edit-find", title: h,
                    subtitle: Tr.t("Enter to search again · Shift+Delete to forget"),
                    run: () => { search.text = h; search.forceActiveFocus(); },
                    remove: () => LauncherEntries.forget(h) }));
                hitems.push({ kind: "history", icon: "edit-clear", title: Tr.t("Clear search history"),
                    subtitle: Tr.t("Forget every recent search"), run: () => LauncherEntries.clearHistory() });
                out.push({ title: Tr.t("Recent searches"), group: "history", items: hitems });
            }
            const frequent = win.apps.filter(a => used(a) > 0).sort((a, b) => used(b) - used(a)).slice(0, 8);
            if (frequent.length)
                out.push({ title: Tr.t("Frequent"), grid: true, group: "app", items: frequent.map(appItem) });
            for (const g of win.groupRecent(win.recent.slice(0, 18), 6))
                out.push({ title: g.key ? Tr.t("Recent files") + " · " + g.label : g.label,
                           group: "file", items: g.items.map(r => fileItem(r.path, r.app)) });
            const all = win.apps.filter(a => win.category === "All" || [].concat(a.categories || []).indexOf(win.category) >= 0)
                .sort((a, b) => a.name.localeCompare(b.name));
            out.push({ title: Tr.t("All apps"), grid: true, chips: true, group: "app", items: all.map(appItem) });
            return out;
        }
        if (q.startsWith("?")) {
            const t = q.slice(1).trim();
            return [{ title: Tr.t("Chronoa"), group: "meta", items: [{ kind: "ask", icon: "chat-message-new", title: t ? "Ask Chronoa: " + t : "Ask Chronoa…", subtitle: Settings.data.launcherHideNavLabels ? "" : Tr.t("Enter"), run: () => t && Chronoa.ask(t) }] }];
        }
        if (q.startsWith(">")) {
            const cmd = q.slice(1).trim();
            return [{ title: Tr.t("Run"), group: "run", items: [
                { kind: "run", icon: "utilities-terminal", title: cmd ? "Run: " + cmd : "Run a command…", subtitle: "Shift+Enter: in " + Settings.data.terminal,
                  run: shift => cmd && Quickshell.execDetached(shift ? [Settings.data.terminal, "-e", "sh", "-c", cmd + "; exec $SHELL"] : ["sh", "-c", cmd]) },
                { kind: "run", icon: "dialog-password", title: cmd ? "Run as administrator: " + cmd : "Run as administrator…",
                  subtitle: Tr.t("pkexec · your password is asked in the shell"),
                  run: () => cmd && win.runAdmin(cmd) }
            ] }];
        }
        if (q.startsWith(":")) {
            const f = q.slice(1).trim().toLowerCase();
            if (win.emojiPath === "")
                Qt.callLater(() => win.emojiPath = "/usr/share/unicode/emoji/emoji-test.txt");
            // variation selectors (VS15 U+FE0E / VS16 U+FE0F) are stripped for
            // the search, so "smiling face" matches both emoji- and text-presentation
            // entries and the glyph itself is searchable too
            const norm = f.replace(/[\uFE0E\uFE0F]/g, "");
            const emoMatch = x => { const n = String(x.name || "").toLowerCase();
                return f === "" || n.indexOf(f) >= 0 || n.indexOf(norm) >= 0; };
            const emoGlyph = x => { const g = String(x.e || "").toLowerCase();
                return f !== "" && norm !== "" && g.indexOf(norm) >= 0; };
            // full Unicode as well as emoji (Characters service, by
            // bridge/characters.py): symbols, math, arrows, Indic scripts -
            // asked for in onQChanged, not here: setting Characters.query
            // inside this binding, which reads it, was a binding loop
            const seen = {};
            const emojiItems = win.emoji.filter(x => emoMatch(x) || emoGlyph(x)).map(x => ({ kind: "emoji", glyph: x.e, icon: "face-smile-big", title: x.name,
                subtitle: Tr.t("Enter types it · Shift+Enter copies"), run: shift => shift ? Quickshell.clipboardText = x.e : Clipboard.typeText(x.e) }));
            for (const it of emojiItems) seen[it.glyph] = true;
            const charItems = (Characters.results || []).filter(x => emoMatch(x)).map(x => {
                if (seen[x.ch]) return null;
                seen[x.ch] = true;
                return { kind: "emoji", glyph: x.ch, icon: "face-smile-big", title: x.name, subtitle: ("U+" + x.cp.toString(16).toUpperCase().padStart(4, "0")) + " · " + Tr.t("Enter types it · Shift+Enter copies"), run: shift => shift ? Quickshell.clipboardText = x.ch : Clipboard.typeText(x.ch) };
            }).filter(Boolean);
            const all = emojiItems.concat(charItems).slice(0, 40);
            return [{ title: Tr.t("Emoji & characters"), group: "emoji", items: all }];
        }
        if (q === "c" || q.startsWith("c ")) {
            const f = q.slice(1).trim().toLowerCase();
            const pins = Array.from(Settings.data.clipPins).filter(t => f === "" || t.toLowerCase().indexOf(f) >= 0)
                .map(t => ({ kind: "clip", icon: "view-pin", title: t.replace(/\s+/g, " ").slice(0, 140), subtitle: Tr.t("Pinned · Enter pastes · Shift+Enter copies · Ctrl+P unpins"),
                             run: shift => shift ? Quickshell.clipboardText = t : Clipboard.setAndPaste(t), pin: () => Clipboard.unpin(t) }));
            const items = Clipboard.entries.filter(e => f === "" || e.text.toLowerCase().indexOf(f) >= 0).slice(0, 30)
                .map(e => ({ kind: "clip", icon: e.image ? "image-x-generic" : "edit-paste", thumb: e.image ? e.preview : "",
                             title: e.text.replace(/\s+/g, " ").slice(0, 140), subtitle: (!e.image && Clipboard.originOf(e.text) ? Tr.t("From %1", Clipboard.originOf(e.text)) + " · " : "") + (e.image ? Tr.t("Picture · Enter pastes it · Shift+Enter copies") : Tr.t("Enter pastes it · Shift+Enter copies · Ctrl+P pins")) + " · " + Tr.t("Shift+Delete removes it"),
                             run: shift => shift ? Clipboard.copy(e) : Clipboard.copyAndPaste(e), remove: () => Clipboard.remove(e), pin: e.image ? null : () => Clipboard.pin(e) }));
            const clipItems = items.length ? items
                : [{ kind: "none", icon: "edit-paste", title: Clipboard.available ? "Clipboard history is empty" : "cliphist is not installed", subtitle: "", run: () => {} }];
            if (items.length && Clipboard.available)
                clipItems.push({ kind: "clipclear", icon: "edit-clear", title: Tr.t("Clear clipboard history"), subtitle: Tr.t("Shift+Delete clears all"), run: () => Clipboard.wipe() });
            const out = (pins.length ? [{ title: Tr.t("Pinned"), group: "clip", items: pins }] : []).concat([{ title: Tr.t("Clipboard"), group: "clip", items: clipItems }]);
            // the numbered history is a window of its own; one row reaches it
            // from the same "c " mode, so it works with the clip: operator too
            out.push({ title: Tr.t("Clipboard history"), group: "clip", items: [
                { kind: "clip", icon: "edit-paste", title: Tr.t("Paste history"),
                  subtitle: Tr.t("Open the numbered clipboard history"),
                  run: () => { Ui.closeAll(); Ui.pasteHistory = true; } }
            ] });
            // quick changes: transform the most recent text entry
            const latest = items.find(e => !e.image);
            if (latest && Clipboard.available) {
                const transforms = [
                    { title: Tr.t("UPPERCASE"), icon: "text-case-upper", mode: "upper" },
                    { title: Tr.t("lowercase"), icon: "text-case-lower", mode: "lower" },
                    { title: Tr.t("Title Case"), icon: "text-case-title", mode: "title" },
                    { title: Tr.t("Plain text"), icon: "text-x-generic", mode: "plain" },
                    { title: Tr.t("Trim whitespace"), icon: "edit-clear", mode: "trim" },
                ];
                out.push({ title: Tr.t("Quick changes"), group: "clip", items: transforms.map(t => ({
                    kind: "clip", icon: t.icon, title: t.title, subtitle: Tr.t("Paste the latest clipboard text as %1", t.title.toLowerCase()),
                    run: () => Clipboard.transformAndPaste(latest.text, t.mode),
                })) });
            }
            return out;
        }

        const math = q.startsWith("=") ? q.slice(1) : q;
        // the Calculator app's angle unit, so sin(30) means the same everywhere
        const v = math !== "" ? Calc.calc(math, Calculator.angleUnit) : null;
        if (v !== null && Settings.data.searchCalc)
            out.push({ title: Tr.t("Calculator"), group: "calc", items: [{ kind: "calc", icon: "accessories-calculator", title: "= " + v, subtitle: Tr.t("Enter copies the result"), run: () => Quickshell.clipboardText = String(v) }] });
        const conv = Settings.data.searchCalc ? Calc.convert(q) : null;
        if (conv)
            out.push({ title: Tr.t("Convert"), group: "calc", items: [{ kind: "calc", icon: "accessories-calculator", title: "= " + conv.text, subtitle: Tr.t("Enter copies"), run: () => Quickshell.clipboardText = String(Number(conv.value.toPrecision(8))) }] });
        if (Settings.data.searchCalc && Calc.isCurrency(q))
            out.push({ title: Tr.t("Currency"), group: "meta", items: [{ kind: "ask", icon: "chat-message-new", title: "Convert " + q + " with Chronoa", subtitle: Tr.t("live rates"), run: () => Chronoa.ask("Convert " + q) }] });
        if (q.startsWith("="))
            return finish();

        // contacts search (name, phone, email). Guarded: the launcher is the
        // primary surface, and an address book that fails to read must not take
        // every search down with it.
        try {
        if (Contacts.contacts.length > 0) {
            const ql = q.toLowerCase();
            const matches = Contacts.contacts.filter(c =>
                (c.name || "").toLowerCase().indexOf(ql) >= 0
                || (c.phone || "").indexOf(q) >= 0
                || (c.email || "").toLowerCase().indexOf(ql) >= 0
            ).slice(0, 5);
            if (matches.length) {
                out.push({ title: Tr.t("Contacts"), group: "contact", items: matches.map(c => ({
                    kind: "contact",
                    icon: "x-office-address-book",
                    title: c.name || c.phone || c.email,
                    subtitle: [c.phone, c.email].filter(x => x).join("  ·  "),
                    run: () => { Ui.closeAll(); Ui.contacts = true; Contacts.selected = c; },
                    copy: () => Quickshell.clipboardText = c.phone || c.email || "",
                })) });
            }
        }

        } catch (e) {}

        // calendar events (today and upcoming, matching the query)
        try {
        if (Agenda.events.length > 0) {
            const ql = q.toLowerCase();
            const matches = Agenda.events.filter(e =>
                (e.title || "").toLowerCase().indexOf(ql) >= 0
            ).slice(0, 5);
            if (matches.length) {
                out.push({ title: Tr.t("Events"), group: "event", items: matches.map(e => ({
                    kind: "event",
                    icon: "x-office-calendar",
                    title: e.title || Tr.t("Untitled event"),
                    subtitle: e.start ? Qt.formatDateTime(new Date(e.start * 1000), Settings.data.use24h ? "ddd HH:mm" : "ddd h:mm AP") : "",
                    run: () => { Ui.closeAll(); Ui.calendar = true; },
                })) });
            }
        }
        } catch (e) {}

        // notes search (QuickNotes)
        // notes search (QuickNotes), also guarded: a note backend that fails
        // must not take the app search down with it
        try {
        {
            const noteMatches = QuickNotes.search(q);
            if (noteMatches.length > 0) {
                out.push({ title: Tr.t("Notes"), group: "note", items: noteMatches.slice(0, 5).map(n => ({
                    kind: "note",
                    icon: "text-x-generic",
                    title: n.name,
                    subtitle: (n.notebook ? n.notebook + "  ·  " : "") + (QuickNotes.preview(n.name, n.notebook) || "").slice(0, 60),
                    run: () => { Ui.closeAll(); Ui.notes = true; QuickNotes.open(n.name, n.notebook || ""); },
                })) });
            }
            // also search note bodies. The search itself is asked for in
            // onQChanged: running it here writes contentHits, which this binding
            // reads - a loop that spins the shell and empties every answer.
            if (noteMatches.length === 0 && q.length >= 3) {
                if (QuickNotes.contentHits && QuickNotes.contentHits.length > 0) {
                    out.push({ title: Tr.t("Notes (in content)"), group: "note", items: QuickNotes.contentHits.slice(0, 5).map(id => ({
                        kind: "note",
                        icon: "text-x-generic",
                        title: id,
                        subtitle: Tr.t("Found in note content"),
                        run: () => { Ui.closeAll(); Ui.notes = true; QuickNotes.open(id.split("/").pop(), id.includes("/") ? id.split("/")[0] : ""); },
                    })) });
                }
            }
        }
        } catch (e) {}

        // a typo forgiven ("fierfox"), ranked below every exact, prefix and inside match
        const ranked = win.apps.map(a => { const s = win.appScore(a, ql); return { a: a, s: s > 0 ? s : Fuzzy.score(win.appWords[a.id], ql) }; }).filter(x => x.s > 0)
            // multiply the class score so usage only breaks ties inside a class
            .map(x => ({ a: x.a, s: x.s * 1000 + Math.min(15, used(x.a)) })).sort((x, y) => y.s - x.s).map(x => x.a);
        if (ranked.length) {
            const items = [];
            ranked.slice(0, 12).forEach((a, i) => {
                items.push(appItem(a));
                if (i === 0)        // the top match also offers its desktop actions
                    for (const act of a.actions)
                        items.push({ kind: "app", app: a.icon, title: a.name + " — " + act.name, subtitle: Tr.t("action"), run: () => win.launch(a, act.id) });
            });
            out.push({ title: Tr.t("Apps"), group: "app", items: items });
        }
        const wins = Object.values(Niri.windows).filter(w => win.score(w.title, ql) > 0 || win.score(w.app_id, ql) > 0).slice(0, 6);
        if (wins.length)
            out.push({ title: Tr.t("Windows"), group: "window", items: wins.map(w => {
                const e = DesktopEntries.heuristicLookup(w.app_id || "");
                return { kind: "window", app: e ? e.icon : w.app_id, title: w.title || w.app_id, subtitle: Niri.workspaceLabel(w.workspace_id), run: () => Niri.focusWin(w) };
            }) });
        let acts = win.actions.filter(a => win.score(a.title, ql) > 0 || win.allWords(a.title + " " + a.words, ql));
        if (acts.length < 6)
            acts = acts.concat(win.actions.map((a, i) => ({ a: a, s: acts.indexOf(a) < 0 ? Fuzzy.score(win.actionWords[i], ql) : 0 }))
                .filter(x => x.s > 0).sort((x, y) => y.s - x.s).map(x => x.a));
        // the tool: operator and the bar's "tool" chip are only for the nine built-in tools
        if (op === "tool" || q.trim().toLowerCase() === "tool") acts = acts.filter(a => /\btool\b/.test(a.words));
        // the bar's "tool" chip and the tool: operator want all nine tools, not six
        acts = acts.slice(0, (op === "tool" || q.trim().toLowerCase() === "tool") ? 9 : 6);
        if (acts.length)
            out.push({ title: Tr.t("Actions"), group: op === "tool" ? "tool" : "action", items: acts.map(a => ({ kind: "action", icon: a.icon, title: a.title,
                subtitle: a.state ? (a.state() ? "On — Enter turns off" : "Off — Enter turns on") : "", run: a.run })) });
        const files = win.recent.filter(r => r.name.toLowerCase().indexOf(ql) >= 0).map(r => r.path);
        const allFiles = files.concat(win.found.filter(p => files.indexOf(p) < 0)).slice(0, 10);
        const byContent = win.inside.filter(p => allFiles.indexOf(p) < 0).slice(0, 6);
        if (allFiles.length || byContent.length)
            out.push({ title: Tr.t("Files"), group: "file", items: allFiles.map(fileItem).concat(byContent.map(p => Object.assign(fileItem(p), { subtitle: "contains “" + q + "” · " + p.replace(Quickshell.env("HOME"), "~") }))) });
        // what Chronoa's index found, by meaning (or by words, when it says so)
        const meant = win.meaning.filter(m => allFiles.indexOf(m.path) < 0 && byContent.indexOf(m.path) < 0).slice(0, 6);
        if (meant.length)
            out.push({ title: /embedding/.test(win.meaningHow) ? Tr.t("In your files, by meaning") : Tr.t("In your files"),
                       group: "file",
                       items: meant.map(m => Object.assign(fileItem(m.path), { subtitle: (m.excerpt ? "“" + m.excerpt.slice(0, 90) + "…” · " : "") + m.path.replace(Quickshell.env("HOME"), "~") })) });
        // what the apps themselves found, one section per app
        // a sum the launcher already answered is not answered again by Calculator's own provider
        const answered = out.some(s => s.items.some(i => i.kind === "calc"));
        for (const app of [...new Set(win.provided.filter(r => !(answered && /calculator/i.test(String(r.bus) + " " + r.app))).map(r => r.app))].slice(0, 4))
            out.push({ title: "From " + app, group: "provided", items: win.provided.filter(r => r.app === app).slice(0, 4).map(r => ({
                kind: "provided", app: r.icon, title: r.name, subtitle: r.description,
                run: () => Quickshell.execDetached(["python3", win.providersTool, "activate", r.bus, r.path, r.id].concat(q.split(/\s+/))) })) });
        // "Ask Chronoa" takes over only what nothing else could answer: it lands
        // last, so it is the first item exactly when the search found nothing
        // and never pushes a real match out of the top spot. A sum the
        // calculator already answered is not a question, so it gets none.
        const calcAnswered = out.some(s => s.items.some(i => i.kind === "calc"));
        if (q !== "" && Settings.data.searchMeaning !== false && !calcAnswered)
            out.push({ title: Tr.t("Ask Chronoa"), group: "meta", items: [
                { kind: "ask", icon: "chat-message-new", title: "Ask Chronoa: " + q, subtitle: Tr.t("Enter to ask in your own words"), run: () => Chronoa.ask(q) }
            ] });
        out.push({ title: Tr.t("More"), group: "meta", items: [
            { kind: "web", icon: "web-browser", title: "Search the web for “" + q + "”", subtitle: Ui.webSearchName(), run: () => Qt.openUrlExternally(Ui.webSearchUrl(q)) },
            // discoverability for the engine picker without leaving the field
            { kind: "web", icon: "web-search", title: Tr.t("Choose a search engine…"), subtitle: Tr.t("Or type web: then your query"),
              run: () => { search.text = "web:"; search.forceActiveFocus(); } }
        ] });
        const done = finish();
        // colored filters: "app:"/"file:"/all as the field is set (the operator
        // lane of the query and the pill are the same thing)
        return win.filter === "all" ? done : done.filter(s => s.group === win.filter);
    }
    readonly property var flat: sections.reduce((acc, s) => acc.concat(s.items), [])
    readonly property var current: flat[Math.max(0, Math.min(sel, flat.length - 1))] || null
    onCurrentChanged: Ui.launcherSelected = current ? (current.title || "") : ""
    onFlatChanged: { Ui.topResult = flat.length > 0 ? flat[0].title : ""; Ui.launcherFiles = flat.filter(x => x.kind === "file").length; }
    onSectionsChanged: Ui.launcherSections = sections.map(x => x.title)
    onQChanged: {
        searchBar = false;
        const p = LauncherEntries.parseQuery(q);
        searchText = p.text;
        if (q.startsWith(":") && Characters.query !== q.slice(1).trim())
            Characters.search(q.slice(1).trim());
        Ui.launcherText = q;
        if (q.trim().length < 4) meaning = [];
        if (q.trim().length >= 3) QuickNotes.searchBodies(q.trim());
        sel = 0;
        fileDebounce.restart();
        if (q === "c" || q.startsWith("c ") || p.op === "clip")
            Clipboard.refresh();
    }

    function activate(i, shift) {
        const r = flat[Math.max(0, Math.min(i, flat.length - 1))];
        if (!r)
            return;
        // only a submitted query becomes a recent search, not every keystroke
        if (!shift && win.q.trim())
            LauncherEntries.remember(win.q.trim());
        Ui.closeAll();
        r.run(shift);
    }
    function askChronoa() {
        const t = q.trim().replace(/^\?/, "").trim();
        const c = current;
        Ui.closeAll();
        // a question typed here wants its answer seen: the conversation opens
        // with it (the Island alone showed "thinking", then nothing - the
        // answer went nowhere a person could read; found filming the README demo)
        if (c && c.kind === "file") {
            Chronoa.ask((t ? t + "\n" : "What is this file, and what can I do with it?\n") + "The file: " + c.path);
            Chronoa.open = true;
        } else if (t) {
            Chronoa.ask(t);
            Chronoa.open = true;
        } else
            Ui.askIsland();
    }

    onVisibleChanged: {
        searchBar = false;
        if (visible) {
            hoverArmed = false;     // a resting pointer must not steal the top result
            appear.restart();
            search.text = Ui.launcherQuery;
            sel = 0;
            category = "All";
            // a phone opens on its apps; the keyboard comes when the search box is tapped
            if (FormFactor.of(win.screen ? win.screen.name : "").profile !== "phone" || Ui.launcherQuery !== "")
                search.forceActiveFocus();
        }
    }

    // ---- drawing ----------------------------------------------------------------
    Rectangle {
        id: backdrop
        anchors.fill: parent
        // glass over a blur of what is behind: the shell's material language
        // (opaque when blur is off, so text still reads on a plain compositor)
        color: Theme.alpha(Theme.bg, Settings.blurWanted ? 0.78 : 0.94)
        MouseArea { objectName: "nav:pointer"; anchors.fill: parent; onClicked: Ui.closeAll(); hoverEnabled: !Settings.data.launcherIgnoreMouse; onPositionChanged: if (!Settings.data.launcherIgnoreMouse) win.hoverArmed = true }
    }

    // opens with a short fade and rise (instant with reduce motion)
    ParallelAnimation {
        id: appear
        NumberAnimation { target: body; property: "opacity"; from: 0; to: 1; duration: Theme.animEnter * 0.6; easing.type: Easing.OutCubic }
        NumberAnimation { target: rise; property: "y"; from: 28; to: 0; duration: Theme.animEnter; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
    }

    ColumnLayout {
        id: body
        transform: Translate { id: rise }
        anchors.fill: parent
        // computed sizes through the UI scale too; a phone's width keeps a narrow margin
        anchors.topMargin: win.narrow ? Theme.px(12) : Math.max(Theme.px(60), parent.height * 0.08)
        anchors.bottomMargin: Math.max(Theme.px(40), Osk.heightOn(win.screen.name) + Theme.px(12))
        // the suite reads this: the results stop above the screen keyboard
        readonly property real keyboardGap: Math.max(Theme.px(40), Osk.heightOn(win.screen.name) + Theme.px(12))
        anchors.leftMargin: Math.max(parent.width < Theme.px(600) ? Theme.px(10) : Theme.px(40), (parent.width - Theme.px(1280)) / 2)
        anchors.rightMargin: Math.max(parent.width < Theme.px(600) ? Theme.px(10) : Theme.px(40), (parent.width - Theme.px(1280)) / 2)
        spacing: Theme.px(18)

        // the field
        Glass {
            Layout.fillWidth: true
            Layout.preferredWidth: Theme.px(900)
            Layout.maximumWidth: Theme.px(900)
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: Theme.px(58)
            strong: true
            radius: Theme.px(29)
            // the remote's cursor on the search bar
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: win.searchBar ? 3 : 0
                border.color: Theme.accent
            }
            MouseArea { anchors.fill: parent; objectName: "nav:pointer" }   // swallows clicks: they do not close it
            // a finger on the search bar swipes the launcher away, down; the
            // results below scroll as always
            DragHandler {
                target: null
                xAxis.enabled: false
                acceptedDevices: PointerDevice.TouchScreen
                onActiveChanged: if (!active && G.dismissed("down", translation.x, translation.y, Theme.px(80))) Ui.closeAll()
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.px(22)
                anchors.rightMargin: Theme.px(22)
                spacing: Theme.px(12)
                Icon { name: "system-search"; size: Theme.px(22); color: Theme.accent }
                // colored filters, All/Apps/Files: the field can be narrowed to
                // one family without typing anything (the "app:"/"file:"
                // operators narrow it too, in the answers)
                Repeater {
                    model: win.filters
                    Choice {
                        required property var modelData
                        text: modelData.title
                        selected: win.filter === modelData.id
                        visible: !win.narrow || modelData.id !== "file"
                        onClicked: { win.filter = modelData.id; search.forceActiveFocus(); }
                    }
                }
                TextInput {
                    id: search
                    activeFocusOnTab: true          // the d-pad and Tab reach it (a pad's LB / RB leave it: Ui.navJump)
                    Accessible.role: Accessible.EditableText
                    Accessible.name: Tr.t("Search apps, files, settings and the web")
                    Layout.fillWidth: true
                    color: Theme.text
                    selectionColor: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.px(20) * Theme.fontScale
                    clip: true
                    onActiveFocusChanged: Ui.trackTextInput(search, activeFocus)
                    Component.onDestruction: Ui.trackTextInput(search, false)
                    Keys.onEscapePressed: Ui.closeAll()
                    Keys.onDownPressed: {
                        if (win.searchBar) { win.searchBar = false; return; }
                        win.sel = Math.min(win.sel + (win.q === "" ? win.gridCols : 1), win.flat.length - 1);
                    }
                    // Up from the top row reaches the search bar (a TV's way to the
                    // keyboard): OK there brings the screen keyboard for a remote
                    Keys.onUpPressed: {
                        if (win.sel < (win.q === "" ? win.gridCols : 1)) win.searchBar = true;
                        else win.sel = Math.max(win.sel - (win.q === "" ? win.gridCols : 1), 0);
                    }
                    // Home/End jump to the first/last answer (handled in the
                    // shared onPressed below); Tab already wraps the same list.
                    Keys.onTabPressed: win.sel = (win.sel + 1) % Math.max(1, win.flat.length)
                    Keys.onBacktabPressed: win.sel = (win.sel - 1 + win.flat.length) % Math.max(1, win.flat.length)
                    Keys.onPressed: e => {
                        // Home/End: first/last answer, like GNOME/Spotlight
                        if (e.key === Qt.Key_Home && win.flat.length) { win.sel = 0; e.accepted = true; return; }
                        if (e.key === Qt.Key_End && win.flat.length) { win.sel = win.flat.length - 1; e.accepted = true; return; }
                        // PageUp/PageDown: a page of the results, so a long
                        // answer list is reachable with the pad only
                        if (e.key === Qt.Key_PageUp && win.flat.length) { win.sel = Math.max(0, win.sel - win.pageRows); e.accepted = true; return; }
                        if (e.key === Qt.Key_PageDown && win.flat.length) { win.sel = Math.min(win.flat.length - 1, win.sel + win.pageRows); e.accepted = true; return; }
                        // Ctrl+P: pin or unpin a clipboard entry
                        if (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier) && win.flat[win.sel] && win.flat[win.sel].pin) {
                            win.flat[win.sel].pin();
                            e.accepted = true;
                            return;
                        }
                        // Ctrl+C: a contact result offers its phone/email to copy,
                        // but never when the person is copying selected query text
                        if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier) && search.selectedText === ""
                            && win.flat[win.sel] && win.flat[win.sel].copy) {
                            win.flat[win.sel].copy();
                            e.accepted = true;
                            return;
                        }
                        // Ctrl+Y: Quick Look at the highlighted file, else the first file found
                        // (as Spotlight's), Left/Right walking the others
                        const files = e.key === Qt.Key_Y && (e.modifiers & Qt.ControlModifier) ? win.flat.filter(x => x.kind === "file").map(x => x.path) : [];
                        if (files.length) {
                            const at = win.current && win.current.kind === "file" ? win.current.path : files[0];
                            Ui.closeAll();
                            QuickLook.open(at, files);
                            e.accepted = true;
                            return;
                        }
                        // Shift+Delete: remove clipboard entry or clear all in clipboard view
                        if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier)) {
                            if (win.flat[win.sel] && win.flat[win.sel].remove) {
                                win.flat[win.sel].remove();
                                e.accepted = true;
                                return;
                            }
                            if ((win.q === "c" || win.q.startsWith("c ")) && Clipboard.available) {
                                Clipboard.wipe();
                                e.accepted = true;
                                return;
                            }
                        }
                        if (win.q === "" && (e.key === Qt.Key_Right || e.key === Qt.Key_Left)) {
                            win.sel = Math.max(0, Math.min(win.flat.length - 1, win.sel + (e.key === Qt.Key_Right ? 1 : -1)));
                            e.accepted = true;
                        }
                    }
                    Keys.onReturnPressed: e => win.searchBar ? (win.searchBar = false, Osk.openRemote())
                        : (e.modifiers & Qt.ControlModifier) ? win.askChronoa() : win.activate(win.sel, e.modifiers & Qt.ShiftModifier)
                    Keys.onEnterPressed: e => (e.modifiers & Qt.ControlModifier) ? win.askChronoa() : win.activate(win.sel, e.modifiers & Qt.ShiftModifier)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        visible: search.text === ""
                        text: Tr.t("Search apps, files, windows and actions — or ask Chronoa")
                        elide: Text.ElideRight
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.px(17) * Theme.fontScale
                    }
                }
                Text {
                    visible: !win.narrow
                    text: Tr.t("Ctrl+Enter  Chronoa")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.px(18)

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
                    spacing: Theme.px(14)

                    Repeater {
                        model: win.sections
                        ColumnLayout {
                            id: section
                            required property var modelData
                            required property int index
                            // where this section's items start in `flat`
                            readonly property int base: win.sections.slice(0, index).reduce((n, s) => n + s.items.length, 0)
                            Layout.fillWidth: true
                            spacing: Theme.px(8)

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Accessible.role: Accessible.Heading
                                    text: section.modelData.title
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(12) * Theme.fontScale
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
                                // the arrows move the launcher's own highlight over these (launcherSelected)
                                objectName: "nav:keys"
                                visible: !!section.modelData.grid
                                Layout.fillWidth: true
                                // one frequent app must not stretch across all columns
                                columns: section.modelData.grid ? Math.min(win.gridCols, Math.max(1, section.modelData.items.length)) : win.gridCols
                                columnSpacing: Theme.px(8)
                                rowSpacing: Theme.px(8)
                                Repeater {
                                    model: section.modelData.grid ? section.modelData.items : []
                                    Rectangle {
                                        id: tile
                                        required property var modelData
                                        required property int index
                                        readonly property bool isSel: win.sel === section.base + index
                                        Accessible.role: Accessible.ListItem
                                        Accessible.name: (tile.modelData.title || "") + (tile.modelData.subtitle ? ", " + tile.modelData.subtitle : "")
                                        Layout.fillWidth: true
                                        // a phone: four equal columns, however long a name (it wraps)
                                        Layout.preferredWidth: win.phone ? win.phoneCell : -1
                                        Layout.maximumWidth: win.phone ? win.phoneCell : Number.POSITIVE_INFINITY
                                        implicitHeight: win.phone ? Theme.px(88) : Theme.px(112)
                                        radius: Theme.px(18)
                                        color: isSel ? Theme.accentSoft : (win.hoverArmed && tileArea.containsMouse ? Theme.hover : "transparent")
                                        border.width: isSel ? 1 : 0
                                        border.color: Theme.accentLine
                                        // drag an app onto the dock to pin it (the dock reads shani-app:<desktop id>)
                                        Item { id: appDragProxy; width: 1; height: 1; z: -1 }
                                        Drag.active: tileArea.drag.active
                                        Drag.dragType: Drag.Automatic
                                        Drag.mimeData: ({ "text/plain": "shani-app:" + (tile.modelData.did || "") })
                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            width: parent.width - 16
                                            spacing: Theme.px(8)
                                            IconImage {
                                                Layout.alignment: Qt.AlignHCenter
                                                implicitSize: win.phone ? 44 : 54
                                                source: Quickshell.iconPath(tile.modelData.app, "application-x-executable")
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: tile.modelData.title
                                                color: Theme.text
                                                wrapMode: Text.Wrap
                                                maximumLineCount: 2
                                                elide: Text.ElideRight
                                                font.family: Theme.font
                                                font.pixelSize: Theme.px(12) * Theme.fontScale
                                            }
                                        }
                                        MouseArea {
                                            id: tileArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            drag.target: appDragProxy
                                            drag.threshold: 8
                                            onEntered: if (win.hoverArmed) win.sel = section.base + tile.index
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
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: (row.modelData.title || "") + (row.modelData.subtitle ? ", " + row.modelData.subtitle : "")
                                    Layout.fillWidth: true
                                    implicitHeight: Theme.px(48)
                                    radius: Theme.px(14)
                                    color: isSel ? Theme.accentSoft : (win.hoverArmed && rowArea.containsMouse ? Theme.hover : "transparent")
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(14)
                                        anchors.rightMargin: Theme.px(14)
                                        spacing: Theme.px(12)
                                        IconImage {
                                            visible: !!row.modelData.app
                                            implicitSize: 28
                                            source: row.modelData.app ? Quickshell.iconPath(row.modelData.app, "application-x-executable") : ""
                                        }
                                        ClippingRectangle {
                                            visible: !!row.modelData.thumb
                                            implicitWidth: Theme.px(56)
                                            implicitHeight: Theme.px(36)
                                            radius: Theme.px(6)
                                            color: Theme.hover
                                            Image {
                                                anchors.fill: parent
                                                source: Files.uriOf(row.modelData.thumb || "")
                                                sourceSize: Qt.size(112, 72)
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                cache: false
                                            }
                                        }
                                        Text {
                                            visible: row.modelData.kind === "emoji"
                                            Layout.preferredWidth: Theme.px(28)
                                            horizontalAlignment: Text.AlignHCenter
                                            text: row.modelData.glyph || ""
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(26) * Theme.fontScale
                                        }
                                        Icon {
                                            visible: !row.modelData.app && !row.modelData.thumb && row.modelData.kind !== "emoji"
                                            name: row.modelData.icon || ""
                                            size: Theme.px(20)
                                            color: row.modelData.kind === "ask" ? Theme.accent : Theme.text
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: row.modelData.title
                                            color: Theme.text
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(14) * Theme.fontScale
                                        }
                                        Text {
                                            Layout.maximumWidth: list.width * 0.55
                                            text: row.modelData.subtitle
                                            color: Theme.dim
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(11) * Theme.fontScale
                                        }
                                    }
                                    MouseArea {
                                        id: rowArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onEntered: if (win.hoverArmed) win.sel = section.base + row.index
                                        onClicked: win.activate(section.base + row.index, false)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Chronoa, one keystroke away, with a preview of what is selected
            // as tall as what it holds, not the whole column
            Glass {
                visible: !win.narrow && (win.q !== "" || (win.current && win.current.kind === "file"))
                Layout.preferredWidth: Theme.px(340)
                Layout.alignment: Qt.AlignTop
                Layout.preferredHeight: chronoaCol.implicitHeight + 36
                strong: true
                radius: Theme.radiusLarge
                MouseArea { anchors.fill: parent; objectName: "nav:pointer" }   // swallows clicks: they do not close it
                ColumnLayout {
                    id: chronoaCol
                    anchors.fill: parent
                    anchors.margins: Theme.px(18)
                    spacing: Theme.px(12)
                    RowLayout {
                        Icon { name: "face-smile-big"; size: Theme.px(20); color: Chronoa.color }
                        Text {
                            text: Tr.t("Chronoa")
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(15) * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text { text: "· " + Chronoa.label; color: Chronoa.color; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(220)
                        visible: win.lookText && lookFile.loaded
                        radius: Theme.px(12)
                        color: Theme.hover
                        clip: true
                        Text {
                            anchors.fill: parent
                            anchors.margins: Theme.px(10)
                            text: lookFile.loaded ? lookFile.text().split("\n").slice(0, 16).join("\n").slice(0, 1500) : ""
                            textFormat: Text.PlainText
                            color: Theme.dim
                            font.family: Theme.mono
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            wrapMode: Text.NoWrap
                        }
                    }
                    ClippingRectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(240)
                        visible: win.lookPdfImage !== ""
                        radius: Theme.px(12)
                        color: Theme.hover
                        Image {
                            anchors.fill: parent
                            source: Files.uriOf(win.lookPdfImage)
                            cache: false
                            fillMode: Image.PreserveAspectFit
                        }
                    }
                    ClippingRectangle {
                        id: imagePreview
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(180)
                        visible: win.current && win.current.kind === "file" && win.current.icon === "image-x-generic"
                        radius: Theme.px(12)
                        color: Theme.hover
                        Image {
                            anchors.fill: parent
                            source: imagePreview.visible ? Files.uriOf(win.current.path) : ""
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
                        font.pixelSize: Theme.px(14) * Theme.fontScale
                    }
                    Button {
                        text: Tr.t("Ask Chronoa")
                        kind: "primary"
                        onClicked: win.askChronoa()
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.px(4)
                        wrapMode: Text.Wrap
                        text: Tr.t("Start with  =  to calculate,  :  for emoji,  c  for the clipboard,  >  to run a command")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
            }
        }
    }
}
