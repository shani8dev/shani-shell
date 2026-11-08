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
    // which layout the switcher is showing on screen right now (its id), so a
    // check can ask what is displayed instead of counting keystrokes that a
    // niri config reload can swallow - see Modules/LayoutSwitcher
    property string layoutTrying: ""
    property int ringDepth: 0           // how many rings deep (for `state`)
    signal askRequested()               // the Island opens its question field
    property bool switcher: false
    property bool windowMenu: false
    property bool processes: false
    property bool player: false  // the Player surface (Modules/Player): queue, seek, volume, lyrics
    property bool fonts: false  // the Fonts surface (Modules/Fonts): preview, size, install
    property bool magnifier: false
    property bool calendar: false            // the Calendar surface (Modules/Calendar)
    property bool annotate: false                  // drawing on the screen
    property int annotateStrokes: 0
    property var printersSeen: []                  // Settings > Printers, for the tests
    property string backupSummary: ""              // Settings > Backup, for the tests
    property string settingsCat: ""                // the settings category open
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
    property bool chargingPreview: false           // the charging animation, once (the tests, the showcase)
    function openSettings(cat) {
        closeAll();
        settingsCat = cat || settingsCat || "personal";
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
    property string navFocus: ""                   // the name of what keyboard/controller focus is on (Common/KeyFocus)
    property bool padTestRunning: false            // a controller's "Test the buttons" reader is running
    property string padTestLast: ""                // the last button it saw pressed
    property int u2fRegistered: 0                  // security keys registered (Settings > Your account)
    property bool tour: false
    property int trashCount: 0                     // the dock's trash tile reports it (for the tests)                      // the tour, opened again by hand
    property string modemDialog: ""                // "pin" | "sms" (ModemDialog)
    property string smsTo: ""                      // the number a reply goes to
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
    signal switcherRequested(bool back) // Alt+Tab / Alt+Shift+Tab
    property string expanded: ""        // control-center section: wifi | bluetooth | audio | vpn | power
    property var screen: Quickshell.screens[0]
    property string topResult: ""
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
    function closeAll() {
        dockMenu = "";
        launcher = false;
        ring = false;
        switcher = false;
        windowMenu = false;
        processes = false;
        player = false;
        fonts = false;
        magnifier = false;
        annotate = false;
        controlCenter = false;
        calendar = false;
        layoutSwitcher = false;
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
}
