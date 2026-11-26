// The Files surface: the shell's file manager. The folder on screen, the
// places on the left, a search box, and the files in the middle as a grid of
// tiles or as a list of rows. Click to choose, Ctrl-click for more, Shift-click
// for a range, Enter or a double click to open (a folder is walked into, a
// file is opened with the app it belongs to), F2 to rename, Delete to move to
// the trash, Backspace to go up, Escape to close.
//
// Split view: Ctrl+Alt+N opens a second pane; files can be
// copied or moved between panes with buttons in the toolbar.
//
// The listing comes from Services/Files.qml and bridge/files.py: the folder is
// watched, so a file made or removed elsewhere shows up here too. Nothing is
// deleted by the file manager - the trash is the desktop trash, where it can
// be put back.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/NetToolsOpen.js" as NetToolsOpen
import qs.Modules.Files
import "../../Common/FilePaths.js" as FilePaths

AppWindow {
    id: win
    property var openWithPaths: []
    appName: "Files"
    sidePane: placesPane
    // on a phone the toolbar is the app's one bar (docs/DESIGN.md): no window
    // header above it - the phone's own bar has back, home and the app switcher
    header: !compact
    Connections { target: Files; function onPathChanged() { placesPane.open = false; } }
    // a phone shows one folder at a time: a split pane opened on a wide window
    // closes when the window narrows, and the toggle is not offered there
    onCompactChanged: { if (win.compact && Files.splitActive) Files.toggleSplit(); }
    visible: Ui.files
    onGone: Files.hide()
    margins: 0
    implicitWidth: Theme.px(1100)
    implicitHeight: Theme.px(760)
    shortcutSearch: searchBox   // Ctrl+F focuses this folder's search
    shortcutRefresh: win.refresh  // Ctrl+R reloads the folder
    function refresh() { dir.reload(); }
    // the refresh action lives in AppWindow's header tools, not a second toolbar
    tools: [
        IconButton { icon: "view-refresh"; size: Theme.px(30); tip: Tr.t("Refresh (F5)"); onClicked: win.refresh() }
    ]

    // the keys the surface answers, wherever the focus is not on a control
    Item {
        id: keys
        anchors.fill: parent
        focus: win.visible
        // Escape goes back a folder first, and out of the surface at the top
        Keys.onEscapePressed: {
            if (win.filterShown) { win.toggleFilters(); return; }
            if (renameBox.visible || newFolderBox.visible || batchBox.visible || Files.props || Files.comparison || Files.syncAsk || Files.usb || Files.unlockFor || Files.locker || (Files.cloudAsk && !Files.cloudAdding) || win.serveAsk !== "" || Files.conflictAsk || Files.copyTo || Files.historyShown || Files.deleteAsk.length) {
                renameBox.visible = false;
                newFolderBox.visible = false;
                batchBox.visible = false;
                Files.props = null;
                Files.comparison = null;
                Files.syncCancel();
                if (!Files.usbBusy) Files.usb = null;
                Files.unlockFor = null;
                Files.locker = null;
                if (!Files.cloudAdding) Files.cloudAsk = false;
                win.serveAsk = "";
                if (Files.conflictAsk) Files.answerConflict("");
                Files.copyTo = null;
                Files.historyShown = false;
                Files.deleteAsk = [];
                return;
            }
            if (Files.splitActive) {
                Files.toggleSplit();
                return;
            }
            // Escape first lets go of a selection, then walks up (or closes)
            if (Files.selected.length) {
                Files.clearSelection();
                return;
            }
            if (Files.canUp)
                Files.up();
            else
                win.requestClose();
        }
        Keys.onPressed: event => {
            const control = (event.modifiers & Qt.ControlModifier) !== 0;
            const alt = (event.modifiers & Qt.AltModifier) !== 0;
            if (control && alt && event.key === Qt.Key_N) {
                Files.toggleSplit();
                event.accepted = true;
                return;
            }
            if (control && event.key === Qt.Key_L) {
                pathBox.visible = true;
                pathBox.text = Files.path;
                pathBox.forceActiveFocus();
                pathBox.selectAll();
                event.accepted = true;
                return;
            }
            // Ctrl+H: show or hide dotfiles (Nautilus / Dolphin / Finder)
            if (control && !alt && event.key === Qt.Key_H) {
                Files.toggleHidden();
                event.accepted = true;
                return;
            }
            // Ctrl+Shift+N: a new folder here (Nautilus / Finder)
            if (control && !alt && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_N) {
                win.openNewFolder();
                event.accepted = true;
                return;
            }
            if (control && event.key === Qt.Key_A) {
                Files.selectAll();
                event.accepted = true;
                return;
            }
            // Ctrl+M: Create Link to the one selected file or folder
            if (control && event.key === Qt.Key_M && Files.selected.length === 1) {
                win.askSymlink(Files.selected[0]);
                event.accepted = true;
                return;
            }
            // Ctrl+Shift+I: the selection turned over
            if (control && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_I) {
                Files.invertSelection();
                event.accepted = true;
                return;
            }
            // Ctrl+plus / minus / 0: bigger, smaller, as it was
            if (control && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.key === Qt.Key_Minus || event.key === Qt.Key_0)) {
                Files.setZoom(event.key === Qt.Key_0 ? 1 : Files.zoom + (event.key === Qt.Key_Minus ? -0.2 : 0.2));
                event.accepted = true;
                return;
            }
            // a keyboard shortcut sheet: Ctrl+/ (or ? like a browser's help)
            if ((control && event.key === Qt.Key_Slash) || (!control && !alt && event.key === Qt.Key_Question)) {
                win.toggleShortcuts();
                event.accepted = true;
                return;
            }
            // Ctrl+D bookmarks the folder on screen; Ctrl+Shift+T brings a closed tab back
            if (control && !alt && event.key === Qt.Key_D) {
                Files.toggleBookmark();
                event.accepted = true;
                return;
            }
            if (control && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_T) {
                Files.reopenClosedTab();
                event.accepted = true;
                return;
            }
            // Ctrl+Shift+Y: every file of the same kind as the one under the cursor
            if (control && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Y) {
                Files.note = Tr.t("%1 selected", Files.selectByType());
                event.accepted = true;
                return;
            }
            // Ctrl+1…9 jumps to a tab, the way a browser does (Alt+1 in Dolphin)
            if (control && !alt && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                const n = event.key - Qt.Key_1;
                if (n < Files.tabPaths.length) { Files.switchTab(n); event.accepted = true; return; }
            }
            // tabs: Ctrl+T a new one here, Ctrl+Shift+W this one closed (Ctrl+W closes the window in AppWindow), Ctrl+Tab / Ctrl+Shift+Tab the next / the last
            if (control && event.key === Qt.Key_T) { Files.newTab(Files.path); event.accepted = true; return; }
            if (control && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_W && Files.tabs.length > 1) { Files.closeTab(); event.accepted = true; return; }
            if (control && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && Files.tabs.length > 1) {
                const n = Files.tabs.length, back = event.key === Qt.Key_Backtab;
                Files.switchTab((Files.tabIndex + (back ? n - 1 : 1)) % n);
                event.accepted = true;
                return;
            }
            // type to find: the first file whose name starts with what was typed
            // (a pause of a second starts again); a space only once a name is begun
            // (Delete's text is \x7f, a "character" too: it stays Delete)
            if (!control && !alt && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                    && (event.key !== Qt.Key_Space || win.typed !== "")) {
                win.typed += event.text.toLowerCase();
                typedTimer.restart();
                const hit = Files._paths.find(p => Files.baseName(p).toLowerCase().startsWith(win.typed));
                if (hit) {
                    Files.select(hit, "single");
                    const i = Files._paths.indexOf(hit);
                    if (grid.visible) grid.positionViewAtIndex(i, GridView.Contain); else list.positionViewAtIndex(i, ListView.Contain);
                }
                event.accepted = true;
                return;
            }
            // the file clipboard, undo, Properties, search
            if (control && !alt && (event.key === Qt.Key_C || event.key === Qt.Key_X) && Files.selected.length > 0) {
                Files.toClipboard(event.key === Qt.Key_X ? "cut" : "copy", []);
                event.accepted = true;
                return;
            }
            if (control && !alt && event.key === Qt.Key_V) {
                Files.pasteHere(Files.path);
                event.accepted = true;
                return;
            }
            if (control && !alt && ((event.key === Qt.Key_Z && (event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Y)) {
                Files.redo();
                event.accepted = true;
                return;
            }
            if (control && !alt && event.key === Qt.Key_Z) {
                Files.undo();
                event.accepted = true;
                return;
            }
            // Ctrl+Shift+F: the finer filter popover, next to the type chips
            if (control && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_F) {
                win.toggleFilters();
                event.accepted = true;
                return;
            }
            // plain Ctrl+F is AppWindow's: shortcutSearch focuses searchBox
            if (alt && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && Files.selected.length > 0) {
                Files.showProps([]);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_F5) {
                win.refresh();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Delete && Files.selected.length > 0 && (event.modifiers & Qt.ShiftModifier) && !Files.isTrash) {
                Files.deleteAsk = Files.selected.slice();         // asked first: no trash to come back from
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Delete && Files.selected.length > 0) {
                Files.trashEntries([]);
                event.accepted = true;
                return;
            }
            // Space: Quick Look at the file the keyboard is on (or the one chosen),
            // with the folder's files to walk with Left and Right
            if (event.key === Qt.Key_Space && !control && !alt) {
                const at = Files.current || (Files.selected.length ? Files.selected[0] : "");
                if (at) {
                    QuickLook.open(at, Files._paths);
                    event.accepted = true;
                    return;
                }
            }
            // plain F2 only: the batch shortcut below owns Ctrl+Shift+F2
            if (event.key === Qt.Key_F2 && !control && !(event.modifiers & Qt.ShiftModifier) && Files.selected.length === 1) {
                win.beginRename(Files.selected[0]);
                event.accepted = true;
                return;
            }
            // CoreFM / Nautilus muscle memory: keyboard users need not reach for the mouse
            if (event.key === Qt.Key_F4) {
                Files.openTerminal(Files.path);
                event.accepted = true;
                return;
            }
            if (control && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_F2 && Files.selected.length) {
                win.beginBatchRename(Files.selected.slice());
                event.accepted = true;
                return;
            }
            if (control && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_V) {
                Files.setViewMode(Files.viewMode === "grid" ? "list" : "grid");
                event.accepted = true;
                return;
            }
            if (control && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_S) {
                const keys = ["name", "size", "mtime"];
                Files.setSort(keys[(keys.indexOf(Files.sortKey) + 1) % keys.length]);
                event.accepted = true;
                return;
            }
            if (control && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && Files.selected.length) {
                win.openWithPaths = Files.selected.slice();
                event.accepted = true;
                return;
            }
            if (alt && event.key === Qt.Key_Left) {
                Files.back();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Backspace && !win.typed) {
                Files.up();
                event.accepted = true;
                return;
            }
        }
    }

    // Ctrl+Space: take the keyboard-focused file in or out of the selection.
    // Plain Space stays Quick Look (the delegates' KeyFocus handles that).
    Shortcut {
        sequence: "Ctrl+Space"
        onActivated: { if (Files.current) Files.select(Files.current, "toggle"); }
    }

    // Shift+arrow: extend from the anchor to where focus lands. The shared
    // KeyFocus does not pass arrow modifiers on, so the range runs through this
    // window instead (moving focus first, then selecting the focused path).
    function extendSelection(key) {
        const kf = win.activeFocusItem;
        if (!kf || kf.peekable !== true || typeof kf.move !== "function")
            return;
        const n = key === Qt.Key_Up ? -(kf.columns || 1)
                : key === Qt.Key_Down ? (kf.columns || 1)
                : key === Qt.Key_Left ? -1 : 1;
        const anchor = Files.current;
        kf.move(n);                       // the newly focused delegate sets Files.current
        const focused = Files.current;
        if (focused === anchor || Files.entryPaths().indexOf(focused) < 0)
            return;
        Files.current = anchor;           // select() ranges from where the keys were
        Files.select(focused, "range");
    }
    Shortcut {
        sequences: ["Shift+Left"]
        enabled: !!(win.activeFocusItem && win.activeFocusItem.peekable === true)
        onActivated: win.extendSelection(Qt.Key_Left)
    }
    Shortcut {
        sequences: ["Shift+Right"]
        enabled: !!(win.activeFocusItem && win.activeFocusItem.peekable === true)
        onActivated: win.extendSelection(Qt.Key_Right)
    }
    Shortcut {
        sequences: ["Shift+Up"]
        enabled: !!(win.activeFocusItem && win.activeFocusItem.peekable === true)
        onActivated: win.extendSelection(Qt.Key_Up)
    }
    Shortcut {
        sequences: ["Shift+Down"]
        enabled: !!(win.activeFocusItem && win.activeFocusItem.peekable === true)
        onActivated: win.extendSelection(Qt.Key_Down)
    }

    onVisibleChanged: {
        if (!visible)
            return;
        Files.loadPlaces();
        if (Files.path === "")
            Files.open(Files.home);
    }

    // ---- the folder being shown ------------------------------------------------
    // the search box's words, settled (a new search per keystroke would walk the tree each time)
    property string deepWords: ""
    Timer {
        id: deepTimer
        interval: 400
        onTriggered: {
            const words = searchBox.text.trim();
            win.deepWords = words.length >= 2 && Files.searchDeep && Files.path.startsWith("/") ? words : "";
            Files.rememberSearch(words);
        }
    }
    readonly property bool searchingDeep: Files.searchDeep && deepWords !== "" && Files.path.startsWith("/")

    // the chips under the search box: extension sets go to FileDirectory.filters
    // (which always keeps folders); "Folders" also needs a surface-side filter.
    readonly property var searchCategories: [
        { id: "all", label: Tr.t("All"), filters: [], foldersOnly: false },
        { id: "folders", label: Tr.t("Folders"), filters: [], foldersOnly: true },
        { id: "images", label: Tr.t("Images"), filters: ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif", "heic", "tif", "tiff", "ico"], foldersOnly: false },
        { id: "media", label: Tr.t("Media"), filters: ["mp3", "flac", "wav", "ogg", "m4a", "aac", "opus", "mp4", "mkv", "webm", "mov", "avi", "m4v", "flv", "wmv"], foldersOnly: false },
        { id: "documents", label: Tr.t("Documents"), filters: ["pdf", "doc", "docx", "odt", "rtf", "xls", "xlsx", "ods", "ppt", "pptx", "odp", "epub", "djvu"], foldersOnly: false },
        { id: "text", label: Tr.t("Text"), filters: ["txt", "md", "json", "yaml", "yml", "toml", "xml", "csv", "log", "ini", "conf", "sh", "py", "js", "ts", "qml", "c", "cpp", "h", "java", "go", "rs", "html", "css"], foldersOnly: false }
    ]
    function applyCategory(id) {
        const cat = win.searchCategories.find(c => c.id === id) || win.searchCategories[0];
        Files.setSearchCategory(cat.id, cat.filters, cat.foldersOnly);
        win.sync();                  // folders-only hides files without a backend filter
        win.syncSplit();
    }
    Component.onCompleted: win.applyCategory(Files.activeCategory)

    // A share path (smb/nfs) or a selected .desktop's URL carries a host worth
    // checking. the Ui singleton source file/shell.qml are out of scope, so there is no handoff flag:
    // write a clipboard marker and set Ui.netTools, the flag shell.qml's
    // netToolsOpen() sets, and NetTools consumes the marker on open.
    function openNetTools(host) { NetToolsOpen.open(host, Quickshell, Ui); }
    function hostFromUri(raw) {
        let s = String(raw || "").trim();
        s = s.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "");
        // drop userinfo first: sftp://user@host/share must hand `host` to
        // Network Tools, not the user name (`user:pw` for https basic auth)
        s = s.replace(/^[^@]*@/, "");
        s = s.split(/[/?#@]/)[0];
        s = s.replace(/:\d+$/, "");
        return s;
    }
    function isNetHost(s) {
        return /^[A-Za-z0-9][A-Za-z0-9.-]*$/.test(String(s || "")) && String(s).length <= 253;
    }
    function networkPathHost() {
        if (!/^(smb|nfs|cifs|sftp|ssh):\/\//i.test(Files.path)) return "";
        const h = win.hostFromUri(Files.path);
        return win.isNetHost(h) ? h : "";
    }
    readonly property bool desktopSelected: Files.selected.length === 1 && /\.desktop$/i.test(Files.selected[0] || "")
    function checkNetworkHost() {
        const h = win.networkPathHost();
        if (h) { win.openNetTools(h); return; }
        if (win.desktopSelected) {
            desktopUrlProc.command = ["sh", "-c", 'grep -m1 "^URL=" "$1" 2>/dev/null | cut -d= -f2-', "sh", Files.selected[0]];
            desktopUrlProc.running = true;
        }
    }
    Process {
        id: desktopUrlProc
        stdout: StdioCollector {
            onStreamFinished: {
                const h = win.hostFromUri(text.trim());
                if (win.isNetHost(h)) win.openNetTools(h);
            }
        }
    }

    // ---- the finer filter popover (date / size / content) -------------------------
    // Type is not redefined here: the chips above and the popover's Type row share
    // win.searchCategories and applyCategory, so there is one source of truth.
    property bool filterShown: false
    property string dateFilter: "any"     // any | today | 7days | 30days
    property string sizeFilter: "any"     // any | small | medium | large

    // The Content box drives the settled deep search the toolbar already uses:
    // files.py's search() calls inside(), a bounded ripgrep over file text (argv,
    // --max-filesize 20M, --max-count 1, 4 s and a result cap; grep fallback).
    // So "contains" needs no new bridge command: it is time-boxed in the bridge
    // and a hung worker is ended by the service's watchdog.
    readonly property string contentQuery: Files.searchDeep ? searchBox.text.trim() : ""

    // one count for the badge and Clear filters, so no filter stays invisible
    function computeActiveFilterCount(category, date, size, content) {
        return (category !== "all" ? 1 : 0) + (date !== "any" ? 1 : 0)
             + (size !== "any" ? 1 : 0) + (content !== "" ? 1 : 0);
    }
    readonly property int activeFilterCount: win.computeActiveFilterCount(Files.activeCategory, win.dateFilter, win.sizeFilter, win.contentQuery)
    readonly property bool hasAnyFilter: win.activeFilterCount > 0 || searchBox.text.trim() !== ""

    // pure predicates: argument-driven so the suite can run them in node
    function filterDateCutoff(preset, nowMs) {
        if (preset === "today") {
            const d = new Date(nowMs);
            d.setHours(0, 0, 0, 0);
            return d.getTime();
        }
        if (preset === "7days") return nowMs - 7 * 86400000;
        if (preset === "30days") return nowMs - 30 * 86400000;
        return 0;                        // "any"
    }
    function filterSizeBounds(preset) {
        if (preset === "small") return [0, 1024 * 1024 - 1];              // < 1 MB
        if (preset === "medium") return [1024 * 1024, 100 * 1024 * 1024]; // 1-100 MB
        if (preset === "large") return [100 * 1024 * 1024 + 1, -1];       // > 100 MB
        return [-1, -1];                                                  // "any"
    }
    function entryPassesFilters(entry, nowMs, filters, foldersOnly) {
        if (!entry) return false;
        if (foldersOnly && !entry.isDir) return false;
        if (!foldersOnly && !entry.isDir && filters && filters.length) {
            const ext = "." + String(entry.name || "").split(".").pop().toLowerCase();
            const wanted = filters.map(f => f.charAt(0) === "." ? f.toLowerCase() : "." + f.toLowerCase());
            if (wanted.indexOf(ext) < 0) return false;
        }
        if (entry.isDir) return true;    // folders survive date/size so navigation is never cut
        const cutoff = win.filterDateCutoff(win.dateFilter, nowMs);
        if (cutoff && !(entry.mtime >= cutoff)) return false;
        const bounds = win.filterSizeBounds(win.sizeFilter);
        if (bounds[0] >= 0 && !(entry.size >= bounds[0])) return false;
        if (bounds[1] >= 0 && !(entry.size <= bounds[1])) return false;
        return true;
    }
    function setDateFilter(which) { win.dateFilter = which; win.sync(); win.syncSplit(); }
    function setSizeFilter(which) { win.sizeFilter = which; win.sync(); win.syncSplit(); }
    function clearAllFilters() {
        win.dateFilter = "any";
        win.sizeFilter = "any";
        searchBox.text = "";
        Files.setSearchDeep(false);
        dir.query = "";
        win.applyCategory("all");        // resets type and syncs both panes
        win.filterShown = false;
        keys.forceActiveFocus();
    }
    function toggleFilters() {
        win.filterShown = !win.filterShown;
        if (win.filterShown) filterBox.forceActiveFocus();
        else keys.forceActiveFocus();
    }

    // entries the surface actually shows after the folders-only filter
    property var visibleEntries: []
    property var splitVisibleEntries: []
    function visibleFrom(model) {
        const out = [];
        for (let i = 0; i < model.count; i++) {
            const e = model.get(i);
            if ((!Files.foldersOnly || e.isDir)
                    && win.entryPassesFilters(e, Date.now(), Files.activeFilters, Files.foldersOnly))
                out.push(e);
        }
        return out;
    }

    FileDirectory {
        id: dir
        path: win.searchingDeep ? Files.searchPath(win.deepWords) : Files.path
        includeHidden: Files.showHidden
        sortKey: Files.sortKey
        sortDesc: Files.sortDesc
        filters: Files.activeFilters
        onListed: win.sync()
    }

    // the second pane for split view
    FileDirectory {
        id: splitDir
        path: Files.splitPath
        includeHidden: Files.showHidden
        sortKey: Files.sortKey
        sortDesc: Files.sortDesc
        filters: Files.activeFilters
        onListed: {
            if (Files.splitActive)
                win.syncSplit();
        }
    }

    // a folder sync finished: both panes show the folders as they are now
    Connections {
        target: Files
        function onSyncFinished() { dir.reload(); splitDir.reload(); }
    }

    // the service keeps the paths and the entries, so a range selection and a
    // lookup by path follow what is on screen
    function sync() {
        const entries = win.visibleFrom(dir.entries);
        win.visibleEntries = entries;
        Files.setPaths(entries.map(e => e.path));
        Files.setEntries(entries);
        // a picture shows itself; the rest may have a thumbnail (a video, a PDF, an office file)
        Files.requestThumbs(entries.filter(e => !e.isDir && !e.image).map(e => e.path));
    }

    function syncSplit() {
        const entries = win.visibleFrom(splitDir.entries);
        win.splitVisibleEntries = entries;
        Files.setSplitPaths(entries.map(e => e.path));
        Files.setSplitEntries(entries);
    }

    // ---- "Open with…" app picker ---------------------------------------------
    LazyLoader {
        active: win.openWithPaths.length > 0
        PopupWindow {
            visible: true
            implicitWidth: Theme.px(380)
            implicitHeight: Theme.px(520)
            color: Theme.glassStrong
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(12)
                spacing: Theme.px(8)
                AppPicker {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    label: Tr.t("Open %1 with…").arg(win.openWithPaths.length)
                    onPicked: id => {
                        Files.openWith(id, win.openWithPaths);
                        win.openWithPaths = [];
                    }
                }
                Button {
                    Layout.alignment: Qt.AlignRight
                    text: Tr.t("Cancel")
                    onClicked: win.openWithPaths = []
                }
            }
        }
    }

    Item {
        id: blurCard
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(10)

            // ---- the toolbar ----------------------------------------------------
            // One row on every width (docs/DESIGN.md). Wide: back, forward, up,
            // the folder, search, view, sort and the everyday actions. Narrow (a
            // phone): back, the folder, search, view and More; search, when
            // opened, takes the whole row. The rarer actions live in More (⋮).
            RowLayout {
                id: toolbar
                Layout.fillWidth: true
                spacing: Theme.space(1)
                readonly property bool searching: win.compact && (win.searchOpen || searchBox.text !== "")
                readonly property int btn: Math.max(Theme.px(32), Theme.touchTarget)

                IconButton {
                    visible: !win.homeShown
                    icon: "go-previous"; size: toolbar.btn
                    tip: toolbar.searching ? Tr.t("Close search") : Tr.t("Back")
                    enabled: toolbar.searching || Files.canBack || (win.compact && !win.homeShown)
                    onClicked: toolbar.searching ? win.closeSearch() : (Files.canBack ? Files.back() : win.showHome = true)
                }
                IconButton { visible: !win.compact; icon: "go-next"; size: toolbar.btn; tip: Tr.t("Forward"); enabled: Files.canForward; onClicked: Files.forward() }
                IconButton { visible: !win.compact; icon: "go-up"; size: toolbar.btn; tip: Tr.t("Up"); enabled: Files.canUp; onClicked: Files.up() }

                RowLayout {
                    visible: !toolbar.searching
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.space(1)
                    spacing: Theme.space(2)
                    Icon { visible: !win.homeShown; name: Files.isTrash ? "user-trash" : "folder"; size: Theme.px(20); color: Theme.accent }
                    Text {
                        Layout.fillWidth: true
                        text: win.homeShown ? Tr.t("Files") : Files.placeTitle(Files.path)
                        color: Theme.text
                        elide: Text.ElideMiddle
                        font.family: Theme.font
                        font.pixelSize: Theme.type("heading")
                        font.weight: Font.DemiBold
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }
                }
                Button {
                    visible: !win.compact && (win.networkPathHost() !== "" || win.desktopSelected)
                    text: Tr.t("Network tools")
                    flat: true
                    Accessible.name: Tr.t("Check host in Network Tools")
                    onClicked: win.checkNetworkHost()
                }

                TextField {
                    id: searchBox
                    visible: !win.compact || toolbar.searching
                    Layout.fillWidth: win.compact
                    Layout.preferredWidth: win.compact ? -1 : Theme.px(220)
                    placeholder: Tr.t("Search this folder")
                    label: Tr.t("Search this folder")
                    onTextChanged: { Files.searchText = text; dir.query = Files.searchDeep ? "" : text; deepTimer.restart(); }
                    Connections { target: Files; function onSearchTextChanged() { if (searchBox.text !== Files.searchText) searchBox.text = Files.searchText; } }
                }
                // through the folders under this one too (the words then search a tree, not a folder)
                IconButton {
                    visible: !win.compact || toolbar.searching
                    icon: "folder-saved-search"
                    size: toolbar.btn
                    on: Files.searchDeep
                    tip: Files.searchDeep ? Tr.t("Searching the folders inside too") : Tr.t("Search the folders inside too")
                    onClicked: { Files.setSearchDeep(!Files.searchDeep); dir.query = Files.searchDeep ? "" : searchBox.text; deepTimer.restart(); }
                }
                IconButton {
                    visible: win.compact && !toolbar.searching && !win.homeShown
                    icon: "system-search"; size: toolbar.btn; tip: Tr.t("Search this folder")
                    onClicked: win.openSearch()
                }
                IconButton {
                    visible: !toolbar.searching && !win.homeShown
                    icon: Files.viewMode === "grid" ? "view-list" : "view-grid"
                    size: toolbar.btn
                    tip: Files.viewMode === "grid" ? Tr.t("Show as a list") : Tr.t("Show as a grid")
                    onClicked: Files.setViewMode(Files.viewMode === "grid" ? "list" : "grid")
                }
                IconButton {
                    visible: !win.compact
                    icon: "view-sort-descending"
                    size: toolbar.btn
                    tip: Tr.t("Sort by %1").arg(win.sortLabel())
                    onClicked: win.nextSort()
                }
                IconButton { visible: !win.compact; icon: "edit-paste"; size: toolbar.btn; tip: Tr.t("Paste here (Ctrl+V)"); onClicked: Files.pasteHere(Files.path) }
                IconButton { visible: !win.compact; icon: "edit-undo"; size: toolbar.btn; tip: Files.undoLabel ? Tr.t("Undo: %1 (Ctrl+Z)", Files.undoLabel) : Tr.t("Nothing to undo"); enabled: Files.undoLabel !== ""; onClicked: Files.undo() }
                IconButton { visible: !win.compact; icon: "folder-new"; size: toolbar.btn; tip: Tr.t("New folder"); onClicked: win.openNewFolder() }
                ConfirmButton {
                    id: emptyTrashConfirm
                    visible: Files.isTrash && !toolbar.searching
                    icon: "user-trash-full"
                    size: toolbar.btn
                    tip: Tr.t("Empty the trash")
                    armedText: Tr.t("Click again: everything in the trash is deleted for good")
                    interval: 4000
                    onConfirmed: Files.emptyTrash()
                }
                IconButton {
                    id: moreBtn
                    visible: !toolbar.searching && !win.homeShown
                    icon: "view-more"
                    size: toolbar.btn
                    tip: Tr.t("More")
                    accessibleName: Tr.t("More actions for this folder")
                    onClicked: win.openMenu({ folderMenu: true }, moreBtn.mapToItem(win.contentItem, moreBtn.width - Theme.px(230), moreBtn.height))
                }
            }

            // search categories: the chips feed the listing's extension filters; a row
            // that scrolls sideways when it is wider than the window (a phone)
            Flickable {
                id: catScroll
                visible: !win.homeShown
                Layout.fillWidth: true
                Layout.preferredHeight: catRow.implicitHeight
                contentWidth: catRow.implicitWidth
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
            RowLayout {
                id: catRow
                width: Math.max(implicitWidth, catScroll.width)
                spacing: Theme.px(6)
                Repeater {
                    model: win.searchCategories
                    Choice {
                        required property var modelData
                        text: modelData.label
                        selected: Files.activeCategory === modelData.id
                        onClicked: win.applyCategory(modelData.id)
                    }
                }
                // the finer filters: type stays with the chips above; this opens date, size and content
                Item {
                    Layout.preferredWidth: Math.max(Theme.px(34), Theme.touchTarget)
                    Layout.preferredHeight: Math.max(Theme.px(34), Theme.touchTarget)
                    IconButton {
                        id: filterBtn
                        anchors.fill: parent
                        icon: "view-filter"
                        size: Theme.px(30)
                        on: win.filterShown || win.activeFilterCount > 0
                        tip: win.activeFilterCount ? Tr.t("Filters · %1 active (Ctrl+Shift+F)").arg(win.activeFilterCount) : Tr.t("Filters (Ctrl+Shift+F)")
                        accessibleName: win.activeFilterCount ? Tr.t("Filters, %1 active").arg(win.activeFilterCount) : Tr.t("Filters")
                        onClicked: win.toggleFilters()
                    }
                    Rectangle {
                        visible: win.activeFilterCount > 0
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 1
                        width: Theme.px(15)
                        height: width
                        radius: width / 2
                        color: Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: String(win.activeFilterCount)
                            color: Theme.accentInk
                            font.family: Theme.font
                            font.pixelSize: Theme.px(9) * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }
            }

            // split pane toolbar: a second pane is not offered on a phone
            Flow {
                visible: Files.splitActive && !win.compact
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text {
                    width: Math.min(Theme.px(200), win.width - Theme.px(80))
                    height: Math.max(Theme.px(30), Theme.touchTarget)
                    verticalAlignment: Text.AlignVCenter
                    text: Files.splitPath === "" ? Tr.t("Split") : Files.baseName(Files.splitPath) || "/"
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.fontTitle * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton {
                    icon: Files.splitViewMode === "grid" ? "view-list" : "view-grid"
                    size: Theme.px(30)
                    tip: Tr.t("Change split view")
                    onClicked: Files.toggleSplitViewMode()
                }
                IconButton { icon: "view-split-left-right"; size: Theme.px(30); tip: Tr.t("Swap panes"); onClicked: Files.swapSplit(); enabled: Files.splitPath !== "" && Files.splitPath !== Files.path; Accessible.name: Tr.t("Swap panes") }
                IconButton { icon: "edit-copy"; size: Theme.px(30); tip: Tr.t("Copy chosen here"); onClicked: Files.copyToSplit(); enabled: Files.selected.length > 0 }
                IconButton { icon: "edit-cut"; size: Theme.px(30); tip: Tr.t("Move chosen here"); onClicked: Files.moveToSplit(); enabled: Files.selected.length > 0 }
                IconButton { icon: "go-up"; size: Theme.px(30); tip: Tr.t("Up"); enabled: Files.splitPath !== "" && Files.splitPath !== "/"; onClicked: { Files.splitPath = FilePaths.parentOf(Files.splitPath); splitDir.reload(); } }
            }

            // ---- a phone's home: where Files opens on a narrow window -------------
            FilesHome {
                visible: win.homeShown
                Layout.fillWidth: true
                Layout.fillHeight: true
                onOpened: path => win.leaveHome(path)
                onSearchRequested: { win.leaveHome(Files.home); Files.setSearchDeep(true); win.openSearch(); }
            }

            // ---- the body -------------------------------------------------------
            RowLayout {
                visible: !win.homeShown
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.px(10)

                // the places: a column beside the files, a drawer on a narrow window (a phone)
                SidePane {
                    id: placesPane
                    compact: win.compact
                    paneWidth: Theme.px(176)
                    label: Tr.t("Places")
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: placesPane.compact ? Theme.px(10) : 0
                    spacing: 2
                    Text {
                        text: Tr.t("Places")
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                    Repeater {
                        // a drive the Devices list below shows is not listed twice
                        model: Files.places.filter(p => !Files.devices.some(d => d.path && d.path === p.path))
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            height: Math.max(Theme.px(30), Theme.touchTarget)
                            radius: Theme.px(8)
                            color: Files.path === modelData.path ? Theme.accentSoft
                                 : (placeArea.containsMouse ? Theme.hover : "transparent")
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.px(8)
                                anchors.rightMargin: Theme.px(6)
                                spacing: Theme.px(8)
                                Icon { name: modelData.icon; size: Theme.px(15); color: Theme.dim }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: Theme.text
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(12) * Theme.fontScale
                                }
                            }
                            FileDropArea {
                                id: placeDrop
                                anchors.fill: parent
                                dest: modelData.path
                                Rectangle { anchors.fill: parent; visible: placeDrop.hovering; color: "transparent"; radius: Theme.px(8); border.width: 2; border.color: Theme.accent }
                            }
                            MouseArea {
                                id: placeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Files.open(modelData.path)
                            }
                            KeyFocus {
                                name: modelData.name
                                onActivated: Files.open(modelData.path)
                            }
                        }
                    }
                    // sidebar extras: Recents and Trash
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: Tr.t("Special")
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            Layout.topMargin: Theme.px(10)
                        }
                        ListRow {
                            Layout.fillWidth: true
                            icon: "document-open-recent"
                            title: Tr.t("Recents")
                            onClicked: Files.open("recent:")
                        }
                        ListRow {
                            Layout.fillWidth: true
                            icon: "starred"
                            title: Tr.t("Starred")
                            visible: Files.starred.length > 0
                            onClicked: Files.open("starred:")
                        }
                        // every file of a kind, wherever it is in your folders (ES File
                        // Explorer's Library)
                        Repeater {
                            model: Files.kinds
                            ListRow {
                                required property var modelData
                                Layout.fillWidth: true
                                icon: modelData[1]
                                title: Files.placeTitle("kind:" + modelData[0])
                                onClicked: Files.open("kind:" + modelData[0])
                            }
                        }
                        ListRow {
                            Layout.fillWidth: true
                            icon: "user-trash"
                            title: Tr.t("Trash")
                            // what is in the Trash, where it is kept (freedesktop: ~/.local/share/Trash/files)
                            onClicked: Files.open(Files.home + "/.local/share/Trash/files")
                        }
                    }
                    // Speed Dial: the shell's own named shortcuts, grouped in sections
                    SpeedDialPanel { Layout.fillWidth: true }
                    // drives, phones, cameras and network places (gio): open - mounting first
                    // when needed - and eject; the computer's other drives below them
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        visible: Files.devices.length > 0
                        Text {
                            text: Tr.t("Devices")
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            Layout.topMargin: Theme.px(10)
                        }
                        Repeater {
                            model: Files.devices.filter(d => !d.internal).concat(Files.devices.filter(d => d.internal))
                            delegate: Rectangle {
                                id: devRow
                                required property var modelData
                                Layout.fillWidth: true
                                height: Math.max(Theme.px(30), Theme.touchTarget)
                                radius: Theme.px(8)
                                color: modelData.path && Files.path.startsWith(modelData.path) ? Theme.accentSoft
                                     : (devArea.containsMouse ? Theme.hover : "transparent")
                                opacity: modelData.mounted ? 1 : 0.75
                                FileDropArea {
                                    id: devDrop
                                    anchors.fill: parent
                                    dest: devRow.modelData.mounted ? devRow.modelData.path : ""
                                    Rectangle { anchors.fill: parent; visible: devDrop.hovering; color: "transparent"; radius: Theme.px(8); border.width: 2; border.color: Theme.accent }
                                }
                                MouseArea {
                                    id: devArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Files.openDevice(devRow.modelData)
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.px(8)
                                    anchors.rightMargin: Theme.px(2)
                                    spacing: Theme.px(8)
                                    Icon { name: devRow.modelData.icon; size: Theme.px(15); color: Theme.dim }
                                    Text {
                                        Layout.fillWidth: true
                                        text: devRow.modelData.name + (devRow.modelData.internal ? " · " + Tr.t("this computer") : "")
                                        color: Theme.text
                                        elide: Text.ElideRight
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(12) * Theme.fontScale
                                    }
                                    IconButton {
                                        visible: devRow.modelData.mounted && (devRow.modelData.canEject || devRow.modelData.canUnmount)
                                        enabled: Files.busyDevice !== devRow.modelData.mount
                                        icon: "media-eject"
                                        size: Theme.px(24)
                                        tip: devRow.modelData.canEject ? Tr.t("Eject %1", devRow.modelData.name) : Tr.t("Close %1", devRow.modelData.name)
                                        onClicked: Files.ejectDevice(devRow.modelData)
                                    }
                                }
                                KeyFocus { name: devRow.modelData.name; onActivated: Files.openDevice(devRow.modelData) }
                                Accessible.role: Accessible.Button
                                Accessible.name: devRow.modelData.name
                                Accessible.onPressAction: Files.openDevice(devRow.modelData)
                            }
                        }
                    }
                    ListRow {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.px(4)
                        icon: "folder-remote"
                        title: Tr.t("Connect to server…")
                        onClicked: { Files.connectError = ""; Files.connectNeedsLogin = false; Files.loadServers(); connectBox.visible = true; }
                    }
                    // cloud drives (rclone): a click opens one; the cross forgets it here
                    Text {
                        text: Tr.t("Cloud")
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                        Layout.topMargin: Theme.px(10)
                        visible: Files.clouds.length > 0
                    }
                    Repeater {
                        model: Files.clouds
                        RowLayout {
                            id: cloudRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 0
                            ListRow {
                                Layout.fillWidth: true
                                icon: "folder-cloud"
                                title: cloudRow.modelData.name + " · " + cloudRow.modelData.label
                                onClicked: Files.openCloud(cloudRow.modelData)
                            }
                            ConfirmButton {
                                id: removeCloudConfirm
                                icon: "window-close"
                                armedIcon: "edit-delete"
                                size: Theme.px(22)
                                tip: Tr.t("Remove %1", cloudRow.modelData.name)
                                armedText: Tr.t("Click again to remove %1 from this computer (the files in the cloud stay)", cloudRow.modelData.name)
                                value: cloudRow.modelData.name
                                interval: 4000
                                onConfirmed: Files.forgetCloud(cloudRow.modelData)
                            }
                            Connections { target: cloudRow; function onModelDataChanged() { removeCloudConfirm.disarm(); } }
                        }
                    }
                    ListRow {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.px(4)
                        icon: "folder-cloud"
                        title: Tr.t("Add a cloud drive…")
                        onClicked: { Files.cloudError = ""; Files.cloudAsk = true; }
                    }
                    ListRow {
                        Layout.fillWidth: true
                        visible: Files.devices.some(d => !d.internal && d.canEject && !d.network)
                        icon: "drive-removable-media"
                        title: Tr.t("USB drives…")
                        onClicked: Files.openUsb("format")
                    }
                    Item { Layout.fillHeight: true }
                }
                }

                // the folder (main pane)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.px(8)

                    // tabs: shown once there are two (Ctrl+T); each its own folder
                    Flickable {
                        id: tabScroll
                        Layout.fillWidth: true
                        Layout.preferredHeight: tabStrip.implicitHeight
                        visible: Files.tabs.length > 1
                        contentWidth: tabStrip.implicitWidth
                        contentHeight: height
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        RowLayout {
                            id: tabStrip
                            width: Math.max(implicitWidth, tabScroll.width)
                            spacing: Theme.px(4)
                            Repeater {
                                model: Files.tabPaths
                                Rectangle {
                                    id: tabChip
                                    required property string modelData
                                    required property int index
                                    readonly property bool on: index === Files.tabIndex
                                    Layout.preferredWidth: Math.min(win.compact ? Theme.px(120) : Theme.px(180), tabRow.implicitWidth + Theme.px(16))
                                    implicitHeight: Math.max(Theme.px(30), Theme.touchTarget)
                                    radius: Theme.radiusSmall
                                    color: on ? Theme.accentSoft : (tabArea.containsMouse ? Theme.hover : Theme.surface1)
                                    border.width: on ? 1 : 0
                                    border.color: Theme.accentLine
                                    FileDropArea { id: tabDrop; anchors.fill: parent; dest: tabChip.modelData.startsWith("/") ? tabChip.modelData : "" }
                                    // a dragged tab moves among the others, Finder/Dolphin style
                                    Item {
                                        id: tabDrag
                                        width: 1; height: 1
                                        Drag.active: tabArea.drag.active
                                        Drag.dragType: Drag.Automatic
                                        Drag.supportedActions: Qt.MoveAction
                                        Drag.mimeData: ({ "text/x-shani-tab": String(tabChip.index) })
                                    }
                                    DropArea {
                                        anchors.fill: parent
                                        keys: ["text/x-shani-tab"]
                                        onEntered: d => d.accept(Qt.MoveAction)
                                        onDropped: d => {
                                            const from = parseInt(String(d.getData("text/x-shani-tab") || ""), 10);
                                            if (!isNaN(from) && from !== tabChip.index) Files.moveTab(from, tabChip.index);
                                            d.acceptProposedAction();
                                        }
                                    }
                                    MouseArea {
                                        id: tabArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                        drag.target: tabDrag
                                        onReleased: { tabDrag.x = 0; tabDrag.y = 0; }
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.MiddleButton) Files.closeTab(tabChip.index);
                                            else if (mouse.button === Qt.RightButton)
                                                win.openTabMenu(tabChip.index, tabArea.mapToItem(win, mouse.x, mouse.y));
                                            else Files.switchTab(tabChip.index);
                                        }
                                    }
                                    RowLayout {
                                        id: tabRow
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(10)
                                        anchors.rightMargin: Theme.px(2)
                                        spacing: Theme.px(4)
                                        Text {
                                            Layout.fillWidth: true
                                            text: Files.placeTitle(tabChip.modelData)
                                            elide: Text.ElideMiddle
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(12) * Theme.fontScale
                                        }
                                        IconButton { icon: "window-close"; size: Theme.px(22); tip: Tr.t("Close this tab"); onClicked: Files.closeTab(tabChip.index) }
                                    }
                                    Accessible.role: Accessible.PageTab
                                    Accessible.name: Tr.t("Tab %1: %2", tabChip.index + 1, Files.placeTitle(tabChip.modelData))
                                    Accessible.onPressAction: Files.switchTab(tabChip.index)
                                }
                            }
                            IconButton { icon: "list-add"; size: Theme.px(26); tip: Tr.t("New tab (Ctrl+T)"); onClicked: Files.newTab(Files.path) }
                            Item { Layout.fillWidth: true }
                            }
                    }

                    // the path, as the parts that lead to it (a phone's toolbar names the folder)
                    Rectangle {
                        visible: !win.compact
                        Layout.fillWidth: true
                        implicitHeight: Math.max(Theme.px(32), Theme.touchTarget + Theme.px(4))
                        radius: Theme.radiusSmall
                        color: Theme.surface1
                        border.width: 1
                        border.color: Theme.stroke
                        Flickable {
                            id: crumbsScroll
                            anchors.left: parent.left
                            anchors.right: pathBox.visible ? pathBox.left : parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: Theme.px(6)
                            anchors.leftMargin: Theme.px(8)
                            contentWidth: crumbs.implicitWidth
                            contentHeight: height
                            flickableDirection: Flickable.HorizontalFlick
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            Row {
                                id: crumbs
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Repeater {
                                    model: win.crumbsModel
                                    delegate: Row {
                                        required property var modelData
                                        required property int index
                                        spacing: 2
                                        Text {
                                            text: modelData.name
                                            height: Math.max(Theme.px(20), Theme.touchTarget)
                                            verticalAlignment: Text.AlignVCenter
                                            color: index === win.crumbsModel.length - 1 ? Theme.text : Theme.dim
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(12) * Theme.fontScale
                                            font.weight: index === win.crumbsModel.length - 1 ? Font.DemiBold : Font.Normal
                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton)
                                                        win.openPathMenu(modelData.path, mapToItem(win, mouse.x, mouse.y));
                                                    else Files.open(modelData.path);
                                                }
                                            }
                                            // keys and a controller: a folder up the path, as the click
                                            Accessible.role: Accessible.Button
                                            Accessible.name: modelData.name
                                            KeyFocus { onActivated: Files.open(modelData.path) }
                                        }
                                        // the little arrow lists this folder's siblings
                                        Text {
                                            text: "▾"
                                            height: Math.max(Theme.px(20), Theme.touchTarget)
                                            verticalAlignment: Text.AlignVCenter
                                            color: Theme.dim
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(9) * Theme.fontScale
                                            anchors.verticalCenter: parent.verticalCenter
                                            Accessible.role: Accessible.Button
                                            Accessible.name: Tr.t("Folders next to %1").arg(modelData.name)
                                            Accessible.onPressAction: { win.crumbMenuSplit = false; win.openCrumbMenu(modelData.path, mapToItem(win, 0, 0)) }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { win.crumbMenuSplit = false; win.openCrumbMenu(modelData.path, mapToItem(win, 0, 0)) }
                                            }
                                            // keys and a controller: Enter / Space lists the siblings, as the click
                                            KeyFocus { name: Tr.t("Folders next to %1").arg(modelData.name); onActivated: { win.crumbMenuSplit = false; win.openCrumbMenu(modelData.path, mapToItem(win, 0, 0)) } }
                                        }
                                        Text {
                                            visible: index < win.crumbsModel.length - 1
                                            text: "›"
                                            color: Theme.faint
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(12) * Theme.fontScale
                                        }
                                    }
                                }
                            }
                        }
                        // Ctrl+L: type a path
                        TextField {
                            id: pathBox
                            anchors.fill: parent
                            anchors.leftMargin: Theme.px(6)
                            anchors.rightMargin: Theme.px(6)
                            visible: false
                            label: Tr.t("Path")
                            onAccepted: {
                                const p = Files.normalize(text);
                                pathBox.visible = false;
                                if (p !== "")
                                    Files.open(p);
                            }
                            Keys.onEscapePressed: pathBox.visible = false
                        }
                    }

                    // the files
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusSmall
                        color: Theme.alpha(Theme.bg, 0.35)
                        clip: true

                        // a drop on the folder's background goes into the folder on screen
                        FileDropArea {
                            id: paneDrop
                            anchors.fill: parent
                            dest: Files.path.startsWith("/") && !Files.isTrash ? Files.path : ""
                            Rectangle {
                                anchors.fill: parent
                                visible: paneDrop.hovering
                                color: Theme.alpha(Theme.accent, 0.06); radius: Theme.radiusSmall
                                border.width: 2; border.color: Theme.accent
                            }
                        }

                        // a left-click on empty background drops the selection; a right-click
                        // opens the folder's own menu (new folder, paste, terminal, select all…)
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton | Qt.LeftButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.LeftButton) {
                                    Files.clearSelection();
                                    return;
                                }
                                if (Files.path.startsWith("/") && !Files.isTrash)
                                    win.openMenu({ path: Files.path, isDir: true, background: true, name: Files.baseName(Files.path) }, mapToItem(win, mouse.x, mouse.y));
                            }
                        }

                        // the grid: a tile per file
                        GridView {
                            id: grid
                            anchors.fill: parent
                            anchors.margins: Theme.px(6)
                            visible: Files.viewMode === "grid"
                            model: win.visibleEntries
                            // the columns share the width evenly (no ragged gap on the right);
                            // a phone takes a smaller base, so three fit across
                            readonly property real baseCell: Math.round((win.compact ? 100 : 124) * Files.zoom)
                            cellWidth: Math.max(Theme.touchTarget * 2, Math.floor(width / Math.max(1, Math.floor(width / baseCell))))
                            cellHeight: Math.round(112 * Files.zoom)
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            function orderedFocus() {
                                const out = [];
                                for (let i = 0; i < count; i++) {
                                    const it = itemAtIndex(i);
                                    if (it && it.focusItem)
                                        out.push(it.focusItem);
                                }
                                out.sort((a, b) => (a.parent.y - b.parent.y) || (a.parent.x - b.parent.x));
                                return out;
                            }
                            delegate: Item {
                                id: cell
                                required property var modelData
                                required property int index
                                width: grid.cellWidth
                                height: grid.cellHeight
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(3)
                                    radius: Theme.radiusSmall
                                    color: Files.isSelected(cell.modelData.path) ? Theme.accentSoft
                                         : (cellArea.containsMouse ? Theme.hover : "transparent")
                                    border.width: Files.isSelected(cell.modelData.path) ? 1 : 0
                                    border.color: Theme.accentLine
                                }
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(8)
                                    spacing: Theme.px(4)
                                    FileIcon {
                                        Layout.alignment: Qt.AlignHCenter
                                        entry: cell.modelData
                                        thumbnail: Files.thumbs[cell.modelData.path] || ""
                                        size: Theme.px(48) * Files.zoom
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: cell.modelData.name
                                        color: Theme.text
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        wrapMode: Text.Wrap
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                    // Finder's View Options: a tile can carry its size or its date
                                    Text {
                                        Layout.fillWidth: true
                                        visible: Files.gridCaption !== "off" && !(cell.modelData.isDir && Files.gridCaption === "size")
                                        text: Files.gridCaption === "date" ? Files.formatTime(cell.modelData.mtime) : Files.humanSize(cell.modelData.size)
                                        color: Theme.faint
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(9) * Theme.fontScale
                                    }
                                }
                                // dragged: the file (or the selection it is part of) as text/uri-list,
                                // a real drag other apps take too; a folder takes drops itself
                                Item {
                                    id: cellDrag
                                    width: 1; height: 1
                                    Drag.active: cellArea.drag.active
                                    Drag.dragType: Drag.Automatic
                                    Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                                    Drag.proposedAction: Qt.MoveAction
                                    Drag.mimeData: ({ "text/uri-list": Files.dragUris(cell.modelData.path) })
                                }
                                FileDropArea {
                                    id: cellDrop
                                    anchors.fill: parent
                                    dest: cell.modelData.isDir ? cell.modelData.path : ""
                                    Rectangle {
                                        anchors.fill: parent; anchors.margins: Theme.px(2)
                                        visible: cellDrop.hovering
                                        color: "transparent"; radius: Theme.radiusSmall
                                        border.width: 2; border.color: Theme.accent
                                    }
                                }
                                MouseArea {
                                    id: cellArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: hoverPeek.forceActive()
                                    onExited: hoverPeek.cancel()
                                    drag.target: cellDrag
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onReleased: { cellDrag.x = 0; cellDrag.y = 0; }
                                    onClicked: mouse => {
                                        // right: the menu - of the selection when this is in it, else of this one
                                        if (mouse.button === Qt.RightButton) {
                                            if (!Files.isSelected(cell.modelData.path)) Files.select(cell.modelData.path, "single");
                                            win.openMenu(cell.modelData, cellArea.mapToItem(win, mouse.x, mouse.y));
                                            return;
                                        }
                                        const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                        const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                        Files.select(cell.modelData.path, shift ? "range" : (ctrl ? "toggle" : "single"));
                                    }
                                    onDoubleClicked: Files.openEntry(cell.modelData.path)
                                }
                                KeyFocus {
                                    id: cellFocus
                                    name: cell.modelData.name + (cell.modelData.isDir ? ", " + Tr.t("folder") : "")
                                    columns: Math.max(1, Math.floor(grid.width / grid.cellWidth))
                                    ordered: grid.orderedFocus
                                    onActivated: Files.openEntry(cell.modelData.path)
                                    peekable: true
                                    onPeek: QuickLook.open(cell.modelData.path, Files._paths)
                                    onActiveFocusChanged: if (activeFocus) Files.current = cell.modelData.path
                                    menuable: true
                                    onMenu: win.openMenu(cell.modelData, cellArea.mapToItem(win, mouseX, mouseY))
                                }
                                HoverPeek {
                                    id: hoverPeek
                                    path: cell.modelData.path
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: cell.modelData.name
                                Accessible.onPressAction: Files.select(cell.modelData.path, "single")
                            }
                        }

                        // the list: a row per file
                        ListView {
                            reuseItems: true
                            cacheBuffer: 400
                            id: list
                            anchors.fill: parent
                            anchors.margins: Theme.px(4)
                            visible: Files.viewMode === "list"
                            model: win.visibleEntries
                            spacing: 1
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            delegate: Item {
                                id: row
                                required property var modelData
                                required property int index
                                width: list.width
                                height: Math.max(Theme.px(32), Theme.touchTarget)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.px(6)
                                    color: Files.isSelected(row.modelData.path) ? Theme.accentSoft
                                         : (rowArea.containsMouse ? Theme.hover : "transparent")
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.px(8)
                                    anchors.rightMargin: Theme.px(10)
                                    spacing: Theme.px(10)
                                    FileIcon { entry: row.modelData; thumbnail: Files.thumbs[row.modelData.path] || ""; size: Theme.px(20) }
                                    Text {
                                        Layout.fillWidth: true
                                        text: row.modelData.name
                                        color: Theme.text
                                        elide: Text.ElideMiddle
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(12) * Theme.fontScale
                                    }
                                    Text {
                                        Layout.preferredWidth: Theme.px(78)
                                        horizontalAlignment: Text.AlignRight
                                        text: row.modelData.isDir ? "" : Files.humanSize(row.modelData.size)
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                    Text {
                                        Layout.preferredWidth: Theme.px(92)
                                        horizontalAlignment: Text.AlignRight
                                        text: Files.formatTime(row.modelData.mtime)
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                }
                                // dragged: the file (or the selection it is part of) as text/uri-list,
                                // a real drag other apps take too; a folder takes drops itself
                                Item {
                                    id: rowDrag
                                    width: 1; height: 1
                                    Drag.active: rowArea.drag.active
                                    Drag.dragType: Drag.Automatic
                                    Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                                    Drag.proposedAction: Qt.MoveAction
                                    Drag.mimeData: ({ "text/uri-list": Files.dragUris(row.modelData.path) })
                                }
                                FileDropArea {
                                    id: rowDrop
                                    anchors.fill: parent
                                    dest: row.modelData.isDir ? row.modelData.path : ""
                                    Rectangle {
                                        anchors.fill: parent; anchors.margins: Theme.px(2)
                                        visible: rowDrop.hovering
                                        color: "transparent"; radius: Theme.radiusSmall
                                        border.width: 2; border.color: Theme.accent
                                    }
                                }
                                MouseArea {
                                    id: rowArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: hoverPeek.forceActive()
                                    onExited: hoverPeek.cancel()
                                    drag.target: rowDrag
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onReleased: { rowDrag.x = 0; rowDrag.y = 0; }
                                    onClicked: mouse => {
                                        // right: the menu - of the selection when this is in it, else of this one
                                        if (mouse.button === Qt.RightButton) {
                                            if (!Files.isSelected(row.modelData.path)) Files.select(row.modelData.path, "single");
                                            win.openMenu(row.modelData, rowArea.mapToItem(win, mouse.x, mouse.y));
                                            return;
                                        }
                                        const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                        const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                        Files.select(row.modelData.path, shift ? "range" : (ctrl ? "toggle" : "single"));
                                    }
                                    onDoubleClicked: Files.openEntry(row.modelData.path)
                                }
                                KeyFocus {
                                    name: row.modelData.name + (row.modelData.isDir ? ", " + Tr.t("folder") : "")
                                    onActivated: Files.openEntry(row.modelData.path)
                                    peekable: true
                                    onPeek: QuickLook.open(row.modelData.path, Files._paths)
                                    onActiveFocusChanged: if (activeFocus) Files.current = row.modelData.path
                                    menuable: true
                                    onMenu: win.openMenu(row.modelData, rowArea.mapToItem(win, mouseX, mouseY))
                                }
                                HoverPeek {
                                    id: hoverPeek
                                    path: row.modelData.path
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: row.modelData.name
                                Accessible.onPressAction: Files.select(row.modelData.path, "single")
                            }
                        }

                        // nothing here
                        EmptyState {
                            anchors.centerIn: parent
                            visible: win.visibleEntries.length === 0 && !dir.loading
                            width: parent.width - 40
                            icon: "folder"
                            title: dir.error !== "" ? Tr.t("This folder could not be opened")
                                 : win.hasAnyFilter ? Tr.t("Nothing matches this view")
                                 : Tr.t("This folder is empty")
                            subtitle: dir.error !== "" ? dir.error : Tr.t("Nothing to show here")
                            actionText: dir.error !== "" ? Tr.t("Retry")
                                        : win.hasAnyFilter ? Tr.t("Clear filters")
                                        : Tr.t("New folder")
                            onAction: {
                                if (dir.error !== "") dir.reload();
                                else if (win.hasAnyFilter) {
                                    win.dateFilter = "any";
                                    win.sizeFilter = "any";
                                    Files.setSearchDeep(false);
                                    searchBox.text = "";
                                    win.applyCategory("all");   // the type chips go back to All too
                                } else win.openNewFolder();
                            }
                            Accessible.name: title + " · " + subtitle
                        }
                        BusyNote {
                            anchors.centerIn: parent
                            visible: dir.loading && win.visibleEntries.length === 0
                            note: Tr.t("Loading…")
                        }
                    }

                    // what is there, and what is chosen
                    Text {
                        Layout.fillWidth: true
                        text: {
                            const parts = [Tr.t("%1 items").arg(win.visibleEntries.length)];
                            if (Files.freeBytes >= 0)
                                parts.push(Tr.t("%1 free").arg(Files.humanSize(Files.freeBytes)));
                            if (Files.selected.length > 0)
                                parts.push(Tr.t("%1 selected · %2").arg(Files.selected.length).arg(Files.humanSize(Files.selectedSize())));
                            if (Files.error !== "")
                                parts.push(Files.error);
                            return parts.join("  ·  ");
                        }
                        color: Files.error !== "" ? Theme.red : Theme.faint
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }

                // the split pane: wide windows only
                ColumnLayout {
                    visible: Files.splitActive && !win.compact
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.px(8)

                    // split path breadcrumbs
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.px(32)
                        radius: Theme.radiusSmall
                        color: Theme.surface1
                        border.width: 1
                        border.color: Theme.stroke
                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.px(6)
                            anchors.leftMargin: Theme.px(8)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Repeater {
                                model: win.splitCrumbsModel
                                delegate: Row {
                                    required property var modelData
                                    required property int index
                                    spacing: 2
                                    Text {
                                        text: modelData.name
                                        color: index === win.splitCrumbsModel.length - 1 ? Theme.text : Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                        font.weight: index === win.splitCrumbsModel.length - 1 ? Font.DemiBold : Font.Normal
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton)
                                                    win.openPathMenu(modelData.path, mapToItem(win, mouse.x, mouse.y));
                                                else { Files.splitPath = modelData.path; splitDir.reload(); }
                                            }
                                        }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: modelData.name
                                        KeyFocus { onActivated: { Files.splitPath = modelData.path; splitDir.reload(); } }
                                    }
                                    // the arrow lists this folder's siblings in the split pane
                                    Text {
                                        text: "▾"
                                        height: Math.max(Theme.px(20), Theme.touchTarget)
                                        verticalAlignment: Text.AlignVCenter
                                        color: Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(9) * Theme.fontScale
                                        anchors.verticalCenter: parent.verticalCenter
                                        Accessible.role: Accessible.Button
                                        Accessible.name: Tr.t("Folders next to %1").arg(modelData.name)
                                        Accessible.onPressAction: { win.crumbMenuSplit = true; win.openCrumbMenu(modelData.path, mapToItem(win, 0, 0)) }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { win.crumbMenuSplit = true; win.openCrumbMenu(modelData.path, mapToItem(win, 0, 0)) }
                                        }
                                        KeyFocus {
                                            name: Tr.t("Folders next to %1").arg(modelData.name)
                                            onActivated: { win.crumbMenuSplit = true; win.openCrumbMenu(modelData.path, mapToItem(win, 0, 0)) }
                                        }
                                    }
                                    Text {
                                        visible: index < win.splitCrumbsModel.length - 1
                                        text: "›"
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                }
                            }
                        }

                        // split pane files (grid view only for simplicity)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusSmall
                            color: Theme.alpha(Theme.bg, 0.35)
                            clip: true

                            FileDropArea {
                                id: splitDrop
                                anchors.fill: parent
                                dest: Files.splitPath.startsWith("/") ? Files.splitPath : ""
                                Rectangle { anchors.fill: parent; visible: splitDrop.hovering; color: Theme.alpha(Theme.accent, 0.06); radius: Theme.radiusSmall; border.width: 2; border.color: Theme.accent }
                            }
                            GridView {
                                anchors.fill: parent
                                anchors.margins: Theme.px(6)
                                model: win.splitVisibleEntries
                                cellWidth: 110
                                cellHeight: 100
                                boundsBehavior: Flickable.StopAtBounds
                                clip: true
                                delegate: Item {
                                    id: scell
                                    required property var modelData
                                    required property int index
                                    width: Theme.px(110)
                                    height: Theme.px(100)
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: Theme.px(3)
                                        radius: Theme.radiusSmall
                                        color: Files.isSplitSelected(scell.modelData.path) ? Theme.accentSoft
                                             : (scellArea.containsMouse ? Theme.hover : "transparent")
                                    }
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.px(6)
                                        spacing: Theme.px(3)
                                        FileIcon {
                                            Layout.alignment: Qt.AlignHCenter
                                            entry: scell.modelData
                                            thumbnail: Files.thumbs[scell.modelData.path] || ""
                                            size: Theme.px(40)
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: scell.modelData.name
                                            color: Theme.text
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            maximumLineCount: 2
                                            wrapMode: Text.Wrap
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(10) * Theme.fontScale
                                        }
                                    }
                                    Item {
                                        id: scellDrag
                                        width: 1; height: 1
                                        Drag.active: scellArea.drag.active
                                        Drag.dragType: Drag.Automatic
                                        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                                        Drag.proposedAction: Qt.MoveAction
                                        Drag.mimeData: ({ "text/uri-list": (Files.isSplitSelected(scell.modelData.path) ? Files.splitSelected : [scell.modelData.path]).map(Files.uriOf).filter(u => u !== "").join("\r\n") + "\r\n" })
                                    }
                                    FileDropArea {
                                        id: scellDrop
                                        anchors.fill: parent
                                        dest: scell.modelData.isDir ? scell.modelData.path : ""
                                        Rectangle { anchors.fill: parent; anchors.margins: Theme.px(2); visible: scellDrop.hovering; color: "transparent"; radius: Theme.radiusSmall; border.width: 2; border.color: Theme.accent }
                                    }
                                    MouseArea {
                                        id: scellArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        drag.target: scellDrag
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onReleased: { scellDrag.x = 0; scellDrag.y = 0; }
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.RightButton) {
                                                win.openMenu(scell.modelData, scellArea.mapToItem(win, mouse.x, mouse.y));
                                                return;
                                            }
                                            const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                            const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                            Files.selectSplit(scell.modelData.path, shift ? "range" : (ctrl ? "toggle" : "single"));
                                        }
                                        onDoubleClicked: { Files.splitPath = scell.modelData.path; splitDir.reload(); }
                                    }
                                    KeyFocus {
                                        name: scell.modelData.name
                                        onActivated: { Files.splitPath = scell.modelData.path; splitDir.reload(); }
                                    }
                                }
                            }

                            EmptyState {
                                anchors.centerIn: parent
                                visible: win.splitVisibleEntries.length === 0 && !splitDir.loading
                                width: parent.width - 40
                                icon: "folder"
                                title: splitDir.error !== "" ? Tr.t("This folder could not be opened") : Tr.t("This folder is empty")
                                subtitle: splitDir.error !== "" ? splitDir.error : Tr.t("Nothing to show here")
                                actionText: splitDir.error !== "" ? Tr.t("Retry") : ""
                                onAction: splitDir.reload()
                                Accessible.name: title + " · " + subtitle
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                const parts = [Tr.t("%1 items").arg(win.splitVisibleEntries.length)];
                                if (Files.splitSelected.length > 0)
                                    parts.push(Tr.t("%1 selected").arg(Files.splitSelected.length));
                                return parts.join("  ·  ");
                            }
                            color: Theme.faint
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                    }
                }

                // the preview of what is chosen
                Rectangle {
                    id: preview
                    Layout.preferredWidth: Math.min(Theme.px(230), win.width * 0.3)
                    Layout.minimumWidth: Theme.px(190)   // keep the empty state readable
                    Layout.maximumWidth: Theme.px(230)
                    Layout.fillHeight: true
                    visible: Files.showPreview && !Files.splitActive && !win.compact
                    radius: Theme.radiusSmall
                    color: Theme.alpha(Theme.bg, 0.35)
                    border.width: 1
                    border.color: Theme.stroke
                    clip: true

                    readonly property var entry: Files.selected.length === 1 ? Files.entryFor(Files.selected[0]) : null

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(12)
                        spacing: Theme.px(8)
                        visible: preview.entry !== null
                        FileIcon {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Theme.px(140)
                            Layout.preferredHeight: Theme.px(140)
                            entry: preview.entry
                            size: Theme.px(140)
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: (preview.entry && preview.entry.name) || ""
                            color: Theme.text
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: preview.entry && !preview.entry.isDir ? Files.humanSize(preview.entry.size) : ""
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        // what the camera recorded, for a picture
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            visible: PhotoMeta.camera !== "" || PhotoMeta.date !== ""
                            text: [PhotoMeta.camera, PhotoMeta.date].filter(x => x !== "").join("\n")
                            color: Theme.dim
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: preview.entry ? Files.formatTime(preview.entry.mtime) : ""
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        Item { Layout.fillHeight: true }
                        Button {
                            Layout.fillWidth: true
                            text: Tr.t("Open")
                            kind: "primary"
                            enabled: preview.entry !== null
                            onClicked: Files.openEntry(preview.entry.path)
                        }
                    }
                    EmptyState {
                        anchors.centerIn: parent
                        visible: preview.entry === null
                        width: parent.width - 24
                        icon: "document-open"
                        title: Tr.t("Nothing chosen")
                        subtitle: Tr.t("Choose a file to see it here")
                    }
                }
            }
        }
    }

    // ---- the right-click menu -------------------------------------------------
    Glass {
        id: menuBox
        parent: win.contentItem
        visible: win.menuEntry !== null
        z: 20
        strong: true
        radius: Theme.px(12)
        width: Math.min(Theme.px(230), win.width - Theme.px(24))
        height: menuCol.implicitHeight + 12
        x: Math.min(Math.max(8, win.menuX), win.width - width - 8)
        y: Math.min(Math.max(8, win.menuY), win.height - height - 8)
        Column {
            id: menuCol
            x: 6
            y: 6
            width: parent.width - 12
            Repeater {
                model: win.menuItems()
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: menuCol.width
                    height: Math.max(Theme.px(30), Theme.touchTarget)
                    radius: Theme.px(8)
                    color: menuArea.containsMouse ? Theme.hover : "transparent"
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(8)
                        anchors.rightMargin: Theme.px(6)
                        spacing: Theme.px(8)
                        Icon { name: modelData.icon; size: Theme.px(15); color: Theme.dim }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: modelData.danger ? Theme.danger : Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                        }
                    }
                    MouseArea {
                        id: menuArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            const keep = !!modelData.keep;      // "Delete for good": the first click only arms it
                            modelData.run();
                            if (!keep) win.menuEntry = null;
                        }
                    }
                    KeyFocus {
                        name: modelData.label
                        onActivated: {
                            const keep = !!modelData.keep;
                            modelData.run();
                            if (!keep) win.menuEntry = null;
                        }
                    }
                }
            }
        }
    }

    // ---- the breadcrumb sibling list ---------------------------------------------
    Glass {
        id: crumbBox
        parent: win.contentItem
        visible: win.crumbMenuFor !== ""
        z: 21
        strong: true
        radius: Theme.px(12)
        width: Math.min(Theme.px(230), win.width - Theme.px(24))
        height: Math.min(crumbCol.implicitHeight + 12, Theme.px(360))
        x: Math.min(Math.max(8, win.crumbMenuX), win.width - width - 8)
        y: Math.min(Math.max(8, win.crumbMenuY + Theme.px(16)), win.height - height - 8)
        Flickable {
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            contentHeight: crumbCol.implicitHeight
            Column {
                id: crumbCol
                width: parent.width
                Repeater {
                    model: win.crumbMenuItems
                    delegate: Rectangle {
                        required property var modelData
                        width: crumbCol.width
                        height: Math.max(Theme.px(30), Theme.touchTarget)
                        radius: Theme.px(8)
                        color: crumbArea.containsMouse ? Theme.hover : "transparent"
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.px(8)
                            spacing: Theme.px(8)
                            Icon { name: "folder"; size: Theme.px(15); color: Theme.dim }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(12) * Theme.fontScale
                                elide: Text.ElideMiddle
                            }
                        }
                        MouseArea {
                            id: crumbArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { win.openCrumbPath(modelData.path); }
                        }
                        KeyFocus {
                            name: modelData.name
                            onActivated: { win.openCrumbPath(modelData.path); }
                        }
                    }
                }
            }
        }
    }

    // ---- Select Items Matching… --------------------------------------------------
    Glass {
        id: matchBox
        parent: win.contentItem
        visible: false
        z: 32
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(Theme.px(420), win.width - Theme.px(24))
        height: matchCol.implicitHeight + 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        ColumnLayout {
            id: matchCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(10)
            Text {
                text: Tr.t("Select Items Matching…")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(14) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("A name, or a pattern with * and ?")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            TextField {
                id: matchField
                Layout.fillWidth: true
                placeholderText: "*.pdf"
                text: win.matchPattern
                onTextChanged: win.matchPattern = text
                onAccepted: win.applyMatch()
                Keys.onEscapePressed: matchBox.visible = false
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: matchBox.visible = false }
                Button { text: Tr.t("Select"); onClicked: win.applyMatch() }
            }
        }
    }

    // ---- Create Link --------------------------------------------------------------
    Glass {
        id: linkBox
        parent: win.contentItem
        visible: false
        z: 32
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(Theme.px(420), win.width - Theme.px(24))
        height: linkCol.implicitHeight + 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        ColumnLayout {
            id: linkCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(10)
            Text {
                text: Tr.t("Create Link")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(14) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("To %1", win.symlinkTarget.split("/").pop())
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                elide: Text.ElideMiddle
            }
            TextField {
                id: linkField
                Layout.fillWidth: true
                placeholderText: Tr.t("Link name")
                text: win.symlinkName
                onTextChanged: win.symlinkName = text
                onAccepted: win.applySymlink()
                Keys.onEscapePressed: linkBox.visible = false
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: linkBox.visible = false }
                Button { text: Tr.t("Create"); onClicked: win.applySymlink() }
            }
        }
    }

    // ---- renaming, and a new folder ---------------------------------------------
    Glass {
        id: renameBox
        parent: win.contentItem
        visible: false
        z: 30
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(Theme.px(420), win.width - Theme.px(24))
        height: renameCol.implicitHeight + 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        ColumnLayout {
            id: renameCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(10)
            Text {
                text: Tr.t("Rename")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                TextField {
                    id: renameField
                    Layout.fillWidth: true
                    label: Tr.t("New name")
                    onAccepted: win.commitRename()
                }
                Button { text: Tr.t("Rename"); kind: "primary"; onClicked: win.commitRename() }
            }
            // "Suggest a name": what Chronoa is doing, or why there is no suggestion
            Text {
                Layout.fillWidth: true
                visible: win.suggesting && (Tidy.naming || Tidy.namingError !== "" || Tidy.suggestion !== "")
                text: Tidy.naming ? Tr.t("Chronoa is reading it…") : Tidy.namingError !== "" ? Tidy.namingError : Tr.t("Chronoa's suggestion — change it or press Enter")
                color: Tidy.namingError !== "" ? Theme.danger : Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
        }
    }
    property bool suggesting: false
    Connections {
        target: Tidy
        function onSuggestionChanged() {
            if (win.suggesting && renameBox.visible && Tidy.suggestion !== "") {
                renameField.text = Tidy.suggestion;
                renameField.forceActiveFocus();
            }
        }
    }
    Connections { target: renameBox; function onVisibleChanged() { if (!renameBox.visible) win.suggesting = false; } }

    // ---- Tidy: what goes where, shown first; then Undo ----
    Glass {
        parent: win.contentItem
        visible: Tidy.folder === Files.path && Files.path !== "" && (Tidy.planned.length > 0 || Tidy.note !== "" || Tidy.planning)
        z: 25
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, 460)
        height: tidyCol.implicitHeight + 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.px(70)
        ColumnLayout {
            id: tidyCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                text: Tidy.planning ? Tr.t("Looking at the files…") : Tidy.planned.length ? Tr.t("Tidy %1: %2 files into folders by kind", Files.path.split("/").pop() || "/", Tidy.planned.length) : Tidy.note
                color: Theme.text
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Repeater {
                model: Tidy.groups
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Icon { name: "folder"; size: Theme.px(16); color: Theme.accent }
                    Text { Layout.fillWidth: true; text: modelData.group; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                    Text { text: Tr.t("%1 files", modelData.count); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: Tidy.planned.length > 0
                text: Tr.t("Nothing is written over, files still downloading stay, and Undo puts every one back.")
                color: Theme.faint
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tidy.planned.length ? Tr.t("Cancel") : Tr.t("Close"); flat: true; onClicked: { Tidy.cancel(); Tidy.note = ""; } }
                Button { visible: Tidy.canUndo && Tidy.planned.length === 0; text: Tr.t("Undo"); onClicked: { Tidy.undo(); dir.reload(); } }
                Button { visible: Tidy.planned.length > 0; kind: "primary"; text: Tr.t("Sort them"); onClicked: Tidy.apply() }
            }
        }
    }
    Connections { target: Tidy; function onMovedChanged() { dir.reload(); } function onNoteChanged() { dir.reload(); } }

    Glass {
        id: newFolderBox
        parent: win.contentItem
        visible: false
        z: 30
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(Theme.px(360), win.width - Theme.px(24))
        height: Theme.px(118)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(10)
            Text {
                text: Tr.t("New folder")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                TextField {
                    id: newFolderField
                    Layout.fillWidth: true
                    label: Tr.t("Folder name")
                    onAccepted: win.commitNewFolder()
                }
                Button { text: Tr.t("Create"); kind: "primary"; onClicked: win.commitNewFolder() }
            }
        }
    }

    // ---- several renamed at once: a pattern, and what it will make of them ----------
    Glass {
        id: batchBox
        parent: win.contentItem
        visible: false
        z: 30
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(Theme.px(460), win.width - Theme.px(24))
        height: batchCol.implicitHeight + 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        ColumnLayout {
            id: batchCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                text: Tr.t("Rename %1 files", win.batchPaths.length)
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("# is the number, in the order they are chosen; each keeps its own extension")
                color: Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                TextField {
                    id: batchField
                    Layout.fillWidth: true
                    label: Tr.t("New names")
                    onAccepted: win.commitBatchRename(text)
                }
                Button { text: Tr.t("Rename"); kind: "primary"; onClicked: win.commitBatchRename(batchField.text) }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text {
                    text: Tr.t("Case:")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                Choice { text: Tr.t("As typed"); selected: win.batchCase === ""; onClicked: win.batchCase = "" }
                Choice { text: Tr.t("lower"); selected: win.batchCase === "lower"; onClicked: win.batchCase = "lower" }
                Choice { text: Tr.t("UPPER"); selected: win.batchCase === "upper"; onClicked: win.batchCase = "upper" }
                Choice { text: Tr.t("Capitalize Each Word"); selected: win.batchCase === "title"; onClicked: win.batchCase = "title" }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                TextField {
                    id: batchFindField
                    Layout.fillWidth: true
                    label: Tr.t("Find")
                    onTextChanged: win.batchFind = text
                }
                TextField {
                    id: batchReplaceField
                    Layout.fillWidth: true
                    label: Tr.t("Replace with")
                    onTextChanged: win.batchReplace = text
                }
                Choice {
                    text: Tr.t("Regex")
                    selected: win.batchRegex
                    onClicked: win.batchRegex = !win.batchRegex
                }
            }
            Text {
                visible: win.batchRegexInvalid
                Layout.fillWidth: true
                text: Tr.t("That regular expression is not valid")
                color: Theme.red
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Repeater {
                model: win.batchPreview(batchField.text)
                Text {
                    required property string modelData
                    text: "→ " + modelData
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
            }
        }
    }

    // ---- Compare: two texts side by side, or what differs between two folders ------
    Glass {
        id: compareBox
        parent: win.contentItem
        visible: Files.comparison !== null
        z: 31
        strong: true
        solid: true
        radius: Theme.px(12)
        width: parent.width * 0.9
        height: parent.height * 0.85
        anchors.centerIn: parent
        readonly property var c: Files.comparison || ({})
        readonly property var rows: c.rows || []
        // where each change starts, for Next / Previous
        readonly property var starts: {
            const out = [];
            for (let i = 0; i < rows.length; i++)
                if ((rows[i].tag && rows[i].tag !== "equal" && (i === 0 || rows[i - 1].tag === "equal")) || rows[i].state)
                    out.push(i);
            return out;
        }
        function jump(dir) {
            const at = compareList.indexAt(0, compareList.contentY + 1);
            const cur = at < 0 ? -1 : at;
            const next = dir > 0 ? starts.find(i => i > cur) : starts.slice().reverse().find(i => i < cur);
            if (next !== undefined) compareList.positionViewAtIndex(next, ListView.Beginning);
        }
        function summary() {
            if (c.loading) return Tr.t("Comparing…");
            if (c.error) return c.error;
            if (c.kind === "binary") return c.same ? Tr.t("The same") : Tr.t("They differ (not text, so not line by line)");
            if (!c.changes) return Tr.t("The same");
            return c.kind === "folders" ? Tr.t("%1 differences", c.changes) : Tr.t("%1 changes", c.changes);
        }
        function shade(tag) {
            if (tag === "insert" || tag === "only-right") return Qt.alpha(Theme.accent, 0.20);
            if (tag === "delete" || tag === "only-left") return Qt.alpha(Theme.danger, 0.20);
            if (tag === "replace" || tag === "differs") return Qt.alpha(Theme.amber, 0.22);
            return "transparent";
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: FilePaths.baseName(compareBox.c.a || "") + "  ↔  " + FilePaths.baseName(compareBox.c.b || "") + "   ·   " + compareBox.summary()
                    elide: Text.ElideMiddle
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "go-up"; size: Theme.px(26); tip: Tr.t("Previous change"); visible: compareBox.starts.length > 0; onClicked: compareBox.jump(-1) }
                IconButton { icon: "go-down"; size: Theme.px(26); tip: Tr.t("Next change"); visible: compareBox.starts.length > 0; onClicked: compareBox.jump(1) }
                Button { visible: Files.compareEdited.l; text: Tr.t("Save left"); onClicked: Files.compareSave(false) }
                Button { visible: Files.compareEdited.r; text: Tr.t("Save right"); kind: "primary"; onClicked: Files.compareSave(true) }
                IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Close"); onClicked: Files.comparison = null }
            }
            // folder comparison only: sync one side into the other with rsync
            RowLayout {
                Layout.fillWidth: true
                visible: compareBox.c.kind === "folders"
                spacing: Theme.px(6)
                Text {
                    text: Tr.t("Sync:")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Button {
                    id: syncModeBtn
                    text: Files.syncMode === "mirror" ? Tr.t("Mirror · delete extra files") : Tr.t("Update · newer files only")
                    onClicked: Files.syncMode = Files.syncMode === "mirror" ? "update" : "mirror"
                    Hint { text: Files.syncMode === "mirror" ? Tr.t("rsync -a --delete: the right side becomes a copy of the left") : Tr.t("rsync -au: only newer files are copied, nothing is deleted") }
                }
                BusyNote {
                    visible: Files.syncBusy
                    note: Tr.t("Syncing…")
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: Tr.t("Sync →")
                    enabled: !Files.syncBusy
                    onClicked: Files.syncFolders(compareBox.c.a, compareBox.c.b, Files.syncMode)
                    Hint { text: Tr.t("Sync %1 into %2", FilePaths.baseName(compareBox.c.a || ""), FilePaths.baseName(compareBox.c.b || "")) }
                }
                Button {
                    text: Tr.t("Sync ←")
                    enabled: !Files.syncBusy
                    onClicked: Files.syncFolders(compareBox.c.b, compareBox.c.a, Files.syncMode)
                    Hint { text: Tr.t("Sync %1 into %2", FilePaths.baseName(compareBox.c.b || ""), FilePaths.baseName(compareBox.c.a || "")) }
                }
            }
            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: compareList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: compareBox.rows
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: compareList.width
                    height: Math.max(lt.implicitHeight, rt.implicitHeight) + 2
                    color: compareBox.shade(modelData.tag || modelData.state)
                    // a folder comparison: the path, and which side has it
                    Text {
                        visible: compareBox.c.kind === "folders"
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(6)
                        text: (modelData.path || "") + "   —   " + (modelData.state === "only-left" ? Tr.t("only in %1", FilePaths.baseName(compareBox.c.a || ""))
                              : modelData.state === "only-right" ? Tr.t("only in %1", FilePaths.baseName(compareBox.c.b || "")) : Tr.t("differs"))
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        verticalAlignment: Text.AlignVCenter
                    }
                    // a change's first line: its lines copied to the other side (Meld's arrows)
                    Row {
                        z: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        visible: compareBox.c.kind === "text" && modelData.tag && modelData.tag !== "equal" && (index === 0 || compareBox.rows[index - 1].tag === "equal")
                        IconButton { icon: "go-next"; size: Theme.px(20); tip: Tr.t("Copy this change to the right"); onClicked: Files.compareTake(index, true) }
                        IconButton { icon: "go-previous"; size: Theme.px(20); tip: Tr.t("Copy this change to the left"); onClicked: Files.compareTake(index, false) }
                    }
                    Row {
                        visible: compareBox.c.kind === "text"
                        anchors.fill: parent
                        Text {
                            id: lt
                            width: parent.width / 2
                            leftPadding: Theme.px(6)
                            text: modelData.l === null || modelData.l === undefined ? "" : (modelData.ln + "  " + modelData.l)
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.mono
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                        }
                        Text {
                            id: rt
                            width: parent.width / 2
                            leftPadding: Theme.px(6)
                            text: modelData.r === null || modelData.r === undefined ? "" : (modelData.rn + "  " + modelData.r)
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.mono
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                        }
                    }
                }
            }
        }
    }

    // ---- folder sync: confirm before rsync, --delete is destructive ------------------
    Glass {
        id: syncBox
        parent: win.contentItem
        visible: Files.syncAsk !== null
        z: 32
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(Theme.px(560), win.width - Theme.px(24))
        height: syncCol.implicitHeight + 28
        anchors.centerIn: parent
        readonly property var a: Files.syncAsk || ({})
        ColumnLayout {
            id: syncCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                text: syncBox.a.mode === "mirror"
                    ? Tr.t("Mirror %1 into %2? Files only on the right will be deleted.", FilePaths.baseName(syncBox.a.left || ""), FilePaths.baseName(syncBox.a.right || ""))
                    : Tr.t("Update %1 into %2? Only newer files are copied, nothing is deleted.", FilePaths.baseName(syncBox.a.left || ""), FilePaths.baseName(syncBox.a.right || ""))
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Dry run — what rsync would do:")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(Theme.px(220), syncPrev.implicitHeight + Theme.px(8))
                clip: true
                contentHeight: syncPrev.implicitHeight
                Text {
                    id: syncPrev
                    width: parent.width
                    text: Files.syncPreview
                    color: Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    wrapMode: Text.Wrap
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); onClicked: Files.syncCancel() }
                Button {
                    text: syncBox.a.mode === "mirror" ? Tr.t("Delete extra files and sync") : Tr.t("Sync")
                    kind: "primary"
                    onClicked: Files.syncConfirm()
                    Hint { text: Tr.t("Runs: %1", Files.syncCommand || "rsync") }
                }
            }
        }
    }

    // ---- Properties ------------------------------------------------------------------
    Glass {
        id: propsBox
        parent: win.contentItem
        visible: Files.props !== null
        z: 30
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(Theme.px(420), win.width - Theme.px(24))
        height: propsCol.implicitHeight + 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        readonly property var p: Files.props || ({})
        function row(label, value) { return value ? [label, value] : null; }

        // CoreFM's Partition tab: the free/total space on the drive the chosen folder is on.
        // files.py's `free` uses statvfs; argv only, and only for a local folder (a pseudo
        // place or a remote URI has no local drive to measure).
        property real freeBytes: -1
        property real totalBytes: -1
        readonly property bool localFolder: p.type === "folder" && typeof p.path === "string" && p.path.indexOf("/") === 0
        function probeCapacity() {
            const path = propsBox.localFolder ? propsBox.p.path : "";
            propsBox.freeBytes = -1;
            propsBox.totalBytes = -1;
            propsCapacity.forPath = path;
            if (path === "") return;
            propsCapacity.command = ["python3", Files.tool, "free", path];
            propsCapacity.running = false;
            Qt.callLater(function () { if (propsCapacity.forPath === path) propsCapacity.running = true; });
        }
        Connections {
            target: Files
            function onPropsChanged() { if (propsBox.visible && !propsBox.p.loading) propsBox.probeCapacity(); }
        }
        Process {
            id: propsCapacity
            property string forPath: ""
            stdout: SplitParser {
                onRead: line => {
                    if (propsCapacity.forPath !== propsBox.p.path) return;
                    let r = null;
                    try { r = JSON.parse(line); } catch (e) { return; }
                    if (typeof r.free === "number") propsBox.freeBytes = r.free;
                    if (typeof r.total === "number") propsBox.totalBytes = r.total;
                }
            }
            onExited: code => {
                if (code !== 0 || propsCapacity.forPath !== propsBox.p.path) {
                    propsBox.freeBytes = -1;
                    propsBox.totalBytes = -1;
                }
            }
        }
        ColumnLayout {
            id: propsCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(6)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: propsBox.p.name || Tr.t("%1 items", propsBox.p.count || 0)
                    elide: Text.ElideMiddle
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Close"); onClicked: Files.props = null }
            }
            Repeater {
                model: propsBox.p.loading ? [[Tr.t("Size"), Tr.t("Counting…")]] : [
                    propsBox.row(Tr.t("Kind"), propsBox.p.type === "folder" ? Tr.t("Folder") : propsBox.p.type),
                    propsBox.row(Tr.t("Size"), Files.humanSize(propsBox.p.size || 0) + (propsBox.p.partial ? " +" : "")
                        + ((propsBox.p.files || propsBox.p.dirs) ? "  ·  " + Tr.t("%1 files, %2 folders", propsBox.p.files || 0, propsBox.p.dirs || 0) : "")),
                    propsBox.row(Tr.t("On disk"), Files.humanSize(propsBox.p.disk || 0)),
                    propsBox.row(Tr.t("Space"), propsBox.totalBytes > 0
                        ? Tr.t("%1 free of %2", Files.humanSize(propsBox.freeBytes), Files.humanSize(propsBox.totalBytes))
                        : ""),
                    propsBox.row(Tr.t("Where"), propsBox.p.path ? FilePaths.parentOf(propsBox.p.path) : ""),
                    propsBox.row(Tr.t("Link target"), propsBox.p.linkTarget ? propsBox.p.linkTarget + (propsBox.p.linkBroken ? "  ·  " + Tr.t("broken") : "") : ""),
                    propsBox.row(Tr.t("Changed"), propsBox.p.mtime ? Files.formatTime(propsBox.p.mtime) : ""),
                    propsBox.row(propsBox.p.btimeIsCtime ? Tr.t("Changed (inode)") : Tr.t("Created"), propsBox.p.btime ? Files.formatTime(propsBox.p.btime) : ""),
                    propsBox.row(Tr.t("Opened"), propsBox.p.atime ? Files.formatTime(propsBox.p.atime) : ""),
                    propsBox.row(Tr.t("Owner"), propsBox.p.owner ? propsBox.p.owner + (propsBox.p.group && propsBox.p.group !== propsBox.p.owner ? " · " + propsBox.p.group : "") : ""),
                    propsBox.row(Tr.t("Permissions"), propsBox.p.mode || "")
                ].filter(r => r)
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.px(10)
                    Text { text: modelData[0]; Layout.preferredWidth: Theme.px(96); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                    Text { Layout.fillWidth: true; text: modelData[1]; wrapMode: Text.WrapAnywhere; color: Theme.text; font.family: modelData[0] === Tr.t("Permissions") ? Theme.mono : Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                }
            }
            // who else may open it, and whether it runs as a program: the rights, changed
            // here (with Undo) - the group and everyone else alike, as Nautilus offers it
            Picks {
                id: othersPick
                visible: !propsBox.p.loading && !!propsBox.p.path && propsBox.p.perm !== undefined
                readonly property bool dir: propsBox.p.type === "folder"
                readonly property int perm: propsBox.p.perm || 0
                label: Tr.t("Who else can open it")
                options: [{ label: Tr.t("Only you"), value: "0" }, { label: Tr.t("Everyone can look"), value: "4" }, { label: Tr.t("Everyone can change"), value: "6" }]
                current: String((perm >> 3) & 6)
                onPicked: v => {
                    const r = parseInt(v), x = dir ? (r ? 1 : 0) : ((perm >> 3) & 1);
                    const g = r | x, mode = (perm & 0o7700) | (g << 3) | g;
                    Files.setRights([[propsBox.p.path, mode]], Tr.t("Who can open %1 changed", propsBox.p.name));
                }
            }
            SwitchRow {
                Layout.fillWidth: true
                visible: othersPick.visible && !othersPick.dir
                text: Tr.t("Run as a program")
                hint: Tr.t("For a script or an app you trust: it may then do anything you can")
                checked: (othersPick.perm & 0o100) !== 0
                onToggled: on => {
                    const p = othersPick.perm;
                    // the run bit for you, and for whoever may read it
                    const mode = on ? p | 0o100 | ((p & 0o040) ? 0o010 : 0) | ((p & 0o004) ? 0o001 : 0) : p & ~0o111;
                    Files.setRights([[propsBox.p.path, mode]], on ? Tr.t("%1 runs as a program", propsBox.p.name) : Tr.t("%1 no longer runs", propsBox.p.name));
                }
            }
        }
    }

    // ---- Connect to server: smb://, sftp://, ftp://, dav(s)://, nfs:// (gio); ssh:// (sshfs)
    // the servers used before are a click each; the address is typed only the first time
    Glass {
        id: connectBox
        objectName: "files-connect"
        parent: win.contentItem
        visible: false
        z: 30
        strong: true
        solid: true
        radius: Theme.px(14)
        width: Math.min(parent.width - 40, Theme.px(440))
        height: connectCol.implicitHeight + 28
        anchors.centerIn: parent
        onVisibleChanged: if (visible) { serverField.text = Files.recentServers.length ? Files.recentServers[0] : ""; serverField.input.forceActiveFocus(); }
        ColumnLayout {
            id: connectCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text { text: Tr.t("Connect to server"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale; font.weight: Font.DemiBold }
            // what the network announces: a click connects (Nautilus's "Networks")
            Text {
                visible: Files.servers.length > 0
                text: Tr.t("On this network")
                color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                visible: Files.servers.length > 0
                Repeater {
                    model: Files.servers
                    Choice {
                        required property var modelData
                        text: modelData.name + " · " + Tr.t(modelData.kind)
                        selected: serverField.text === modelData.uri
                        onClicked: { serverField.text = modelData.uri; Files.connectServer(modelData.uri, "", "", ""); }
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                visible: Files.recentServers.length > 0
                Repeater {
                    model: Files.recentServers
                    Choice { required property string modelData; text: modelData; selected: serverField.text === modelData; onClicked: serverField.text = modelData }
                }
            }
            TextField {
                id: serverField
                Layout.fillWidth: true
                placeholder: "smb://server/share · ssh://user@host/path · davs://host/path"
                label: Tr.t("Server address")
                onAccepted: connectGo.clicked()
            }
            TextField { id: userField; Layout.fillWidth: true; visible: Files.connectNeedsLogin; placeholder: Tr.t("User name"); label: Tr.t("User name") }
            TextField { id: passField; Layout.fillWidth: true; visible: Files.connectNeedsLogin; placeholder: Tr.t("Password"); label: Tr.t("Password"); secret: true; onAccepted: connectGo.clicked() }
            Text {
                Layout.fillWidth: true
                visible: Files.connectError !== ""
                text: Files.connectNeedsLogin ? Tr.t("This server asks who you are: %1", Files.connectError) : Files.connectError
                color: Theme.danger; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: connectBox.visible = false }
                Button {
                    id: connectGo
                    text: Files.connecting ? Tr.t("Connecting…") : Tr.t("Connect")
                    enabled: !Files.connecting && serverField.text.trim() !== ""
                    onClicked: Files.connectServer(serverField.text, userField.text, passField.text, "")
                }
            }
            Connections { target: Files; function onConnectingChanged() { if (!Files.connecting && Files.connectError === "") { connectBox.visible = false; passField.text = ""; } } }
        }
    }

    // ---- Shift+Delete: asked, since there is no trash to come back from ------------
    Glass {
        id: deleteBox
        parent: win.contentItem
        visible: Files.deleteAsk.length > 0
        z: 34
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(420))
        height: deleteCol.implicitHeight + 28
        anchors.centerIn: parent
        ColumnLayout {
            id: deleteCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(10)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Files.deleteAsk.length === 1 ? Tr.t("Delete %1 for good? It does not go to the trash, so it cannot be put back.", FilePaths.baseName(Files.deleteAsk[0] || ""))
                                                   : Tr.t("Delete these %1 for good? They do not go to the trash, so they cannot be put back.", Files.deleteAsk.length)
                color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: Files.deleteAsk = [] }
                Button { text: Tr.t("Move to the trash instead"); onClicked: { const p = Files.deleteAsk; Files.deleteAsk = []; Files.trashEntries(p); } }
                Button { kind: "danger"; text: Tr.t("Delete"); onClicked: Files.deleteNow(Files.deleteAsk) }
            }
        }
    }

    // ---- a name already there: one rule for the whole job (TeraCopy's choices) ------
    Glass {
        id: conflictBox
        parent: win.contentItem
        visible: Files.conflictAsk !== null
        z: 34
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(460))
        height: conflictCol.implicitHeight + 28
        anchors.centerIn: parent
        readonly property var c: Files.conflictAsk || ({ names: [] })
        ColumnLayout {
            id: conflictCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: conflictBox.c.names.length === 1 ? Tr.t("%1 is already in %2. What should happen?", conflictBox.c.names[0], FilePaths.baseName(conflictBox.c.dest || ""))
                    : Tr.t("%1 of these are already in %2 (%3). What should happen to them?", conflictBox.c.names.length, FilePaths.baseName(conflictBox.c.dest || ""), conflictBox.c.names.slice(0, 3).join(", ") + (conflictBox.c.names.length > 3 ? "…" : ""))
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
            }
            Repeater {
                model: [["rename", Tr.t("Keep both"), Tr.t("the new one is named \"name (2)\"")],
                        ["skip", Tr.t("Skip them"), Tr.t("the ones there stay; folders get what they are missing")],
                        ["older", Tr.t("Replace the older ones"), Tr.t("only where what comes in is newer")],
                        ["differs", Tr.t("Replace where different"), Tr.t("size or date not the same")],
                        ["replace", Tr.t("Replace them all"), Tr.t("the replaced ones go to the trash")]]
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    title: modelData[1]
                    subtitle: modelData[2]
                    onClicked: Files.answerConflict(modelData[0])
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Choice { text: Tr.t("Check every copy (verify)"); selected: Files.jobVerify; onClicked: Files.setVerify(!Files.jobVerify) }
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: Files.answerConflict("") }
            }
        }
    }

    // ---- Copy to… / Move to…: a folder, the ones used lately first -----------------
    Glass {
        id: copyToBox
        parent: win.contentItem
        visible: Files.copyTo !== null
        z: 33
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(460))
        height: copyToCol.implicitHeight + 28
        anchors.centerIn: parent
        readonly property var c: Files.copyTo || ({ paths: [] })
        ColumnLayout {
            id: copyToCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: (copyToBox.c.mode === "move" ? Tr.t("Move %1 to…", copyToBox.c.paths.length === 1 ? FilePaths.baseName(copyToBox.c.paths[0]) : Tr.t("%1 items", copyToBox.c.paths.length))
                                                  : Tr.t("Copy %1 to…", copyToBox.c.paths.length === 1 ? FilePaths.baseName(copyToBox.c.paths[0]) : Tr.t("%1 items", copyToBox.c.paths.length)))
                color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.DemiBold
            }
            Repeater {
                // the ones used lately, the other pane, the sidebar's places and drives
                model: {
                    const seen = {}, out = [];
                    const add = p => { if (p && p.startsWith("/") && !seen[p]) { seen[p] = true; out.push(p); } };
                    Files.recentDests.forEach(add);
                    if (Files.splitActive) add(Files.splitPath);
                    Files.places.forEach(p => add(p.path));
                    Files.devices.filter(d => d.mounted).forEach(d => add(d.path));
                    return out.slice(0, 10);
                }
                ListRow {
                    required property string modelData
                    Layout.fillWidth: true
                    icon: "folder"
                    title: FilePaths.baseName(modelData) || "/"
                    subtitle: modelData.replace(Files.home, "~")
                    onClicked: Files.sendTo(copyToBox.c.mode, modelData)
                }
            }
            FolderPicker { id: copyToPick; Layout.fillWidth: true; label: Tr.t("Another folder"); onPicked: path => Files.sendTo(copyToBox.c.mode, path) }
            RowLayout {
                Layout.fillWidth: true
                Choice { text: Tr.t("Check every copy (verify)"); selected: Files.jobVerify; onClicked: Files.setVerify(!Files.jobVerify) }
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: Files.copyTo = null }
            }
        }
    }

    // ---- what could not be copied: listed, with Retry (just those) -------------------
    Glass {
        id: failedBox
        parent: win.contentItem
        visible: Files.jobFailed.length > 0 && !Files.jobRunning
        z: 29
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(520))
        height: Math.min(failedCol.implicitHeight + 24, parent.height * 0.6)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.px(18)
        ColumnLayout {
            id: failedCol
            anchors.fill: parent
            anchors.margins: Theme.px(12)
            spacing: Theme.px(4)
            Text {
                Layout.fillWidth: true
                text: Tr.t("%1 could not be copied - the rest were", Files.jobFailed.length)
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; font.weight: Font.DemiBold
            }
            Repeater {
                model: Files.jobFailed.slice(0, 8)
                Text {
                    required property var modelData
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: FilePaths.baseName(modelData.path) + " - " + modelData.error
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Dismiss"); flat: true; onClicked: Files.jobFailed = [] }
                Button { kind: "primary"; text: Tr.t("Retry these"); onClicked: Files.retryFailed() }
            }
        }
    }

    // ---- the copies done lately (TeraCopy's history) ---------------------------------
    Glass {
        id: historyBox
        parent: win.contentItem
        visible: Files.historyShown
        z: 33
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(560))
        height: parent.height * 0.7
        anchors.centerIn: parent
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(6)
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: Tr.t("Copy history"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale; font.weight: Font.DemiBold }
                IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Close"); onClicked: Files.historyShown = false }
            }
            Text { visible: !Files.copyHistory.length; text: Tr.t("No copies yet"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
            ListView {
                reuseItems: true
                cacheBuffer: 400
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: Files.copyHistory
                spacing: Theme.px(4)
                delegate: ColumnLayout {
                    required property var modelData
                    width: ListView.view.width
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: (modelData.mode === "move" ? Tr.t("Moved") : modelData.mode === "hash" ? Tr.t("Checksums") : modelData.mode === "check" ? Tr.t("Tested") : Tr.t("Copied"))
                              + " " + (modelData.names || []).join(", ") + ((modelData.items || 0) > (modelData.names || []).length ? "…" : "")
                              + (modelData.dest && modelData.dest !== "-" ? " → " + modelData.dest.replace(Files.home, "~") : "")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Files.formatTime((modelData.time || 0) * 1000) + " · " + Files.humanSize(modelData.bytes || 0) + " in " + (modelData.seconds || 0) + " s"
                              + (modelData.verified ? " · " + Tr.t("%1 checked", modelData.verified) : "")
                              + (modelData.failed ? " · " + Tr.t("%1 failed", modelData.failed) : "")
                              + (modelData.skipped ? " · " + Tr.t("%1 skipped", modelData.skipped) : "")
                              + (modelData.cancelled ? " · " + Tr.t("stopped") : "")
                        color: modelData.failed ? Theme.danger : Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                }
            }
        }
    }

    // ---- a cloud drive added: which one, its name; the sign-in is the provider's own
    //      page in the browser (Nextcloud / WebDAV: its address and login here)
    Glass {
        id: cloudBox
        parent: win.contentItem
        visible: Files.cloudAsk
        z: 33
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(440))
        height: cloudCol.implicitHeight + 28
        anchors.centerIn: parent
        property string kind: "drive"
        onVisibleChanged: if (visible) { kind = "drive"; cloudName.text = ""; cloudUrl.text = ""; cloudUser.text = ""; cloudPass.text = ""; }
        readonly property var labels: ({ drive: "Google Drive", onedrive: "OneDrive", dropbox: "Dropbox", box: "Box", pcloud: "pCloud", yandex: "Yandex Disk", webdav: "Nextcloud / WebDAV" })
        readonly property string name: cloudName.text.trim() || labels[kind]
        ColumnLayout {
            id: cloudCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text { text: Tr.t("Add a cloud drive"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale; font.weight: Font.DemiBold }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: ["drive", "onedrive", "dropbox", "box", "pcloud", "yandex", "webdav"]
                    Choice { required property string modelData; text: cloudBox.labels[modelData]; selected: cloudBox.kind === modelData; onClicked: cloudBox.kind = modelData }
                }
            }
            TextField { id: cloudName; Layout.fillWidth: true; placeholderText: Tr.t("Name (optional): %1", cloudBox.labels[cloudBox.kind]) }
            TextField { id: cloudUrl; visible: cloudBox.kind === "webdav"; Layout.fillWidth: true; placeholderText: "https://cloud.example.org/remote.php/dav/files/you" }
            TextField { id: cloudUser; visible: cloudBox.kind === "webdav"; Layout.fillWidth: true; placeholderText: Tr.t("User name") }
            TextField { id: cloudPass; visible: cloudBox.kind === "webdav"; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Password (an app password, where it has them)") }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: cloudBox.kind !== "webdav" || Files.cloudAdding
                text: Files.cloudAdding && cloudBox.kind !== "webdav" ? Tr.t("Sign in on the page that opened in your browser, then come back here.")
                    : Tr.t("Its sign-in page opens in your browser; this computer keeps only the permission it gives.")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Text {
                visible: Files.cloudError !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Files.cloudError
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; enabled: !Files.cloudAdding; onClicked: Files.cloudAsk = false }
                Button {
                    kind: "primary"
                    busy: Files.cloudAdding
                    enabled: !Files.cloudAdding && (cloudBox.kind !== "webdav" || (cloudUrl.text.trim() !== "" && cloudUser.text.trim() !== ""))
                    text: cloudBox.kind === "webdav" ? Tr.t("Add") : Tr.t("Sign in")
                    onClicked: Files.addCloud(cloudBox.name, cloudBox.kind, cloudUrl.text.trim(), cloudUser.text.trim(), cloudPass.text)
                }
            }
        }
    }

    // ---- a folder opened to phones: asked first (may they add files?), then a bar
    //      with its link and Stop while it runs; the QR code is the shell's QrView
    property string serveAsk: ""
    Glass {
        id: serveBox
        parent: win.contentItem
        visible: win.serveAsk !== "" || Files.servedPath !== ""
        z: 28
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(480))
        height: serveCol.implicitHeight + 24
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.px(64)
        property bool upload: false
        ColumnLayout {
            id: serveCol
            anchors.fill: parent
            anchors.margins: Theme.px(12)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Files.servedPath !== ""
                    ? (Files.servedUrl ? Tr.t("%1 is open to this network at %2 - point a phone's camera at the code. It stops by itself after an hour unused.", FilePaths.baseName(Files.servedPath), Files.servedUrl)
                                       : Tr.t("Opening %1…", FilePaths.baseName(Files.servedPath)))
                    : Tr.t("Open %1 to phones and computers on this network, through their web browser, until you stop it?", FilePaths.baseName(win.serveAsk))
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Choice { visible: Files.servedPath === ""; text: Tr.t("They can add files too"); selected: serveBox.upload; onClicked: serveBox.upload = !serveBox.upload }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { visible: Files.servedPath === ""; text: Tr.t("Cancel"); flat: true; onClicked: win.serveAsk = "" }
                Button { visible: Files.servedPath === ""; kind: "primary"; text: Tr.t("Open it"); onClicked: { Files.serveFolder(win.serveAsk, serveBox.upload); win.serveAsk = ""; serveBox.upload = false; } }
                Button { visible: Files.servedUrl !== ""; text: Tr.t("Show the code"); flat: true; onClicked: Qr.show(Tr.t("Open %1 on your phone", FilePaths.baseName(Files.servedPath)), Files.servedUrl) }
                Button { visible: Files.servedPath !== ""; kind: "danger"; text: Tr.t("Stop"); onClicked: Files.stopServing() }
            }
        }
    }

    // ---- a password: locking a file, unlocking it, a new or locked encrypted folder ----
    Glass {
        id: lockBox
        parent: win.contentItem
        visible: Files.locker !== null
        z: 33
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(420))
        height: lockCol.implicitHeight + 28
        anchors.centerIn: parent
        readonly property var l: Files.locker || ({})
        readonly property bool twice: l.mode === "lock" || l.mode === "vault-new"
        property bool trashOriginal: false
        onVisibleChanged: if (visible) {
            lockPass.text = ""; lockPass2.text = ""; vaultName.text = ""; trashOriginal = false;
            (l.mode === "vault-new" ? vaultName : lockPass).input.forceActiveFocus();
        }
        readonly property bool ready: lockPass.text !== "" && (!twice || lockPass.text === lockPass2.text)
                                      && (l.mode !== "vault-new" || vaultName.text.trim() !== "")
        function go() {
            if (!ready) return;
            Files.doLock(lockPass.text, l.mode === "vault-new" ? vaultName.text.trim() : trashOriginal);
        }
        ColumnLayout {
            id: lockCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: { const n = FilePaths.baseName(lockBox.l.path || "");
                    return lockBox.l.mode === "lock" ? (/\.pdf$/i.test(n) ? Tr.t("Lock %1 with a password. A locked copy is made beside it; any PDF reader asks for the password.", n)
                                                                          : Files.lockAsZip ? Tr.t("Lock %1 with a password, as a ZIP beside it: 7-Zip, WinRAR, Keka and this computer open it.", n)
                                                                          : Tr.t("Lock %1 with a password. It is sealed into a .gpg file beside it (gpg opens it).", n))
                         : lockBox.l.mode === "unlock" ? Tr.t("The password of %1. An unlocked copy is made beside it.", n)
                         : lockBox.l.mode === "vault-new" ? Tr.t("A new encrypted folder in %1: what you put in it is kept encrypted, file by file, and opens only with its password.", n)
                         : Tr.t("%1 is an encrypted folder. Its password opens it.", n); }
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
            }
            TextField { id: vaultName; visible: lockBox.l.mode === "vault-new"; Layout.fillWidth: true; placeholderText: Tr.t("Name, e.g. Private"); onAccepted: lockPass.input.forceActiveFocus() }
            TextField { id: lockPass; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Password"); onAccepted: lockBox.twice ? lockPass2.input.forceActiveFocus() : lockBox.go() }
            TextField { id: lockPass2; visible: lockBox.twice; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("The password again"); onAccepted: lockBox.go() }
            Text {
                visible: lockBox.twice && lockPass2.text !== "" && lockPass.text !== lockPass2.text
                text: Tr.t("The two are not the same")
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Flow {
                visible: lockBox.l.mode === "lock" && !/\.pdf$/i.test(lockBox.l.path || "")
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Choice { text: Tr.t("ZIP with a password"); selected: Files.lockAsZip; onClicked: Files.lockAsZip = true }
                Choice { text: Tr.t("Sealed with gpg"); selected: !Files.lockAsZip; onClicked: Files.lockAsZip = false }
            }
            Choice { visible: lockBox.l.mode === "lock"; text: Tr.t("Move the original to the trash"); selected: lockBox.trashOriginal; onClicked: lockBox.trashOriginal = !lockBox.trashOriginal }
            Text {
                visible: lockBox.twice
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Tr.t("There is no way back in without the password: keep it somewhere safe.")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Text {
                visible: Files.lockError !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Files.lockError
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: Files.locker = null }
                Button {
                    kind: "primary"
                    busy: Files.lockBusy
                    enabled: lockBox.ready && !Files.lockBusy
                    text: lockBox.l.mode === "lock" ? Tr.t("Lock") : lockBox.l.mode === "vault-new" ? Tr.t("Make it") : Tr.t("Unlock")
                    onClicked: lockBox.go()
                }
            }
        }
    }

    // ---- an encrypted drive's password ------------------------------------------------
    Glass {
        id: unlockBox
        parent: win.contentItem
        visible: Files.unlockFor !== null
        z: 32
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(400))
        height: unlockCol.implicitHeight + 28
        anchors.centerIn: parent
        onVisibleChanged: if (visible) { unlockPass.text = ""; unlockPass.input.forceActiveFocus(); }
        ColumnLayout {
            id: unlockCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Tr.t("%1 is locked. Its password opens it.", (Files.unlockFor || {}).name || "")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
            }
            TextField { id: unlockPass; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Password"); onAccepted: Files.unlockDevice(text) }
            Text {
                visible: Files.unlockError !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Files.unlockError
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: Files.unlockFor = null }
                Button { kind: "primary"; text: Tr.t("Unlock"); busy: Files.busyDevice !== ""; enabled: unlockPass.text !== ""; onClicked: Files.unlockDevice(unlockPass.text) }
            }
        }
    }

    // ---- USB drives: a disk image written to one, or one formatted ------------------
    // Everything on the drive goes, so its name is typed before the button wakes up
    // (as with removing an account that has files). Only drives udisks calls
    // removable are offered; the computer's own disk never is.
    Glass {
        id: usbBox
        parent: win.contentItem
        visible: Files.usb !== null
        z: 32
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(480))
        height: usbCol.implicitHeight + 28
        anchors.centerIn: parent
        readonly property var u: Files.usb || ({})
        readonly property bool writing: u.mode === "write"
        property var drive: null
        property string fs: "exfat"
        property bool encrypt: false
        function reset() { drive = null; fs = "exfat"; encrypt = false; usbConfirm.text = ""; usbLabel.text = ""; usbPass.text = ""; usbPass2.text = ""; usbOldPw.text = ""; usbNewPw.text = ""; usbNewPw2.text = ""; }
        // each time it is asked for (also straight from one kind to the other)
        Connections { target: Files; function onUsbChanged() { if (Files.usb && Files.usb.loading) usbBox.reset(); } }
        readonly property bool passOk: !encrypt || writing || (usbPass.text !== "" && usbPass.text === usbPass2.text)
        readonly property bool confirmed: drive !== null && (u.mode === "backup" ? usbBackupTo.value !== ""
                                          : u.mode === "passphrase" ? (usbOldPw.text !== "" && usbNewPw.text !== "" && usbNewPw.text === usbNewPw2.text)
                                          : usbConfirm.text.trim() === drive.name && passOk)
        ColumnLayout {
            id: usbCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: usbBox.writing ? Tr.t("Write %1 to a USB drive", FilePaths.baseName(usbBox.u.image || ""))
                        : usbBox.u.mode === "backup" ? Tr.t("Copy a USB drive into an image file")
                        : usbBox.u.mode === "passphrase" ? Tr.t("Change a locked drive's password") : Tr.t("Format a USB drive")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Close"); enabled: !Files.usbBusy; onClicked: Files.usb = null }
            }
            // what to do with a drive (GNOME Disks' menu); Write when an image was chosen
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: (usbBox.u.image ? [["write", Tr.t("Write the image")]] : []).concat([["format", Tr.t("Format")], ["backup", Tr.t("Back up to an image")], ["passphrase", Tr.t("Change its password")]])
                    Choice { required property var modelData; text: modelData[1]; selected: usbBox.u.mode === modelData[0]; onClicked: Files.usbMode(modelData[0]) }
                }
                Choice { text: Tr.t("Drive health…"); onClicked: Files.driveHealth() }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                readonly property bool erases: usbBox.u.mode === "write" || usbBox.u.mode === "format"
                text: usbBox.u.loading ? Tr.t("Looking for USB drives…")
                    : !(usbBox.u.drives || []).length ? Tr.t("No USB drive or memory card is plugged in.")
                    : erases ? Tr.t("Everything on the drive you pick is erased.")
                    : usbBox.u.mode === "backup" ? Tr.t("The drive is read, not changed: every byte of it into one file, which can be written back later.")
                    : Tr.t("The drive keeps everything on it; only the password that opens it changes.")
                color: (usbBox.u.drives || []).length && erases ? Theme.danger : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: usbBox.u.drives || []
                    Choice {
                        required property var modelData
                        text: modelData.name + " · " + Files.humanSize(modelData.size)
                        selected: usbBox.drive !== null && usbBox.drive.block === modelData.block
                        onClicked: usbBox.drive = modelData
                    }
                }
            }
            // formatting: what to format it as, and an optional name
            Flow {
                visible: !usbBox.writing && usbBox.drive !== null
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [["exfat", Tr.t("exFAT · any computer, phone, TV")], ["vfat", Tr.t("FAT32 · older devices, files up to 4 GB")],
                            ["ntfs", Tr.t("NTFS · Windows")], ["ext4", Tr.t("ext4 · Linux")], ["btrfs", Tr.t("Btrfs · Linux, snapshots")],
                            ["f2fs", Tr.t("F2FS · Linux, kind to flash")], ["xfs", Tr.t("XFS · Linux, big files")],
                            ["udf", Tr.t("UDF · any computer, files over 4 GB")]]
                    Choice { required property var modelData; text: modelData[1]; selected: usbBox.fs === modelData[0]; onClicked: usbBox.fs = modelData[0] }
                }
            }
            TextField { id: usbLabel; visible: !usbBox.writing && usbBox.drive !== null; Layout.fillWidth: true; placeholderText: Tr.t("Name (optional)") }
            // LUKS2: asked for whenever it is plugged in (GNOME Disks' "Password protect")
            Choice {
                visible: !usbBox.writing && usbBox.drive !== null
                text: Tr.t("Lock it with a password")
                selected: usbBox.encrypt
                onClicked: usbBox.encrypt = !usbBox.encrypt
            }
            TextField { id: usbPass; visible: usbBox.encrypt && !usbBox.writing && usbBox.drive !== null; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Password") }
            TextField { id: usbPass2; visible: usbPass.visible; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("The password again") }
            // backing up: where the image goes
            FolderPicker { id: usbBackupTo; visible: usbBox.u.mode === "backup" && usbBox.drive !== null; Layout.fillWidth: true; label: Tr.t("Into"); value: Files.home }
            // a new password: the old one, the new one twice
            TextField { id: usbOldPw; visible: usbBox.u.mode === "passphrase" && usbBox.drive !== null; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Its password now") }
            TextField { id: usbNewPw; visible: usbOldPw.visible; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("The new password") }
            TextField { id: usbNewPw2; visible: usbOldPw.visible; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("The new password again") }
            TextField {
                id: usbConfirm
                visible: usbBox.drive !== null && (usbBox.u.mode === "write" || usbBox.u.mode === "format")
                Layout.fillWidth: true
                placeholderText: usbBox.drive ? Tr.t("Type %1 to erase it", usbBox.drive.name) : ""
            }
            // a write under way: how far
            Rectangle {
                visible: Files.usbBusy && Files.usbTotal > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(4)
                radius: Theme.px(2)
                color: Theme.alpha(Theme.text, 0.15)
                Accessible.role: Accessible.ProgressBar
                Accessible.name: Tr.t("Writing")
                Rectangle { width: parent.width * (Files.usbTotal > 0 ? Files.usbDone / Files.usbTotal : 0); height: parent.height; radius: parent.radius; color: Theme.accent }
            }
            Text {
                visible: Files.usbError !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Files.usbError
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { visible: Files.usbBusy && (usbBox.writing || usbBox.u.mode === "backup"); text: Tr.t("Stop"); onClicked: Files.usbStop() }
                Button {
                    busy: Files.usbBusy
                    enabled: usbBox.confirmed && !Files.usbBusy
                    kind: usbBox.u.mode === "backup" || usbBox.u.mode === "passphrase" ? "primary" : "danger"
                    text: usbBox.writing ? Tr.t("Write") : usbBox.u.mode === "backup" ? Tr.t("Back up") : usbBox.u.mode === "passphrase" ? Tr.t("Change it") : Tr.t("Format")
                    onClicked: {
                        if (!usbBox.confirmed) return;
                        if (usbBox.writing) Files.usbWrite(usbBox.drive);
                        else if (usbBox.u.mode === "backup") Files.usbBackup(usbBox.drive, usbBackupTo.value);
                        else if (usbBox.u.mode === "passphrase") Files.usbPassphrase(usbBox.drive, usbOldPw.text, usbNewPw.text);
                        else Files.usbFormat(usbBox.drive, usbBox.fs, usbLabel.text.trim(), usbBox.encrypt ? usbPass.text : "");
                    }
                }
            }
        }
    }

    // ---- a copy or a move under way: how far, and Stop ------------------------------
    Glass {
        id: jobBar
        objectName: "files-job"
        parent: win.contentItem
        visible: Files.jobRunning
        z: 29
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(460))
        height: jobCol.implicitHeight + 20
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.px(18)
        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(10)
            spacing: Theme.px(12)
            ColumnLayout {
                id: jobCol
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: (Files.jobPaused ? Tr.t("Paused") : Files.jobPhase === "verifying" ? Tr.t("Checking the copy")
                           : Files.jobMode === "hash" ? Tr.t("Making checksums") : Files.jobMode === "check" ? Tr.t("Testing checksums")
                           : Files.jobMode === "move" ? Tr.t("Moving") : Tr.t("Copying"))
                          + (Files.jobTotal > 0 ? " · " + Files.humanSize(Files.jobDone) + " / " + Files.humanSize(Files.jobTotal) : "")
                          + (Files.jobRate > 0 && !Files.jobPaused ? " · " + Files.humanSize(Files.jobRate) + "/s" : "")
                          + (Files.jobSecondsLeft > 0 && !Files.jobPaused ? " · " + (Files.jobSecondsLeft >= 3600 ? Tr.t("%1 h %2 min left", Math.floor(Files.jobSecondsLeft / 3600), Math.round(Files.jobSecondsLeft % 3600 / 60))
                                                                                   : Files.jobSecondsLeft >= 60 ? Tr.t("%1 min left", Math.round(Files.jobSecondsLeft / 60)) : Tr.t("%1 s left", Math.ceil(Files.jobSecondsLeft))) : "")
                          + (Files.jobsWaiting > 0 ? " · " + Tr.t("%1 more waiting", Files.jobsWaiting) : "")
                          + (Files.jobFile ? " · " + Files.jobFile : "")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(4)
                    radius: Theme.px(2)
                    color: Theme.alpha(Theme.text, 0.15)
                    Accessible.role: Accessible.ProgressBar
                    Accessible.name: Tr.t("Copy progress")
                    Rectangle { width: parent.width * Files.jobFraction; height: parent.height; radius: parent.radius; color: Theme.accent }
                }
            }
            // when everything queued is done (TeraCopy's "Shut down when finished")
            Choice {
                text: Files.whenDone === "suspend" ? Tr.t("Then sleep") : Files.whenDone === "poweroff" ? Tr.t("Then shut down") : Tr.t("Then: nothing")
                selected: Files.whenDone !== ""
                onClicked: Files.whenDone = Files.whenDone === "" ? "suspend" : Files.whenDone === "suspend" ? "poweroff" : ""
            }
            Button { text: Files.jobPaused ? Tr.t("Resume") : Tr.t("Pause"); flat: true; onClicked: Files.pauseJob() }
            Button { text: Tr.t("Stop"); flat: true; onClicked: Files.cancelJob() }
        }
    }

    // ---- what was just done, with Undo -------------------------------------------------
    Glass {
        id: noteBar
        parent: win.contentItem
        visible: Files.note !== "" && !Files.props && !Files.jobRunning
        z: 28
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, noteRow.implicitWidth + 28)
        height: noteRow.implicitHeight + 18
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.px(18)
        RowLayout {
            id: noteRow
            anchors.centerIn: parent
            spacing: Theme.px(12)
            Text { text: Files.note; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
            Button { visible: Files.undoLabel !== "" && Files.note === Files.undoLabel; flat: true; text: Tr.t("Undo"); onClicked: Files.undo() }
        }
        Timer { id: noteTimer; running: noteBar.visible; interval: 7000; onTriggered: Files.note = "" }
        Connections { target: Files; function onNoteChanged() { noteTimer.restart(); } }
    }

    // last searches, on focus: the same store the service persists, no second copy
    Glass {
        id: searchHistoryBox
        parent: win.contentItem
        visible: searchBox.activeFocus && searchBox.text === "" && Files.searchHistory.length > 0 && !Files.props && !batchBox.visible
        z: 29
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.max(Theme.px(240), searchBox.width)
        height: historyCol.implicitHeight + Theme.px(16)
        x: searchBox.mapToItem(win.contentItem, 0, searchBox.height).x
        y: searchBox.mapToItem(win.contentItem, 0, searchBox.height).y + Theme.px(4)
        ColumnLayout {
            id: historyCol
            anchors.fill: parent
            anchors.margins: Theme.px(8)
            spacing: Theme.px(2)
            Repeater {
                model: Files.searchHistory.slice(0, Files.searchHistoryMax)
                Button {
                    required property string modelData
                    Layout.fillWidth: true
                    flat: true
                    text: modelData
                    onClicked: { searchBox.text = modelData; searchBox.forceActiveFocus(); }
                }
            }
            Button {
                Layout.fillWidth: true
                flat: true
                text: Tr.t("Clear search history")
                onClicked: Files.clearSearchHistory()
            }
        }
    }

    // ---- the finer filter popover: date / size / content, beside the type chips -------
    // Translucent Glass on purpose: no opaque card over the folder listing.
    Glass {
        id: filterBox
        parent: win.contentItem
        visible: win.filterShown
        z: 29
        strong: true
        radius: Theme.px(12)
        width: Math.min(Theme.px(390), win.width - Theme.px(24))
        height: filterCol.implicitHeight + Theme.px(20)
        x: Math.min(Math.max(8, filterBtn.mapToItem(win.contentItem, 0, filterBtn.height).x), win.width - width - 8)
        y: Math.min(filterBtn.mapToItem(win.contentItem, 0, filterBtn.height).y + Theme.px(4), win.height - height - 8)
        focus: visible
        Accessible.role: Accessible.Dialog
        Accessible.name: Tr.t("File filters")
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) { win.toggleFilters(); event.accepted = true; }
        }
        ColumnLayout {
            id: filterCol
            anchors.fill: parent
            anchors.margins: Theme.px(10)
            spacing: Theme.px(8)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: win.activeFilterCount ? Tr.t("Filters · %1 active").arg(win.activeFilterCount) : Tr.t("Filters")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "window-close"; size: Theme.px(24); tip: Tr.t("Close filters"); onClicked: win.toggleFilters() }
            }
            // Type: the very same chips and applyCategory the toolbar uses - no second model
            Text {
                text: Tr.t("Type · choose with the chips above")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: win.searchCategories
                    Choice {
                        required property var modelData
                        text: modelData.label
                        selected: Files.activeCategory === modelData.id
                        onClicked: win.applyCategory(modelData.id)
                    }
                }
            }
            Text {
                text: Tr.t("Date modified")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
                Layout.topMargin: Theme.px(4)
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [["any", Tr.t("Any time")], ["today", Tr.t("Today")], ["7days", Tr.t("Last 7 days")], ["30days", Tr.t("Last 30 days")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.dateFilter === modelData[0]
                        onClicked: win.setDateFilter(modelData[0])
                    }
                }
            }
            Text {
                text: Tr.t("Size")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
                Layout.topMargin: Theme.px(4)
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [["any", Tr.t("Any size")], ["small", Tr.t("Under 1 MB")], ["medium", Tr.t("1-100 MB")], ["large", Tr.t("Over 100 MB")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.sizeFilter === modelData[0]
                        onClicked: win.setSizeFilter(modelData[0])
                    }
                }
            }
            Text {
                text: Tr.t("Content contains")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
                Layout.topMargin: Theme.px(4)
            }
            TextField {
                id: contentField
                Layout.fillWidth: true
                placeholder: Tr.t("Words inside a file (3 or more letters)")
                label: Tr.t("Content contains")
                text: searchBox.text
                onTextChanged: {
                    if (text === searchBox.text) return;
                    if (text.trim() !== "" && !Files.searchDeep) Files.setSearchDeep(true);
                    searchBox.text = text;
                    dir.query = Files.searchDeep ? "" : text;
                    deepTimer.restart();
                }
                // let the Glass popover own Escape; toggling here made the
                // event propagate and toggle a second time, leaving it open
                Keys.onEscapePressed: { win.toggleFilters(); event.accepted = true; }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Tr.t("Looks through this folder and the ones inside it, matching file names and text inside files.")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.px(4)
                Button {
                    text: Tr.t("Clear filters")
                    flat: true
                    enabled: win.hasAnyFilter
                    onClicked: win.clearAllFilters()
                }
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Done"); kind: "primary"; onClicked: win.toggleFilters() }
            }
        }
    }

    // ---- the keyboard shortcut sheet (Ctrl+/ or ?) -----------------------------------
    Glass {
        id: shortcutSheet
        parent: win.contentItem
        visible: win.shortcutsShown
        z: 36
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(Theme.px(430), win.width - Theme.px(24))
        height: Math.min(Theme.px(520), win.height - Theme.px(40))
        anchors.centerIn: parent
        focus: visible
        Accessible.name: Tr.t("Keyboard shortcuts")
        Keys.onPressed: event => {
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            if (event.key === Qt.Key_Escape || (ctrl && event.key === Qt.Key_Slash)) {
                win.toggleShortcuts();
                event.accepted = true;
            }
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(12)
            spacing: Theme.px(8)
            Text {
                text: Tr.t("Keyboard shortcuts")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.fontTitle * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: shortcutGrid.implicitHeight
                GridLayout {
                    id: shortcutGrid
                    columns: 2
                    width: parent.width
                    rowSpacing: Theme.px(4)
                    columnSpacing: Theme.px(12)
                    Repeater {
                        model: win.shortcutRows
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(8)
                            Text { text: modelData.key; color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.DemiBold; Layout.minimumWidth: Theme.px(90) }
                            Text { Layout.fillWidth: true; text: modelData.label; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; wrapMode: Text.Wrap }
                        }
                    }
                }
            }
            Button { Layout.alignment: Qt.AlignRight; text: Tr.t("Close"); onClicked: win.toggleShortcuts() }
        }
    }

    // ---- the pieces that need the window ------------------------------------------
    property var menuEntry: null
    property string typed: ""                // type to find: what was typed so far
    Timer { id: typedTimer; interval: 1000; onTriggered: win.typed = "" }
    property real menuX: 0
    property real menuY: 0

    // the parts of the path, as the buttons that lead to it
    readonly property var crumbsModel: {
        const p = Files.path;
        if (!p || p === "/")
            return [{ name: "/", path: "/" }];
        const home = Files.home;
        const out = [];
        let rest = p;
        let at = "";
        if (home && (p === home || p.indexOf(home + "/") === 0)) {
            out.push({ name: Tr.t("Home"), path: home });
            rest = p.substring(home.length);
            at = home;
        } else {
            // outside Home, the root is the first ancestor you can jump to
            out.push({ name: "/", path: "/" });
        }
        for (const part of rest.split("/").filter(x => x)) {
            at = at + "/" + part;
            out.push({ name: part, path: at });
        }
        // a long path: the last few parts are what matter
        if (out.length > 5)
            return out.slice(0, 1).concat(out.slice(-3));
        return out;
    }

    readonly property var splitCrumbsModel: {
        const p = Files.splitPath;
        if (!p || p === "/")
            return [{ name: "/", path: "/" }];
        const home = Files.home;
        const out = [];
        let rest = p;
        let at = "";
        if (home && (p === home || p.indexOf(home + "/") === 0)) {
            out.push({ name: Tr.t("Home"), path: home });
            rest = p.substring(home.length);
            at = home;
        } else {
            // outside Home, the root is the first ancestor you can jump to
            out.push({ name: "/", path: "/" });
        }
        for (const part of rest.split("/").filter(x => x)) {
            at = at + "/" + part;
            out.push({ name: part, path: at });
        }
        if (out.length > 5)
            return out.slice(0, 1).concat(out.slice(-3));
        return out;
    }

    // ---- breadcrumb dropdowns: a crumb's sibling folders --------------------------
    property string crumbMenuFor: ""
    property var crumbMenuItems: []
    property real crumbMenuX: 0
    property real crumbMenuY: 0
    property bool crumbMenuSplit: false   // a split-pane crumb navigates that pane
    function openCrumbMenu(path, point) {
        crumbMenuFor = path;
        crumbMenuItems = [];
        crumbMenuX = point.x;
        crumbMenuY = point.y;
        // the siblings of a crumb live in its parent folder
        const parent = path === "/" ? "/" : (path.substring(0, path.lastIndexOf("/")) || "/");
        Files.list(parent, {}, r => {
            if (crumbMenuFor !== path) return;             // a newer click won
            crumbMenuItems = (r.entries || []).filter(e => e.isDir).map(e => ({ name: e.name, path: e.path }));
        });
    }
    function closeCrumbMenu() { crumbMenuFor = ""; crumbMenuItems = []; crumbMenuSplit = false; }
    function openCrumbPath(path) {
        const split = win.crumbMenuSplit;
        closeCrumbMenu();
        if (split) { Files.splitPath = path; splitDir.reload(); }
        else Files.open(path);
    }

    // ---- Select Items Matching… and Create Link ----------------------------------
    property string matchPattern: ""
    function openMatch() { matchPattern = ""; matchBox.visible = true; matchField.forceActiveFocus(); }
    function applyMatch() {
        const n = Files.selectMatching(matchPattern);
        Files.note = Tr.t("%1 item%2 selected", n, n === 1 ? "" : "s");
        matchBox.visible = false;
    }
    property string symlinkTarget: ""
    property string symlinkName: ""
    function askSymlink(path) {
        symlinkTarget = path;
        symlinkName = Tr.t("Link to %1", FilePaths.baseName(path));
        linkBox.visible = true;
        linkField.forceActiveFocus();
    }
    function applySymlink() {
        const name = symlinkName.trim();
        if (!name || !symlinkTarget) { linkBox.visible = false; return; }
        if (name.indexOf("/") >= 0) { Files.error = Tr.t("That is not a name"); return; }
        const link = Files.path.replace(/\/$/, "") + "/" + name;
        Files.symlink(symlinkTarget, link, r => {
            linkBox.visible = false;
            if (r.error) Files.error = r.error;
            else { Files.error = ""; Files.note = Tr.t("Link created"); Files.list(Files.path, { sortKey: Files.sortKey, sortDesc: Files.sortDesc, includeHidden: Files.showHidden, filters: Files.activeFilters || [] }, () => {}); }
        });
    }

    function sortLabel() {
        if (Files.sortKey === "size") return Tr.t("size");
        if (Files.sortKey === "mtime") return Tr.t("date");
        if (Files.sortKey === "btime") return Tr.t("date created");
        if (Files.sortKey === "type") return Tr.t("type");
        return Tr.t("name");
    }

    property bool searchOpen: false
    // a phone opens on its home (FilesHome); a folder opened from anywhere leaves it
    property bool showHome: true
    readonly property bool homeShown: compact && showHome
    function leaveHome(path) { showHome = false; if (path !== Files.path) Files.open(path); }
    Connections { target: Files; function onPathChanged() { if (win.compact) win.showHome = false; } }
    function openSearch() { searchOpen = true; searchBox.input.forceActiveFocus(); }
    function closeSearch() { searchBox.text = ""; searchOpen = false; }
    function nextSort() {
        const order = ["name", "size", "mtime", "btime", "type"];
        Files.setSort(order[(order.indexOf(Files.sortKey) + 1) % order.length]);
    }
    function openMenu(entry, point) {
        if (!entry)
            return;
        menuEntry = entry;
        menuX = point.x;
        menuY = point.y;
    }
    // the same menu popup serves a tab chip and a breadcrumb button
    function openTabMenu(i, point) { openMenu({ tabMenu: true, index: i }, point); }
    function openPathMenu(path, point) { openMenu({ pathMenu: true, path: path }, point); }
    function openInSplit(path) {
        Files.openInSplit(path);
        splitDir.reload();
    }
    property bool shortcutsShown: false
    readonly property var shortcutRows: [
        { key: "Ctrl+T", label: Tr.t("New tab") },
        { key: "Ctrl+Shift+T", label: Tr.t("Reopen the last closed tab") },
        { key: "Ctrl+W / middle click", label: Tr.t("Close tab") },
        { key: "Ctrl+1…9", label: Tr.t("Go to tab") },
        { key: "Ctrl+L", label: Tr.t("Type a path") },
        { key: "Ctrl+D", label: Tr.t("Bookmark this folder") },
        { key: "Ctrl+H", label: Tr.t("Show hidden files") },
        { key: "Ctrl+Shift+F", label: Tr.t("The finer filters") },
        { key: "Ctrl+A / Ctrl+Shift+I", label: Tr.t("Select all / invert the selection") },
        { key: "Ctrl+Shift+Y", label: Tr.t("Select all of this type") },
        { key: "Ctrl+Alt+N", label: Tr.t("Split view") },
        { key: "Ctrl+C / Ctrl+X / Ctrl+V", label: Tr.t("Copy / cut / paste") },
        { key: "Ctrl+F2", label: Tr.t("Batch rename") },
        { key: "F2 / F4", label: Tr.t("Rename / open a terminal here") },
        { key: "Delete / Shift+Delete", label: Tr.t("Trash / delete for good") },
        { key: "Space / F5", label: Tr.t("Quick Look / refresh") },
        { key: "Ctrl+/", label: Tr.t("This shortcut sheet") }
    ]
    function toggleShortcuts() {
        shortcutsShown = !shortcutsShown;
        if (shortcutsShown) shortcutSheet.forceActiveFocus();
        else keys.forceActiveFocus();
    }

    function menuItems() {
        const e = menuEntry;
        if (!e)
            return [];
        const items = [];
        if (e.tabMenu) {
            const i = e.index, count = Files.tabPaths.length;
            items.push({ label: Tr.t("Duplicate tab"), icon: "tab-new", danger: false, run: () => Files.duplicateTab(i) });
            if (count > 2)
                items.push({ label: Tr.t("Close other tabs"), icon: "tab-close-other", danger: false, run: () => Files.closeOtherTabs(i) });
            if (i < count - 1)
                items.push({ label: Tr.t("Close tabs to the right"), icon: "tab-close-right", danger: false, run: () => Files.closeTabsToRight(i) });
            items.push({ label: Tr.t("Close tab"), icon: "window-close", danger: false, run: () => Files.closeTab(i) });
            return items;
        }
        if (e.folderMenu) {
            // the toolbar's More (⋮): what a narrow window has no room for, and the rarer actions everywhere
            if (compact) {
                items.push({ label: Tr.t("Refresh"), icon: "view-refresh", danger: false, run: () => win.refresh() });
                if (Files.canUp)
                    items.push({ label: Tr.t("Up one folder"), icon: "go-up", danger: false, run: () => Files.up() });
                items.push({ label: Tr.t("New folder"), icon: "folder-new", danger: false, run: () => win.openNewFolder() });
                items.push({ label: Tr.t("Paste here"), icon: "edit-paste", danger: false, run: () => Files.pasteHere(Files.path) });
                if (Files.undoLabel !== "")
                    items.push({ label: Tr.t("Undo: %1", Files.undoLabel), icon: "edit-undo", danger: false, run: () => Files.undo() });
                items.push({ label: Tr.t("Sort by %1").arg(win.sortLabel()), icon: "view-sort-descending", danger: false, keep: true, run: () => win.nextSort() });
                if (win.networkPathHost() !== "" || win.desktopSelected)
                    items.push({ label: Tr.t("Network tools"), icon: "network-workgroup", danger: false, run: () => win.checkNetworkHost() });
            }
            items.push({ label: Files.sortDesc ? Tr.t("Sort: largest / newest first") : Tr.t("Sort: smallest / oldest first"), icon: Files.sortDesc ? "view-sort-ascending" : "view-sort-descending", danger: false, keep: true, run: () => Files.setSort(Files.sortKey) });
            items.push({ label: Files.showHidden ? Tr.t("Hide hidden files") : Tr.t("Show hidden files"), icon: Files.showHidden ? "view-conceal" : "view-reveal", danger: false, run: () => Files.toggleHidden() });
            items.push({ label: Files.isBookmarked(Files.path) ? Tr.t("Remove bookmark") : Tr.t("Bookmark this folder"), icon: Files.isBookmarked(Files.path) ? "user-bookmarks" : "bookmark-new", danger: false, run: () => Files.toggleBookmark() });
            items.push({ label: Tr.t("Tidy this folder"), icon: "edit-clear-all", danger: false, run: () => Tidy.plan(Files.path) });
            if (!compact) {
                items.push({ label: Files.splitActive ? Tr.t("Close split view") : Tr.t("Split view"), icon: Files.splitActive ? "view-close" : "view-dual", danger: false, run: () => Files.toggleSplit() });
                items.push({ label: Tr.t("Keyboard shortcuts"), icon: "help-faq", danger: false, run: () => win.toggleShortcuts() });
            }
            return items;
        }
        if (e.pathMenu) {
            const p = e.path;
            items.push({ label: Tr.t("Open in a new tab"), icon: "tab-new", danger: false, run: () => Files.newTab(p) });
            if (p.startsWith("/"))
                items.push({ label: Tr.t("Open in split pane"), icon: "view-dual", danger: false, run: () => win.openInSplit(p) });
            items.push({ label: Tr.t("Copy path"), icon: "edit-copy", danger: false, run: () => Files.copyPath(p) });
            items.push({ label: Files.isBookmarked(p) ? Tr.t("Remove from the sidebar") : Tr.t("Add to the sidebar"), icon: "user-bookmarks", danger: false, run: () => Files.toggleBookmark(p) });
            return items;
        }
        if (e.background) {
            items.push({ label: Tr.t("New folder"), icon: "folder-new", danger: false, run: () => win.openNewFolder() });
            for (const tpl of Files.templates)
                items.push({ label: Tr.t("New %1", tpl.name), icon: "document-new", danger: false, run: () => Files.newFromTemplate(tpl, e.path) });
            items.push({ label: Tr.t("Paste"), icon: "edit-paste", danger: false, run: () => Files.pasteHere(e.path) });
            items.push({ label: Tr.t("Open in terminal"), icon: "utilities-terminal", danger: false, run: () => Files.openTerminal(e.path) });
            items.push({ label: Tr.t("New encrypted folder…"), icon: "folder-locked", danger: false, run: () => Files.askLock("vault-new", e.path) });
            items.push({ label: Tr.t("Copy history"), icon: "document-open-recent", danger: false, run: () => { Files.loadCopyHistory(); Files.historyShown = true; } });
            if (e.path.startsWith("/"))
                items.push({ label: Tr.t("Open from your phone…"), icon: "phone", danger: false, run: () => win.serveAsk = e.path });
            if (e.path.startsWith("/") && !Files.asAdmin)
                items.push({ label: Tr.t("Open as administrator"), icon: "security-high", danger: false, run: () => Files.openAsAdmin(e.path, true) });
            items.push({ label: Tr.t("Select all"), icon: "edit-select-all", danger: false, run: () => Files.selectAll() });
            items.push({ label: Tr.t("Turn the selection over"), icon: "edit-select-invert", danger: false, run: () => Files.invertSelection() });
            items.push({ label: Tr.t("Select Items Matching…"), icon: "edit-find", danger: false, run: () => win.openMatch() });
            items.push({ label: Tr.t("Grid captions: %1", Files.gridCaption), icon: "view-grid", danger: false, run: () => Files.cycleGridCaption() });
            items.push({ label: Tr.t("Reopen closed tab (Ctrl+Shift+T)"), icon: "tab-new", danger: false, run: () => Files.reopenClosedTab() });
            if (e.path.startsWith("/"))
                items.push({ label: Tr.t("Save folder tree as text…"), icon: "document-save-as", danger: false, run: () => win.askSaveTree(e.path) });
            items.push({ label: Tr.t("Properties"), icon: "document-properties", danger: false, run: () => Files.showProps([e.path]) });
            return items;
        }
        const chosen = Files.selected.indexOf(e.path) >= 0 ? Files.selected.slice() : [e.path];
        // in the trash: put back where it came from, or delete for good (asked twice)
        if (Files.isTrash) {
            const from = (Files.trashItems[Files.trashNameOf(e.path)] || {}).original || "";
            items.push({ label: from ? Tr.t("Put back in %1", FilePaths.baseName(FilePaths.parentOf(from)) || "/") : Tr.t("Put back"),
                         icon: "edit-undo", danger: false, run: () => Files.putBack(chosen) });
            items.push({ label: win.confirmDelete === e.path ? Tr.t("Click again: gone for good") : Tr.t("Delete for good"), icon: "edit-delete", danger: true,
                         keep: win.confirmDelete !== e.path,
                         run: () => { if (win.confirmDelete !== e.path) { win.confirmDelete = e.path; confirmTimer.restart(); return; } win.confirmDelete = ""; Files.deleteForGood(chosen); } });
            return items;
        }
        if (e.isDir)
            items.push({ label: Tr.t("Open"), icon: "folder-open", danger: false, run: () => Files.open(e.path) });
        else
            items.push({ label: Tr.t("Open"), icon: "document-open", danger: false, run: () => Files.openEntry(e.path) });
        // the shell's own app first, when the whole selection has one owner;
        // the desktop app picker below stays the fallback for everything else
        const routed = !e.isDir && chosen.every(p => !(Files.entryFor(p) || {}).isDir)
                       ? Files.routeForPaths(chosen, QuickNotes.dir) : "";
        if (routed) {
            const info = Files.routeInfo(routed);
            items.push({ label: Tr.t("Open in %1", info.label), icon: info.icon, danger: false,
                         run: () => Files.openRoute(chosen) });
        }
        items.push({ label: Tr.t("Open with…"), icon: "view-app-grid", danger: false, run: () => { win.openWithPaths = chosen.slice(); } });
        // the database browser reads the path off the clipboard as it opens
        if (!e.isDir && /\.(db|sqlite|sqlite3)$/i.test(e.path))
            items.push({ label: Tr.t("Open in Database Browser"), icon: "database", danger: false,
                         run: () => { Quickshell.clipboardText = e.path; Files.hide(); Ui.closeAll(); Ui.databaseBrowser = true; } });
        items.push({ label: Tr.t("Select all of this type"), icon: "edit-select-all", danger: false, run: () => { Files.select(e.path, "single"); Files.note = Tr.t("%1 selected", Files.selectByType()); } });
        if (e.isDir && e.path.startsWith("/"))
            items.push({ label: Tr.t("Open in split pane"), icon: "view-dual", danger: false, run: () => win.openInSplit(e.path) });
        items.push({ label: Tr.t("Rename"), icon: "document-edit", danger: false, run: () => beginRename(e.path) });
        if (!e.isDir)
            items.push({ label: Tr.t("Suggest a name"), icon: "tools-check-spelling", danger: false,
                         run: () => { Files.select(e.path, "single"); win.suggesting = true; beginRename(e.path); Tidy.suggestName(e.path); } });
        items.push({ label: Tr.t("Copy"), icon: "edit-copy", danger: false, run: () => Files.toClipboard("copy", chosen) });
        items.push({ label: Tr.t("Cut"), icon: "edit-cut", danger: false, run: () => Files.toClipboard("cut", chosen) });
        if (chosen.length === 1 && Files.path.startsWith("/"))
            items.push({ label: Tr.t("Create Link"), icon: "insert-link", danger: false, run: () => win.askSymlink(chosen[0]) });
        if (e.isDir)
            items.push({ label: Tr.t("Paste into this folder"), icon: "edit-paste", danger: false, run: () => Files.pasteHere(e.path) });
        // a password: on a PDF (a PDF password), any other file or folder (gpg)
        if (Files.isGpg(e.path) || /\.(pdf|zip)$/i.test(e.path))
            items.push({ label: Tr.t("Unlock…"), icon: "changes-allow", danger: false, run: () => Files.askLock("unlock", e.path) });
        if (!Files.isGpg(e.path))
            items.push({ label: Tr.t("Lock with a password…"), icon: "changes-prevent", danger: false, run: () => Files.askLock("lock", e.path) });
        if (!e.isDir && Files.mountableImage(e.path))
            items.push({ label: Tr.t("Open as a drive"), icon: "media-optical", danger: false, run: () => Files.mountImage(e.path) });
        if (!e.isDir && Files.diskImage(e.path))
            items.push({ label: Tr.t("Write to a USB drive…"), icon: "drive-removable-media", danger: false, run: () => Files.openUsb("write", e.path) });
        for (const s of Files.scripts)
            items.push({ label: Tr.t("Script: %1", s.name), icon: "system-run", danger: false, run: () => Files.runScript(s, chosen) });
        items.push({ label: Tr.t("Copy to…"), icon: "edit-copy", danger: false, run: () => Files.copyTo = { mode: "copy", paths: chosen } });
        items.push({ label: Tr.t("Move to…"), icon: "go-jump", danger: false, run: () => Files.copyTo = { mode: "move", paths: chosen } });
        if (Files.isChecksumFile(e.path))
            items.push({ label: Tr.t("Test the checksums"), icon: "security-high", danger: false, run: () => Files.checkChecksums(e.path) });
        else
            items.push({ label: Tr.t("Make checksums (.sha256)"), icon: "security-high", danger: false, run: () => Files.makeChecksums(chosen) });
        if (chosen.length === 2)
            items.push({ label: Tr.t("Compare"), icon: "view-split-left-right", danger: false, run: () => Files.compare(chosen[0], chosen[1]) });
        if (chosen.length > 1)
            items.push({ label: Tr.t("Rename %1…", chosen.length), icon: "document-edit", danger: false, run: () => win.beginBatchRename(chosen) });
        if (e.isDir)
            items.push({ label: Tr.t("Open from your phone…"), icon: "phone", danger: false, run: () => win.serveAsk = e.path });
        if (e.path.startsWith("/") && !Files.asAdmin)
            items.push({ label: Tr.t("Open as administrator"), icon: "security-high", danger: false, run: () => Files.openAsAdmin(e.path, e.isDir) });
        if (e.isDir && e.path.startsWith(Files.home + "/"))
            items.push(Files.isShared(e.path)
                       ? { label: Tr.t("Stop sharing on the network"), icon: "folder-publicshare", danger: false, run: () => Files.setShared(e.path, false) }
                       : { label: Tr.t("Share on the network"), icon: "folder-publicshare", danger: false, run: () => Files.setShared(e.path, true) });
        if (e.isDir)
            items.push(Files.isBookmarked(e.path)
                       ? { label: Tr.t("Remove from the sidebar"), icon: "user-bookmarks", danger: false, run: () => Files.setBookmark(e.path, false) }
                       : { label: Tr.t("Add to the sidebar"), icon: "user-bookmarks", danger: false, run: () => Files.setBookmark(e.path, true) });
        items.push({ label: Tr.t("Properties"), icon: "document-properties", danger: false, run: () => Files.showProps(chosen) });
        items.push({ label: Tr.t("Duplicate"), icon: "edit-copy", danger: false, run: () => Files.duplicateEntry(e.path) });
        items.push({ label: Tr.t("Copy path"), icon: "edit-copy", danger: false, run: () => Files.copyPath(e.path) });
        items.push(Files.isStarred(e.path)
            ? { label: Tr.t("Unstar"), icon: "non-starred", danger: false, run: () => Files.setStar(chosen, false) }
            : { label: Tr.t("Star"), icon: "starred", danger: false, run: () => Files.setStar(chosen, true) });
        if (e.isDir)
            items.push({ label: Tr.t("Open in terminal"), icon: "utilities-terminal", danger: false, run: () => Files.openTerminal(e.path) });
        if (e.image)
            items.push({ label: Tr.t("Set as wallpaper"), icon: "preferences-desktop-wallpaper", danger: false, run: () => Files.setWallpaper(e.path) });
        items.push({ label: Tr.t("Share…"), icon: "folder-publicshare", danger: false, run: () => Share.open(e.path) });
        if (!e.isDir)
            items.push({ label: Tr.t("Send to phone"), icon: "phone", danger: false, run: () => PhoneTools.filesSend(e.path) });
        // the chosen files when this one is among them, else this one
        items.push({ label: Tr.t("Compress…"), icon: "package-x-generic", danger: false,
                     run: () => Archive.createAsk(Files.selected.indexOf(e.path) >= 0 ? Files.selected : [e.path]) });
        if (!e.isDir && Archive.types.indexOf((e.name.split(".").pop() || "").toLowerCase()) >= 0)
            items.push({ label: Tr.t("Extract here"), icon: "archive-extract", danger: false, run: () => Archive.extractHere(e.path) });
        items.push({ label: Tr.t("Move to trash"), icon: "edit-delete", danger: true, run: () => Files.trashEntries(chosen) });
        items.push({ label: Tr.t("Delete for good…"), icon: "edit-delete", danger: true, run: () => Files.deleteAsk = chosen });
        return items;
    }

    // shortcut: context-menu delete-for-good uses a menu item (not a ConfirmButton widget); keep hand-rolled path-keyed confirm
    property string confirmDelete: ""
    Timer { id: confirmTimer; interval: 4000; onTriggered: win.confirmDelete = "" }

    property var batchPaths: []
    property string batchCase: ""              // "", "lower", "upper", "title"
    property string batchFind: ""
    property string batchReplace: ""
    property bool batchRegex: false
    function batchRegexValid(pattern) {
        try { new RegExp(pattern, "g"); return true; } catch (err) { return false; }
    }
    readonly property bool batchRegexInvalid: win.batchRegex && win.batchFind !== "" && !win.batchRegexValid(win.batchFind)

    // one transform for the pattern, so the preview and the real rename agree
    function batchTransform(text) {
        let out = String(text || "");
        if (win.batchFind) {
            if (win.batchRegex && win.batchRegexValid(win.batchFind))
                out = out.replace(new RegExp(win.batchFind, "g"), win.batchReplace);
            else
                out = out.split(win.batchFind).join(win.batchReplace);
        }
        if (win.batchCase === "upper")
            out = out.toUpperCase();
        else if (win.batchCase === "lower")
            out = out.toLowerCase();
        else if (win.batchCase === "title") {
            let titled = "";
            let beginning = true;
            for (const ch of out) {
                if (/\s/.test(ch)) { titled += ch; beginning = true; }
                else if (/[A-Za-z]/.test(ch)) { titled += beginning ? ch.toUpperCase() : ch.toLowerCase(); beginning = false; }
                else titled += ch;                 // digits and punctuation do not end a word
            }
            out = titled;
        }
        return out;
    }
    function beginBatchRename(paths) {
        win.batchPaths = paths;
        batchField.text = Tr.t("Name") + " #";
        batchFindField.text = "";
        batchReplaceField.text = "";
        win.batchFind = "";
        win.batchReplace = "";
        win.batchCase = "";
        win.batchRegex = false;
        batchBox.visible = true;
        batchField.forceActiveFocus();
        batchField.selectAll();
    }
    function commitBatchRename(pattern) {
        if (win.batchRegexInvalid) { Files.error = Tr.t("That regular expression is not valid"); return; }
        batchBox.visible = false;
        Files.batchRename(win.batchTransform(pattern), win.batchPaths);
    }
    // what "Holiday #" makes of the chosen files, as files.py batch-rename will
    function batchPreview(pattern) {
        const newPattern = win.batchTransform(pattern);
        const w = String(win.batchPaths.length).length;
        return win.batchPaths.slice(0, 3).map((p, i) => {
            const base = FilePaths.baseName(p), dot = base.lastIndexOf(".");
            const num = String(i + 1).padStart(w, "0");
            return (newPattern.indexOf("#") >= 0 ? newPattern.split("#").join(num) : newPattern + " " + num).trim() + (dot > 0 ? base.slice(dot) : "");
        });
    }

    function beginRename(path) {
        const e = Files.entryFor(path);
        if (!e)
            return;
        renameField.text = e.name;
        renameBox.visible = true;
        renameField.forceActiveFocus();
        renameField.selectAll();
    }

    function commitRename() {
        const path = Files.selected.length === 1 ? Files.selected[0] : "";
        const name = renameField.text;
        renameBox.visible = false;
        if (!path || !Files.validName(name))
            return;
        Files.renameEntry(path, name);
    }

    function openNewFolder() {
        newFolderField.text = "";
        newFolderBox.visible = true;
        newFolderField.forceActiveFocus();
    }

    function commitNewFolder() {
        const name = newFolderField.text;
        newFolderBox.visible = false;
        if (!Files.validName(name))
            return;
        Files.makeFolder(name);
    }

    // ---- Save folder tree as text… (background menu): a native save picker -------
    property string treeSaveDir: ""
    function askSaveTree(dir) {
        treeSaveDir = dir;
        treeDlg.open();
    }
    // made on first use: a native dialog holds the shell while its D-Bus waits
    Loader {
        id: treeDlg
        active: false
        function open() { active = true; item.open(); }
        sourceComponent: FileDialog {
            title: Tr.t("Save folder tree as text…")
            fileMode: FileDialog.SaveFile
            currentFolder: "file://" + win.treeSaveDir
            selectedFile: "file://" + win.treeSaveDir.replace(/\/$/, "") + "/folder-tree.txt"
            nameFilters: [Tr.t("Text files") + " (*.txt)", Tr.t("All files") + " (*)"]
            onAccepted: {
                const path = selectedFile.toString().replace(/^file:\/\//, "");
                Files.saveTree(win.treeSaveDir, path);
                win.treeSaveDir = "";
            }
        }
    }
}
