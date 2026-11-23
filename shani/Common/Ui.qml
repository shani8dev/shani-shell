pragma Singleton
// Which shell surface is open, and on which screen. One overlay at a time:
// opening one closes the others, so Escape and click-outside have one meaning.
import Quickshell
import QtQuick

Singleton {
    id: root
    property bool launcher: false
    property string launcherQuery: ""
    property bool controlCenter: false
    property bool ring: false
    property bool layoutSwitcher: false
    property bool windowLayouts: false      // the window layout palette (Services/WindowLayouts)
    // which layout the switcher is showing on screen right now (its id), so a
    // check can ask what is displayed instead of counting keystrokes that a
    // niri config reload can swallow - see Modules/LayoutSwitcher
    property string layoutTrying: ""
    property int ringDepth: 0           // how many rings deep (for `state`)
    signal askRequested()               // the Island opens its question field
    property bool switcher: false
    property bool windowMenu: false
    property bool processes: false
    property bool logs: false                  // the Logs surface (Modules/Logs)
    property bool player: false  // the Player surface (Modules/Player): queue, seek, volume, lyrics
    property bool fonts: false  // the Fonts surface (Modules/Fonts): preview, size, install
    property string fontFile: ""  // a font file opened in Fonts (a .ttf from Files): shown, then installable
    property string mediaFrameSaved: ""     // the Media Player's last saved frame, for the tests
    property string fontFileDetails: ""  // its style, version, maker... (fc-query), for the tests
    property string fontFileFamily: ""   // what Fonts read from it ("!" when it is not a font it can read)
    property bool fontFileInstalled: false
    property bool characters: false        // the Characters panel (Modules/Characters)
    property bool voiceRecorder: false     // the Voice Recorder panel (Modules/VoiceRecorder)
    property bool pdfSigner: false            // the Signed panel (Modules/PdfSigner): sign / fill a PDF
    property bool diskUsage: false          // the DiskUsage panel (Modules/DiskUsage): disk treemap
    property bool disks: false              // the Disks app (Modules/Disks): erase, format, encrypt, health
    property bool files: false             // the Files surface (Modules/Files): the file manager
    property bool videoTrimmer: false              // the Video Trimmer (Modules/VideoTrimmer)
    property bool magnifier: false
    property bool viewer: false
    property bool pdfReader: false
    property bool calendar: false            // the Calendar surface (Modules/Calendar)
    property var calendarSelected: null      // selected day (Calendar surface)
    property bool maps: false                // the Maps surface (Modules/Maps)
    property var calendarView: ""           // calendar view mode (month/week)
    property real mapsZoom: 14              // maps zoom level
    property real mapsLat: 0                // maps centre (persisted place)
    property real mapsLon: 0
    property string mapsPlace: ""           // maps search result label
    property string mapsQuery: ""           // maps search box
    // what the Maps window reports (the tests read these) and asks it to do
    property var mapsView: ({})             // { lat, lon, zoom, tiles, route, distance, steps, error }
    signal mapsAsked(string what, string arg)
    property bool textEditor: false         // the TextEditor surface (Modules/TextEditor)
    property bool terminalApp: false          // the Terminal app (Modules/Terminal)
    property bool scanner: false           // the Scanner surface (Modules/Scanner)
    property bool passwordGenerator: false           // the Secrets surface (Modules/PasswordGenerator)
    property bool kundali: false          // the Kundali/Panchang surface (Modules/Kundali)
    property bool models: false            // the Models app (Modules/Models): AI model discovery/download
    property bool studio: false            // the Studio app (Modules/Studio): AI app builder
    property string kundaliDate: ""       // the day the calendar asked about (YYYY-MM-DD)
    property bool weather: false             // the Weather app (Modules/Weather)
    property bool tasks: false               // the Tasks app (Modules/Tasks)
    property bool contacts: false            // the Contacts app (Modules/Contacts)
    property bool photos: false              // the Photos app (Modules/Photos)
    property bool translate: false           // the Translate app (Modules/Translate)
    property bool converter: false           // the Converter app (Modules/Converter)
    property var converterFiles: []          // files handed to it (the Media Player's Convert…)
    property bool nearby: false              // the Nearby app (Modules/Nearby): LocalSend
    property bool authenticator: false       // the Authenticator app (Modules/Authenticator)
    property var passwordsItems: []          // for the tests: the saved passwords' labels
    property var passwordsKeys: []           // ...the GPG keys' names
    property string passwordsRevealed: ""    // ...the label of the one shown last
    property bool containers: false          // Containers (Modules/Containers: Pods, BoxBuddy - Distrobox and Podman)
    property var containersList: []          // for the tests: "box:name:state" / "name:state",
    property var containersImages: []
    property var containersApps: []          // ...a toolbox's apps listed,
    property string containersDone: ""       // ...the last long job's "<what>:ok",
    property string containersEntered: ""    // ...the toolbox opened in a terminal last,
    property string containersExported: ""   // ...the app put in the menu last
    property bool software: false            // Software (Modules/Software: GNOME Software, Warehouse, Gear Lever)
    property var softwareResults: []         // for the tests: the ids listed,
    property var softwareInstalled: []       // ...installed,
    property string softwareApp: ""          // ...the one whose page is open,
    property string softwareDone: ""         // ...the last job's "<id>:ok",
    property var softwareLeftovers: []
    property var softwareAppImages: []
    property string softwareRef: ""          // a .flatpakref opened with Software: installed when the window is up
    property bool passwords: false           // Passwords and Keys (Modules/Passwords: Seahorse parity)
    property bool clocks: false              // the Clocks app (Modules/Clocks): world, alarms, stopwatch, timer
    property string clocksTab: "world"
    property string textEditorOpenPath: ""   // a file a widget in Common hands to the Text Editor (which takes it and clears this)
    property bool notes: false               // the Notes surface (Modules/Notes): notebooks + wiki links
    property bool feeds: false               // the Feeds reader (Modules/Feeds)
    property bool mail: false                // the Mail reader (Modules/Mail)
    property bool servicesApp: false         // the Services app (Modules/Services): user units + cron
    property bool calls: false               // the Calls app (Modules/Calls): dial pad + history
    property bool messages: false            // the Messages app (Modules/Messages): the phone's texts
    property string callsNumber: ""          // the Calls app: the number the dial pad opens with
    property string messagesNumber: ""       // the Messages app: the conversation to open
    property string calculatorTab: "standard" // the Calculator tab (Modules/Calculator): standard | scientific | financial | programming | converter
    property string notesNotebook: ""         // the notes notebook filter (SidebarNotes): "" = all notebooks, else a notebook name
    property bool annotate: false                  // drawing on the screen
    property int annotateStrokes: 0
    property var printersSeen: []                  // Settings > Printers, for the tests
    property var appPermApps: []                   // Settings > App permissions: the Flatpaks listed, for the tests
    property string appPermShown: ""               // ...and the open one's permissions (JSON)
    property var printerOptions: []                // Settings > Printers: name:media:sides:colour, for the tests
    property var printersFound: []                 // Settings > Printers adding: what ippfind found, for the tests
    property string backupSummary: ""              // Settings > Backup, for the tests
    property bool backup: false                    // the Backup panel (Modules/Backup/BackupPanel)
    property string settingsCat: ""                // the settings category open
    property string settingsSection: ""            // a part of it to scroll to, once (openSettings)
    property bool settingsOpen: false              // the Settings window (Modules/Settings)
    // flash the control for a just-searched setting: the longest significant
    // word of its label is matched against every control's accessible name;
    // the page the search led to pulses its rings for a moment
    property string settingsHighlight: ""
    property string settingsFlash: ""
    Timer {
        id: settingsFlashClear
        interval: 3200
        onTriggered: { root.settingsHighlight = ""; root.settingsFlash = ""; }
    }
    function flashSetting(label) {
        const skip = new Set(["the", "and", "with", "from", "after", "until", "your", "every", "when", "mode", "that", "this", "will"]);
        let best = "";
        for (const w of String(label || "").toLowerCase().split(/[^a-z]+/))
            if (w.length >= 4 && !skip.has(w) && w.length > best.length)
                best = w;
        root.settingsHighlight = label || "";
        root.settingsFlash = best;
        settingsFlashClear.restart();
    }
    property string dockMenu: ""                   // an app whose dock menu the tests opened
    // the file chooser (Services/FilePicker): the shell sets it, so a widget
    // in Common can ask for a file without reaching into the services
    property var filePicker: null
    // the window in front, minimised (Services/Niri's way: niri has no minimise);
    // the shell sets it, so a window in Common can ask without reaching into the services
    property var minimiser: null
    function minimiseFocused() { if (minimiser) minimiser(); }
    // Shell app windows (Common/AppWindow) register by desktop-entry id so a
    // stuck one can be closed or minimised by its own id. Niri.forceCloseFocused
    // uses close: SIGKILL would take down every shell window (one shared pid).
    // shell.qml owns the zero-arg `minimiser` closure, so an id cannot be routed
    // through it without editing shell.qml - these per-window actions are the fix.
    property var appWindowActions: ({})
    function registerAppWindow(id, actions) {
        if (!id) return;
        const m = Object.assign({}, appWindowActions);
        m[id] = actions;
        appWindowActions = m;
    }
    function unregisterAppWindow(id) {
        if (!id || !appWindowActions[id]) return;
        const m = Object.assign({}, appWindowActions);
        delete m[id];
        appWindowActions = m;
    }
    function closeAppWindow(id) {
        const a = appWindowActions[id];
        if (a && typeof a.close === "function") { a.close(); return true; }
        return false;
    }
    // minimise the window that registered as `id`, never the focused one
    function minimise(id) {
        const a = appWindowActions[id];
        if (a && typeof a.minimise === "function") { a.minimise(); return true; }
        return false;
    }
    property bool chargingPreview: false           // the charging animation, once (the tests, the showcase)
    // section: an objectName in the page to scroll to ("section:colours")
    function openSettings(cat, section) {
        closeAll();
        tvHome = false;
        settingsCat = cat || settingsCat || "personal";
        settingsSection = section || "";
        settingsOpen = true;
    }
    property int faceRev: 0                        // bumped when ~/.face changes
    property int shortcutsListed: 0                // binds Settings > Keyboard shortcuts read from niri
    property int controllersListed: 0              // game controllers Settings lists
    property bool dockFocus: false                 // the dock has the keyboard (IPC focusDock, a controller)
    property bool desktopMenu: false               // open the desktop menu from the keyboard (IPC desktopMenu)
    property bool barFocus: false                  // the bar has the keyboard (IPC focusBar)
    property string osdLabel: ""                   // the OSD's last words (the tests)
    property bool promptKeyboard: false            // a password prompt's screen keyboard is up (lock, polkit)
    // a TV remote / keyboard activated the last control (Common/KeyFocus), so
    // what it opens is driven by keys too - the screen keyboard then types
    // from the remote (Services/Osk remote mode)
    property bool keysActivated: false
    // the focused screen's kind and size (Services/FormFactor): Theme.ui reads it
    property string formFactor: "computer"
    property real uiScale: 1.0
    // the TV home (Modules/TvHome) on a TV screen: shown at start and on Home,
    // hidden by whatever it opens; tvSelected is its highlighted card (the tests)
    property bool tvHome: true
    property string tvSelected: ""
    // the quick panel over a running game (Modules/QuickPanel; the ⋯ button)
    property bool quickPanel: false
    // a text field of the shell has the keys (Common/TextField, the launcher's
    // search): on a tablet or a phone the screen keyboard comes up for it
    property var textInput: null
    readonly property bool textFocus: textInput !== null && textInput.activeFocus && textInput.visible && !textInput.readOnly
    // when keys (or a controller) last moved the focus (Common/KeyFocus), and whether the
    // field that has it now was reached that way - not focused by a surface on opening
    property real keyMovedAt: 0
    property bool textByKeys: false
    function trackTextInput(input, focused) {
        if (focused) {
            textByKeys = Date.now() - keyMovedAt < 600;
            textInput = input;
        }
        else if (textInput === input)
            textInput = null;
    }
    property bool settingsCompact: false           // Settings is one pane at a time (the tests)
    property bool settingsShowingPage: true
    property bool lockBusy: false                  // the lock screen is checking a password (the tests)
    // the whiteboard (Modules/Whiteboard; the classroom board's, anyone's)
    property bool whiteboard: false
    property int whiteboardStrokes: 0
    property int whiteboardPage: 0
    property string whiteboardSaved: ""
    property string quickSelected: ""
    property string launcherSelected: ""      // the highlighted result (the tests)
    property int windowMenuSel: 0             // the window menu's highlighted row (the tests)
    property bool launcherSearchBar: false
    property string launcherText: ""          // what the launcher's search holds now (the tests)    // the remote's cursor is on the launcher's search bar
    signal typingRequested()            // OK on an empty field: the remote's keyboard
    property string navFocus: ""                   // the name of what keyboard/controller focus is on (Common/KeyFocus)
    property bool padTestRunning: false            // a controller's "Test the buttons" reader is running
    property string padTestLast: ""                // the last button it saw pressed
    property int u2fRegistered: 0                  // security keys registered (Settings > Your account)
    property bool tour: false
    property int trashCount: 0                     // the dock's trash tile reports it (for the tests)                      // the tour, opened again by hand
    property string modemDialog: ""                // "pin" | "sms" (ModemDialog)
    property string smsTo: ""                      // the number a reply goes to
    // Shani Link Phone / Messages (opened via Services/Phone; the external
    // shani-link-app window, not a shell panel): which page the shell last
    // opened and the number its dialer/messages composer was prefilled with.
    property string phoneNumber: ""   // the number the dial pad / Messages composer opened with
    // the web search chosen in Settings > Search (the launcher, Lens)
    readonly property var webSearches: ({
        duckduckgo: ["DuckDuckGo", "https://duckduckgo.com/?q="], google: ["Google", "https://www.google.com/search?q="],
        startpage: ["Startpage", "https://www.startpage.com/do/search?q="], bing: ["Bing", "https://www.bing.com/search?q="],
        ecosia: ["Ecosia", "https://www.ecosia.org/search?q="]
    })
    function webSearchName() { return (webSearches[Settings.data.webSearch] || webSearches.duckduckgo)[0]; }
    function webSearchUrl(q) { return (webSearches[Settings.data.webSearch] || webSearches.duckduckgo)[1] + encodeURIComponent(q); }
    property int flashes: 0                        // flash alerts shown, for the tests
    property string lastFlash: ""                  // the notification that flashed last (its summary)
    property point ringAt: Qt.point(-1, -1)        // where the Ring opens; -1: at the pointer
    function openRingAt(x, y) {
        closeAll();
        ringAt = Qt.point(x, y);
        ring = true;
    }
    property real windowMenuX: 0
    signal windowMenuActionRequested(string id)
    property var windowMenuLabels: []                 // the window menu's rows, as shown (the tests read them)
    signal windowMenuAppRequested(int index)          // open one of the app's menus (IPC, the tests)
    signal switcherRequested(bool back) // Alt+Tab / Alt+Shift+Tab
    property string expanded: ""        // control-center section: wifi | bluetooth | audio | vpn | power
    property var screen: Quickshell.screens[0]
    property string topResult: ""
    property int launcherFiles: 0
    property int launcherMeaning: 0
    property var liveWallpaperPlaying: ({})        // output -> playing (the tests read it)                // files Chronoa found by meaning (the tests read it)                  // how many file results the launcher shows (the tests read it)
    // read-outs for `state` (tests and scripts)
    property string islandActivity: ""
    property bool islandBusy: false               // the Island is asking, working or waiting on an approval (brings a hidden bar back)
    property var launcherSections: []
    property var tilesShown: []       // the launcher's first answer (shown in `state`)

    // files dropped on an app (the dock): its desktop file opens them, as a file
    // manager's "Open with" does - gio launch fills its %f/%u from the arguments
    function openFilesWith(appId, files) {
        if (!appId || !files.length)
            return;
        Quickshell.execDetached(["sh", "-c", 'id=$1; shift; IFS=:; for d in "${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do '
            + 'f="$d/applications/$id.desktop"; [ -f "$f" ] && exec gio launch "$f" "$@"; done; exit 1', "sh", appId].concat(files));
    }
    // closeApps() has run: the apps whose state is a service's (the calculator,
    // the viewers, the camera) close on it too - shell.qml listens
    signal closedApps()
    // The shell's apps are windows (Common/AppWindow): they stay open while the
    // launcher, the sidebar or another app is used, so closeAll() leaves them.
    // closeApps() closes them too - the "back to an empty desktop" a script asks for.
    // the apps the sidebar, the desktop widgets, the bar and the Island hand over to:
    // one place for each thing (a timer is Clocks', the weather is Weather's)
    function openClocks(tab) { closeAll(); if (tab) clocksTab = tab; clocks = true; }
    function openWeather() { closeAll(); weather = true; }
    function openScreenTime() { openSettings("screentime"); }
    function openNotes() { closeAll(); notes = true; }
    function openContacts() { closeAll(); Contacts.refresh(); contacts = true; }
    function openCalls() { closeAll(); calls = true; }
    function openMessages() { closeAll(); messages = true; }
    function closeApps() {
        converter = false;
        nearby = false;
        authenticator = false;
        passwords = false;
        software = false;
        containers = false;
        tasks = false;
        contacts = false;
        photos = false;
        translate = false;
        weather = false;
        clocks = false;
        processes = false;
        textEditor = false;
        logs = false;
        fonts = false;
        characters = false;
        voiceRecorder = false;
        pdfSigner = false;
        diskUsage = false;
        disks = false;
        files = false;
        videoTrimmer = false;
        calendar = false;
        maps = false;
        terminalApp = false;
        scanner = false;
        passwordGenerator = false;
        kundali = false;
        models = false;
        studio = false;
        notes = false;
        mail = false;
        feeds = false;
        calls = false;
        messages = false;
        backup = false;
        closedApps();
    }
    function closeAll() {
        quickPanel = false;
        dockMenu = "";
        launcher = false;
        ring = false;
        switcher = false;
        windowMenu = false;
        player = false;
        magnifier = false;
        annotate = false;
        controlCenter = false;
        layoutSwitcher = false;
        windowLayouts = false;
        expanded = "";
        dockFocus = false;
        barFocus = false;
    }
    function toggleLauncher(query) {
        const was = launcher;
        closeAll();
        // the query first: opening the launcher reads it at once, and set
        // after, every launch showed the previous query's answers
        launcherQuery = query || "";
        launcher = !was;
        if (launcher && Settings.data.launcherOpens < 5)
            Settings.data.launcherOpens++;
    }
    function askIsland() {
        closeAll();
        askRequested();
    }
    function toggleRing() {
        const was = ring;
        closeAll();
        ring = !was;
    }
    function toggleLayoutSwitcher() {
        const was = layoutSwitcher;
        closeAll();
        layoutSwitcher = !was;
    }
    function toggleWindowLayouts() {
        const was = windowLayouts;
        closeAll();
        windowLayouts = !was;
    }
    function toggleControlCenter(section) {
        const was = controlCenter && (section === undefined || expanded === section);
        closeAll();
        controlCenter = !was;
        if (controlCenter && section)
            expanded = section;
    }
    // keyboard and controller: focus the first thing a surface offers, once it is shown
    // (Common/KeyFocus items are the surface's tab chain, in reading order)
    function focusFirst(root) {
        Qt.callLater(() => {
            const it = root ? root.nextItemInFocusChain(true) : null;
            if (it)
                it.forceActiveFocus(Qt.TabFocusReason);
        });
    }

    // A controller's LB / RB in a shell surface: on to the next (previous) section, as
    // Tab would - but moved here, not typed, so a document being edited never gets a
    // tab character. From a Common/KeyFocus its region's jump; from anything else (a
    // field, a document) the next control. False: no shell window has the keys.
    // a few lines to type in a panel (a note, a text to translate): Down on its last
    // line and Up on its first go on to the next / previous control, as a one-line
    // field's do - else the arrows and a d-pad walking a panel would stop there
    function leaveAtEdge(edit, forward) {
        const t = edit.text, c = edit.cursorPosition;
        const edge = forward ? t.indexOf("\n", c) < 0 : t.lastIndexOf("\n", c - 1) < 0;
        if (!edge) return false;
        const n = edit.nextItemInFocusChain(forward);
        if (!n || n === edit) return false;
        keyMovedAt = Date.now();
        n.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        return true;
    }
    function navJump(forward) {
        for (const w of navWindows) {
            let it = null;
            try { if (!w.active) continue; it = w.activeFocusItem; } catch (e) { continue; }
            if (!it) continue;
            keyMovedAt = Date.now();
            if (typeof it.jumpRegion === "function") { it.jumpRegion(forward); return true; }
            const n = it.nextItemInFocusChain(forward);
            if (n && n !== it) n.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
            return true;
        }
        return false;
    }

    // ---- reach with keys and a controller, checked (the tests: dev/shell-parts/pad-reach.sh) ----
    // The shell's app windows by name (Common/AppWindow registers its content)
    property var navRoots: ({})
    // What a click reaches that keys do not: every MouseArea taking a left click and
    // every TapHandler, shown and enabled, with nothing focusable around it - not on
    // itself, its parent or an ancestor up to three up, nor inside its parent (where
    // Common/KeyFocus sits). Pointer-only by nature (a drag handle with keys of its
    // own elsewhere, a backdrop that closes on a click outside, which Escape does):
    // objectName "nav:pointer". Each found: [the names around it, its types].
    function navAudit(root) {
        const out = [];
        const isMouse = o => String(o).indexOf("QQuickMouseArea") === 0;
        const isTap = o => String(o).indexOf("QQuickTapHandler") === 0;
        // in the tab chain (a TextInput is not by default: then the d-pad passes it by)
        const focusable = it => it && it.activeFocusOnTab === true;
        function inside(it, depth) {
            if (!it || depth > 4 || !it.visible) return false;
            if (focusable(it)) return true;
            const ch = it.children || [];
            for (let i = 0; i < ch.length; i++)
                if (inside(ch[i], depth + 1)) return true;
            return false;
        }
        // a part of a control that keys reach as a whole (a tile's chevron: its Menu
        // key): a focusable child covering all of the control two up
        function wholeFocus(c) {
            const ch = c ? (c.children || []) : [];
            for (let i = 0; i < ch.length; i++)
                if (focusable(ch[i]) && ch[i].width >= c.width - 1 && ch[i].height >= c.height - 1) return true;
            return false;
        }
        function reachable(it) {
            for (let p = it, i = 0; p && i < 4; p = p.parent, i++)
                if (focusable(p)) return true;
            return inside(it.parent, 0) || (it.parent && wholeFocus(it.parent.parent));
        }
        function shown(it) {
            for (let p = it; p; p = p.parent)
                if (!p.visible || p.opacity === 0 || p.enabled === false) return false;
            return it.width > 2 && it.height > 2;
        }
        function about(it) {
            const names = [], types = [];
            for (let p = it, i = 0; p && i < 9; p = p.parent, i++) {
                const n = (p.Accessible && p.Accessible.name) || p.text || p.tip || p.label || p.name || "";
                if (typeof n === "string" && n && names.indexOf(n) < 0) names.push(n);
                types.push(String(p).replace(/\(0x[0-9a-f]+.*$/, "").replace(/_QML(TYPE)?_\d+$/, ""));
            }
            return names.slice(0, 2).join(" / ") + "  [" + types.join(" < ") + "]";
        }
        function walk(it) {
            if (!it || !it.visible) return;
            // "nav:pointer": pointer by nature; "nav:keys": the surface moves its own highlight with keys
            if (String(it.objectName) === "nav:pointer" || String(it.objectName) === "nav:keys") return;
            if (isMouse(it) && it.enabled && (it.acceptedButtons & Qt.LeftButton) && shown(it) && !reachable(it))
                out.push(about(it));
            // a field to type in that Tab and the d-pad pass by
            const field = String(it).indexOf("QQuickTextInput") === 0 || String(it).indexOf("QQuickTextEdit") === 0;
            if (field && !it.readOnly && it.enabled && shown(it) && !focusable(it))
                out.push("(field) " + about(it));
            const data = it.data || [];
            for (let i = 0; i < data.length; i++) {
                const d = data[i];
                if (isTap(d) && d.enabled && shown(it) && !reachable(it))
                    out.push(about(it));
            }
            const ch = it.children || [];
            for (let i = 0; i < ch.length; i++) walk(ch[i]);
        }
        walk(root);
        return out;
    }
    // ...and in every surface of the shell that is showing. QML cannot list the
    // shell's windows, so each makes itself known: every Common/KeyFocus says which
    // window it is in, and a surface without one has a Common/NavWindow.
    property var navWindows: []                    // plain list: no bindings follow it
    function navSeen(w) {
        if (w && navWindows.indexOf(w) < 0)
            navWindows.push(w);
    }
    property int navAuditWindows: 0          // how many showing windows the last navAuditAll looked into
    function navAuditAll() {
        navAuditWindows = 0;
        const out = [], alive = [];
        const kind = o => String(o).replace(/\(0x[0-9a-f]+.*$/, "").replace(/_QML(TYPE)?_\d+$/, "");
        for (const w of navWindows) {
            let item = null, shown = false;
            try { item = w.contentItem; shown = w.visible; } catch (e) { continue; }    // gone (its loader let it go)
            if (!item) continue;
            alive.push(w);
            if (!shown) continue;
            navAuditWindows++;
            // the window named by what it holds (Quickshell's windows all read "ProxiedWindow")
            let top = item;                // Quickshell's own content item first: what it holds
            while (top.children && top.children.length === 1 && String(top.children[0]).indexOf("ProxyWindowContentItem") === 0) top = top.children[0];
            if (top.children && top.children.length && String(top.children[0]).indexOf("ProxyWindowContentItem") === 0) top = top.children[0];
            const ch = top.children || [];
            const what = [];
            for (let i = 0; i < ch.length && what.length < 3; i++) what.push(kind(ch[i]));
            for (const f of navAudit(item)) out.push("{" + what.join(",") + "}: " + f);
        }
        // the shell's app windows, by name (Common/AppWindow)
        for (const name in navRoots)
            for (const f of navAudit(navRoots[name])) out.push(name + ": " + f);
        navWindows = alive;
        const once = [];
        for (const f of out) { const k = f.slice(f.indexOf(": ") + 2); if (!once.some(x => x.slice(x.indexOf(": ") + 2) === k)) once.push(f); }
        return once;
    }
}
