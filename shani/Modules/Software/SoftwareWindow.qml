// Software (GNOME Software, Warehouse and Gear Lever's jobs, in Qt): Flathub's
// apps found by name or by kind, an app's page (what it does, who makes it, its
// licence, a screenshot) with Install / Open / Remove and progress; the apps you
// have, with their updates; what removed apps left in ~/.var/app; and AppImages
// added to the launcher. Everything is bridge/appstore.py over `flatpak`; a
// system-wide install asks the administrator's password in the shell's polkit agent.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Software"
    visible: Ui.software
    onGone: Ui.software = false
    implicitWidth: Theme.px(860)
    implicitHeight: Theme.px(680)

    readonly property string tool: Quickshell.env("SHANI_APPSTORE_TOOL") || "/usr/lib/shani-shell/appstore.py"
    property string tab: "explore"
    property var results: []
    property string showing: ""               // what the list shows: a search or a category
    property var app: null                    // the app whose page is open
    property var appPermissions: null         // Flatpak permissions for the open app
    property bool permsLoading: false
    property var installedApps: []
    property var leftovers: []
    property bool leftoversLoaded: false
    property var appimages: []
    property var featured: []
    property var remotes: []
    property bool busy: false
    Timer { id: removeTimer; interval: 4000; onTriggered: { win.removing = ""; win.removingLeftover = ""; } }
    Timer { id: confirmTimer; interval: 4000; onTriggered: win.confirmUpdateAll = false }
    property string job: ""                   // the app a job runs for
    property real progress: -1
    property string jobLine: ""
    property string error: ""
    property string removing: ""
    property string removingLeftover: ""
    readonly property int updates: installedApps.filter(a => a.update).length
    property bool confirmUpdateAll: false        // two-tap confirm, armed for a few seconds
    property var skippedIds: []                  // apps held back with "Skip this version"
    property string installedQuery: ""           // filter the Installed list
    property bool updatesOnly: false             // show only apps with an update
    property var catalogue: ({})                 // {refreshed, ageDays} from the bridge

    // ---- app-store additions: queue, history, search state, collections ------------
    property var jobQueue: []                    // pending {args, forId} jobs, run one at a time
    property string jobAction: ""                // the bridge verb of the running job (history label)
    property bool jobCancelled: false            // a cancelled job must not refresh or be logged
    property var jobHistory: []                  // this session's finished installs/updates/removes
    property var lastJob: null                   // {args, forId} of the last job, for Retry
    property bool jobFailed: false               // was the last job a failure (vs a read error)?
    property int searchGen: 0                    // ignore answers from a query the person already replaced
    property bool installedOnly: false           // filter Explore search results to installed apps
    property bool showAllReleases: false         // expand a long changelog on the app page
    readonly property var tabIds: ["explore", "installed", "leftovers", "appimages", "history", "repositories"]

    readonly property var categories: [["AudioVideo", Tr.t("Music and video")], ["Development", Tr.t("Developer tools")], ["Education", Tr.t("Learning")],
                                       ["Game", Tr.t("Games")], ["Graphics", Tr.t("Graphics")], ["Network", Tr.t("Internet")], ["Office", Tr.t("Office")],
                                       ["Science", Tr.t("Science")], ["System", Tr.t("System")], ["Utility", Tr.t("Utilities")]]
    // collections are unions of AppStream categories, fetched with the bridge's own
    // `category` command and merged here (no new bridge command, no new dependency)
    readonly property var collections: [[Tr.t("Creativity"), ["Graphics", "AudioVideo"]],
                                        [Tr.t("Productivity"), ["Office", "Development", "Education"]],
                                        [Tr.t("Play and learn"), ["Game", "Science"]]]

    onVisibleChanged: if (visible) start()
    Component.onCompleted: if (visible) start()
    // a .flatpakref opened with Software (a website's Install link): installed at once
    Connections { target: Ui; function onSoftwareRefChanged() { win.takeRef(); } }
    function takeRef() {
        if (!Ui.softwareRef) return;
        const p = Ui.softwareRef;
        Ui.softwareRef = "";
        win.tab = "installed";
        win.runJob(["install-ref", p], p.split("/").pop());
    }
    function start() {
        Qt.callLater(win.takeRef);
        ask(["installed"], r => { win.installedApps = Array.isArray(r) ? r : []; Ui.softwareInstalled = win.installedApps.map(a => a.id); });
        ask(["skipped"], r => { win.skippedIds = Array.isArray(r) ? r : []; });
        ask(["catalogue"], r => { win.catalogue = r && !r.error ? r : ({}); });
        if (!win.results.length) showCategory("Utility");
        win.loadFeatured();
    }
    // editorial picks (a fixed shortlist, plus catalogue fillers if absent)
    function loadFeatured() { ask(["featured"], r => { win.featured = Array.isArray(r) ? r : []; }); }
    function loadRemotes() { ask(["remotes"], r => { win.remotes = Array.isArray(r) ? r : []; }); }
    function onTabChanged(name) {
        if (name === "leftovers") win.loadLeftovers();
        if (name === "appimages") win.loadAppImages();
        if (name === "repositories") win.loadRemotes();
    }
    function gotoTab(i) {
        const id = win.tabIds[i];
        if (!id) return;
        win.tab = id; win.app = null; win.confirmUpdateAll = false; confirmTimer.stop();
        win.onTabChanged(id);
    }
    function toggleRemote(name, on) {
        win.ask(["remote-toggle", name, on ? "on" : "off"], () => win.loadRemotes());
    }
    // one question at a time (answers are JSON); a job streams its progress instead
    property var _queue: []
    function ask(args, cb) { win._queue = win._queue.concat([{ args: args, cb: cb }]); _next(); }
    function _next() {
        if (asker.running || !win._queue.length) return;
        asker.cb = win._queue[0].cb;
        asker.command = ["python3", win.tool].concat(win._queue[0].args);
        win._queue = win._queue.slice(1);
        asker.running = true;
    }
    Process {
        id: asker
        property var cb: null
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null;
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() }; }
                if (r && r.error) win.error = r.error;
                if (asker.cb) asker.cb(r);
                Qt.callLater(win._next);
            }
        }
    }
    function search(words) {
        win.error = "";
        const gen = ++win.searchGen;
        win.showing = "search:" + words;
        ask(["search", words], r => win.applyResults(gen, r));
    }
    // a slow answer from an earlier query must not replace what is on screen now
    function applyResults(gen, r) {
        if (gen !== win.searchGen) return false;
        win.results = Array.isArray(r) ? r : [];
        Ui.softwareResults = win.results.map(a => a.id);
        return true;
    }
    function filteredResults() {
        const all = Array.isArray(win.results) ? win.results : [];
        const out = win.installedOnly ? all.filter(a => a.installed) : all.slice();
        return out.sort((a, b) => String(a.name || "").localeCompare(String(b.name || "")));
    }
    // a collection is several categories merged into one list, de-duplicated by id
    function showCollection(name, cats) {
        win.error = "";
        win.showing = "collection:" + name;
        let left = cats.length;
        let merged = [];
        cats.forEach(c => ask(["category", c], r => {
            if (Array.isArray(r)) {
                const seen = new Set(merged.map(a => a.id));
                r.forEach(a => { if (!seen.has(a.id)) { merged.push(a); seen.add(a.id); } });
            }
            if (--left === 0) win.applyCollection(merged);
        }));
    }
    function applyCollection(merged) {
        win.results = merged;
        Ui.softwareResults = merged.map(a => a.id);
    }
    function clampIndex(i, count) { return count <= 0 ? -1 : Math.max(0, Math.min(count - 1, i)); }
    function showCategory(c) {
        win.error = "";
        win.showing = "category:" + c;
        ask(["category", c], r => { win.results = Array.isArray(r) ? r : []; Ui.softwareResults = win.results.map(a => a.id); });
    }
    function openApp(id) {
        win.error = "";
        win.showAllReleases = false;
        ask(["info", id], r => {
            if (r && !r.error) { win.app = r; Ui.softwareApp = r.id; win.loadPerms(id); }
        });
    }
    function loadPerms(id) {
        win.appPermissions = null;
        win.permsLoading = true;
        permsProc.command = ["sh", "-c",
            'flatpak info --show-permissions "$1" 2>/dev/null || echo "No permissions info"', "sh", id];
        permsProc.running = true;
    }
    Process {
        id: permsProc
        stdout: StdioCollector {
            onStreamFinished: {
                win.permsLoading = false;
                const lines = text.trim().split("\n").filter(l => l !== "" && l !== "No permissions info");
                const perms = [];
                for (const line of lines) {
                    const [key, ...rest] = line.split("=");
                    if (key && rest.length) perms.push({ key: key.trim(), value: rest.join("=").trim() });
                }
                win.appPermissions = perms;
            }
        }
        onExited: code => { win.permsLoading = false; if (code !== 0) win.appPermissions = []; }
    }
    // jobs queue up instead of being dropped while another install is running
    function runJob(args, forId) {
        win.jobQueue = win.jobQueue.concat([{ args: args, forId: forId || "" }]);
        win.startNextJob();
    }
    function startNextJob() {
        if (jobProc.running) return;
        if (!win.jobQueue.length) { win.progress = -1; win.job = ""; win.jobLine = ""; return; }
        const next = win.jobQueue[0];
        win.jobQueue = win.jobQueue.slice(1);
        win.error = ""; win.progress = 0; win.jobLine = "";
        win.job = next.forId; win.jobAction = next.args[0] || ""; win.jobCancelled = false;
        win.lastJob = { args: next.args, forId: next.forId };
        jobProc.command = ["python3", win.tool].concat(next.args);
        jobProc.running = true;
    }
    function cancelJob() {
        if (!jobProc.running) return;
        win.jobCancelled = true;
        jobProc.running = false;         // Quickshell's supported way to stop a Process
        win.jobQueue = [];               // abandon the whole batch, not just this job
        win.error = Tr.t("The operation was cancelled.");
        win.jobFailed = false;
        win.progress = -1; win.jobLine = ""; win.job = "";
    }
    function recordJob(code) {
        const verb = win.jobAction;
        const label = verb === "update-all" ? Tr.t("Update all")
            : verb === "refresh" ? Tr.t("Refresh catalogue")
            : verb === "install" || verb === "install-ref" ? Tr.t("Installed")
            : verb === "remove" ? Tr.t("Removed")
            : verb === "update" ? Tr.t("Updated") : Tr.t("Operation");
        win.jobHistory = [{ action: label, name: win.job || "", when: new Date().toLocaleTimeString(), ok: code === 0 }]
            .concat(win.jobHistory).slice(0, 50);
    }
    function friendlyError() {
        const e = win.error || "";
        if (/no space left|ENOSPC/i.test(e)) return Tr.t("Not enough free space to finish this operation.");
        if (!Net.online && /network|resolve|connect|temporary failure|unreachable/i.test(e)) return Tr.t("You are offline — reconnect and try again.");
        if (/flatpak/.test(e) && /No such file|not found/.test(e)) return Tr.t("Flatpak isn't installed — install it to browse apps.");
        if (/flatpak/.test(e) && /permission.*denied/i.test(e)) return Tr.t("Permission denied. Try running the software manager as Administrator.");
        if (/not an app id/i.test(e)) return Tr.t("That app could not be found in the catalogue.");
        return e;
    }
    function reloadCurrentView() {
        const s = win.showing || "";
        if (s.startsWith("search:")) win.search(s.slice(7));
        else if (s.startsWith("category:")) win.showCategory(s.slice(9));
        else if (s.startsWith("collection:")) {
            const name = s.slice(11);
            const c = win.collections.find(x => x[0] === name);
            if (c) win.showCollection(c[0], c[1]); else win.start();
        } else win.start();
    }
    function retry() {
        const last = win.lastJob;
        win.error = "";
        if (win.jobFailed && last) win.runJob(last.args, last.forId);
        else win.reloadCurrentView();
    }
    Process {
        id: jobProc
        stdout: SplitParser {
            onRead: line => {
                let r = {};
                try { r = JSON.parse(line); } catch (e) { return; }
                if (r.progress !== undefined && r.progress !== null) win.progress = r.progress;
                if (r.line) win.jobLine = r.line;
                if (r.error) win.error = r.error;
                if (r.ok) Ui.softwareDone = win.job + ":ok";
            }
        }
        onExited: code => {
            const cancelled = win.jobCancelled;
            win.jobFailed = !cancelled && code !== 0;
            if (!cancelled) {
                win.recordJob(code);
                win.start();
                if (win.app) win.openApp(win.app.id);
                if (win.tab === "leftovers") win.loadLeftovers();
            }
            win.progress = -1;
            win.job = "";
            Qt.callLater(win.startNextJob);
        }
    }
    function loadLeftovers() {
        win.leftoversLoaded = false;
        ask(["leftovers"], r => { win.leftovers = Array.isArray(r) ? r : []; win.leftoversLoaded = true; Ui.softwareLeftovers = win.leftovers.map(l => l.id); });
    }
    function loadAppImages() { ask(["appimages"], r => { win.appimages = Array.isArray(r) ? r : []; Ui.softwareAppImages = win.appimages.map(a => a.name + (a.added ? ":added" : "")); }); }
    // 1024-based sizes must be labelled KiB/MiB/GiB, not decimal KB/MB/GB
    function human(n) { return n >= 1073741824 ? (n / 1073741824).toFixed(1) + " GiB" : n >= 1048576 ? (n / 1048576).toFixed(1) + " MiB" : Math.round(n / 1024) + " KiB"; }
    // flatpak's size column, added up so "Update all" can say how big it is
    function bytesOf(s) {
        const m = /^([\d.]+)\s*([KMG]i?B|B)$/i.exec(String(s || "").trim());
        if (!m) return 0;
        const unit = m[2].toLowerCase().replace("ib", "b");
        return parseFloat(m[1]) * ({ b: 1, kb: 1024, mb: 1048576, gb: 1073741824 })[unit] || 0;
    }
    function updateSize() {
        let total = 0, known = 0;
        for (const a of installedApps) {
            const b = a.update ? win.bytesOf(a.size) : 0;
            if (b) { total += b; known++; }
        }
        return known > 0 && known === win.updates ? win.human(Math.round(total)) : "";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(14)
        spacing: Theme.px(8)
        focus: true
        // Escape goes back to the list first, then closes the window: never traps
        Keys.onEscapePressed: { if (win.app !== null) win.app = null; else win.visible = false; }
        // keyboard-first navigation: / searches, Ctrl+1..6 switch tabs,
        // Up/Down walk the results and Enter opens the highlighted app
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape || q.activeFocus || installedSearch.activeFocus) return;
            if (e.key === Qt.Key_Slash && win.tab === "explore" && !win.app) { q.forceActiveFocus(); e.accepted = true; return; }
            if ((e.modifiers & Qt.ControlModifier) && e.key >= Qt.Key_1 && e.key <= Qt.Key_6) { win.gotoTab(e.key - Qt.Key_1); e.accepted = true; return; }
            if (win.tab === "explore" && !win.app) {
                if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) {
                    grid.currentIndex = win.clampIndex(grid.currentIndex + (e.key === Qt.Key_Down ? 1 : -1), grid.count);
                    grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
                    e.accepted = true; return;
                }
                if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && grid.count > 0) {
                    const hit = win.filteredResults()[grid.currentIndex];
                    if (hit) win.openApp(hit.id);
                    e.accepted = true; return;
                }
            }
            if (win.tab === "installed") {
                if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) {
                    ilist.currentIndex = win.clampIndex(ilist.currentIndex + (e.key === Qt.Key_Down ? 1 : -1), ilist.count);
                    ilist.positionViewAtIndex(ilist.currentIndex, ListView.Contain);
                    e.accepted = true; return;
                }
                if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && ilist.count > 0) {
                    const row = ilist.currentItem;
                    if (row && row.modelData) { win.tab = "explore"; win.openApp(row.modelData.id); }
                    e.accepted = true; return;
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: [["explore", Tr.t("Explore")], ["installed", win.updates ? Tr.t("Installed · %1 updates", win.updates) : Tr.t("Installed")],
                        ["leftovers", Tr.t("Leftovers")], ["appimages", Tr.t("AppImages")],
                        ["history", Tr.t("History")], ["repositories", Tr.t("Repositories")]]
                Choice {
                    required property var modelData
                    text: modelData[1]
                    selected: win.tab === modelData[0]
                    Accessible.name: modelData[1]
                    onClicked: { win.tab = modelData[0]; win.app = null; win.confirmUpdateAll = false; confirmTimer.stop(); win.onTabChanged(modelData[0]); }
                }
            }
            Item { Layout.fillWidth: true }
            IconButton { icon: "view-refresh"; size: Theme.px(28); tip: Tr.t("Fetch Flathub's list again"); Accessible.name: Tr.t("Refresh the app catalogue"); onClicked: win.runJob(["refresh"], "") }
        }
        // the catalogue this window is showing, and when it was last fetched
        Rectangle {
            visible: !Net.online || (win.catalogue.ageDays !== null && win.catalogue.ageDays > 30)
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.px(32)
            radius: Theme.px(6)
            color: Theme.alpha(Theme.amber, 0.15)
            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(6)
                spacing: Theme.px(6)
                Text { text: "⚠"; color: Theme.amber; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: !Net.online
                        ? Tr.t("Offline — showing the catalogue saved on this device. Installing and updating need internet.")
                        : Tr.t("The app catalogue is %1 days old — refresh it for the latest apps.", win.catalogue.ageDays)
                    color: Theme.amber; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
        }
        Text {
            visible: !!win.catalogue.refreshed
            Layout.fillWidth: true
            text: Tr.t("Catalogue refreshed %1", win.catalogue.refreshed)
            color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
        }
        // a job under way: how far, flatpak's own words
        ColumnLayout {
            visible: jobProc.running || win.jobQueue.length > 0
            Layout.fillWidth: true
            spacing: 2
            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: win.jobLine || Tr.t("Working…"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Text {
                visible: win.jobQueue.length > 0
                Layout.fillWidth: true
                text: Tr.t("%1 queued", win.jobQueue.length)
                color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                Accessible.name: text
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(4)
                radius: Theme.px(2)
                color: Theme.alpha(Theme.text, 0.15)
                Accessible.role: Accessible.ProgressBar
                Accessible.name: Tr.t("Operation progress")
                Rectangle { width: parent.width * Math.max(0, win.progress) / 100; height: parent.height; radius: parent.radius; color: Theme.accent }
            }
            Button {
                visible: jobProc.running
                Layout.alignment: Qt.AlignRight
                flat: true
                text: Tr.t("Cancel")
                Accessible.name: Tr.t("Cancel the current operation")
                onClicked: win.cancelJob()
            }
        }
        Text {
            visible: win.error !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            // bridge stderr is not user-facing copy: friendlyError maps the common failures
            text: win.friendlyError()
            color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            Accessible.name: text
        }
        Button {
            visible: win.error !== "" && !/cancelled/.test(win.error)
            flat: true
            Layout.alignment: Qt.AlignRight
            text: Tr.t("Retry")
            Accessible.name: Tr.t("Try the operation again")
            onClicked: win.retry()
        }

        // ---- Explore: search, categories, results; an app's page over them ----
        Timer { id: liveSearch; interval: 450; onTriggered: if (q.text.trim().length >= 3) win.search(q.text.trim()) }
        RowLayout {
            visible: win.tab === "explore" && !win.app
            Layout.fillWidth: true
            TextField { id: q; Layout.fillWidth: true; placeholderText: Tr.t("Find apps on Flathub"); Accessible.name: Tr.t("Find apps on Flathub"); onTextChanged: liveSearch.restart(); onAccepted: if (text.trim()) { liveSearch.stop(); win.search(text.trim()) } }
            Button { text: Tr.t("Find"); enabled: q.text.trim() !== ""; Accessible.name: Tr.t("Search for apps"); onClicked: { liveSearch.stop(); win.search(q.text.trim()) } }
            IconButton { icon: "edit-clear-all"; size: Theme.px(24); tip: Tr.t("Clear the search"); visible: q.text !== ""; Accessible.name: Tr.t("Clear the search"); onClicked: { liveSearch.stop(); q.text = ""; win.results = []; win.showing = ""; q.forceActiveFocus() } }
        }
        Text {
            visible: win.tab === "explore" && !win.app && q.text.trim().length > 0 && q.text.trim().length < 3
            Layout.fillWidth: true
            text: Tr.t("Type at least 3 characters to search.")
            color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
            Accessible.name: text
        }
        RowLayout {
            visible: win.tab === "explore" && !win.app
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Choice { text: Tr.t("Installed only"); selected: win.installedOnly; Accessible.name: Tr.t("Show only installed results"); onClicked: win.installedOnly = !win.installedOnly }
            Item { Layout.fillWidth: true }
            Text {
                visible: win.results.length > 0
                text: Tr.t("%1 apps", win.filteredResults().length)
                color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                Accessible.name: text
            }
        }
        // ---- curated picks / collections / categories --------------------------------
        Text {
            visible: win.tab === "explore" && !win.app && win.featured.length > 0
            Layout.fillWidth: true
            text: Tr.t("Featured — hand-picked from Flathub")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
            font.weight: Font.DemiBold
        }
        Flow {
            visible: win.tab === "explore" && !win.app && win.featured.length > 0
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: win.featured
                Rectangle {
                    required property var modelData
                    width: Theme.px(190); height: Theme.px(56)
                    radius: Theme.px(8)
                    color: pickArea.containsMouse ? Theme.hover : Theme.card
                    MouseArea { id: pickArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.openApp(modelData.id) }
                    RowLayout {
                        anchors.fill: parent; anchors.margins: Theme.px(6); spacing: Theme.px(6)
                        Image { Layout.preferredWidth: Theme.px(32); Layout.preferredHeight: Theme.px(32); source: modelData.icon ? "file://" + modelData.icon : ""; fillMode: Image.PreserveAspectFit; asynchronous: true }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.DemiBold }
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.summary || ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(9) * Theme.fontScale }
                        }
                        Text { visible: modelData.installed; text: "✓"; color: Theme.accent; font.pixelSize: Theme.px(12) }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name + (modelData.installed ? " — " + Tr.t("installed") : "")
                    Accessible.onPressAction: win.openApp(modelData.id)
                }
            }
        }
        Text {
            visible: win.tab === "explore" && !win.app
            Layout.fillWidth: true
            text: Tr.t("Collections")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
            font.weight: Font.DemiBold
        }
        Flow {
            visible: win.tab === "explore" && !win.app
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: win.collections
                Choice {
                    required property var modelData
                    text: modelData[0]
                    selected: win.showing === "collection:" + modelData[0]
                    Accessible.name: Tr.t("Browse the %1 collection", modelData[0])
                    onClicked: win.showCollection(modelData[0], modelData[1])
                }
            }
        }
        Flow {
            visible: win.tab === "explore" && !win.app
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: win.categories
                Choice { required property var modelData; text: modelData[1]; selected: win.showing === "category:" + modelData[0]; onClicked: win.showCategory(modelData[0]) }
            }
        }
        Text {
            visible: win.tab === "explore" && !win.app && win.results.length === 0 && !asker.running
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Tr.t("Nothing here yet. If this is the first time, fetch Flathub's list with the refresh button.")
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        EmptyState {
            Layout.fillWidth: true
            visible: win.tab === "explore" && !win.app && win.results.length === 0 && asker.running
            icon: "preferences-system"
            title: Tr.t("Working…")
            subtitle: ""
        }
        Text {
            Layout.fillWidth: true
            visible: win.tab === "explore" && !win.app && win.results.length === 0 && !asker.running && win.showing.startsWith("search:")
            text: Tr.t("No matches for %1", win.showing.slice(7))
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        GridView {
            id: grid
            visible: win.tab === "explore" && !win.app
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: Math.floor(width / Math.max(1, Math.floor(width / Theme.px(260))))
            cellHeight: Theme.px(76)
            model: win.filteredResults()
            currentIndex: 0
            onCountChanged: grid.currentIndex = win.clampIndex(grid.currentIndex, grid.count)
            highlight: Rectangle { z: 2; color: "transparent"; border.width: 2; border.color: Theme.accent; radius: Theme.px(10); width: grid.cellWidth - Theme.px(6); height: grid.cellHeight - Theme.px(6) }
            delegate: Rectangle {
                id: card
                required property var modelData
                width: grid.cellWidth - Theme.px(6)
                height: grid.cellHeight - Theme.px(6)
                radius: Theme.px(10)
                color: cardArea.containsMouse ? Theme.hover : Theme.card
                MouseArea { id: cardArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.openApp(card.modelData.id) }
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(8)
                    spacing: Theme.px(10)
                    Image { Layout.preferredWidth: Theme.px(48); Layout.preferredHeight: Theme.px(48); source: card.modelData.icon ? "file://" + card.modelData.icon : ""; sourceSize: Qt.size(96, 96); fillMode: Image.PreserveAspectFit; asynchronous: true }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: card.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.DemiBold }
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap; text: card.modelData.summary; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    }
                    Text { visible: card.modelData.installed; text: "✓"; color: Theme.accent; font.pixelSize: Theme.px(14) }
                }
                Accessible.role: Accessible.Button
                Accessible.name: card.modelData.name
                Accessible.onPressAction: win.openApp(card.modelData.id)
            }
        }
        Text {
            visible: win.tab === "explore" && !win.app && win.results.length > 0 && win.filteredResults().length === 0
            Layout.fillWidth: true
            text: Tr.t("No installed apps in these results. Turn off Installed only.")
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            Accessible.name: text
        }
        // an app's page
        Flickable {
            visible: win.tab === "explore" && win.app !== null
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: appCol.implicitHeight
            ColumnLayout {
                id: appCol
                width: parent.width
                spacing: Theme.px(10)
                readonly property var a: win.app || ({})
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(12)
                    IconButton { icon: "go-previous"; size: Theme.px(28); tip: Tr.t("Back"); onClicked: win.app = null }
                    Image { Layout.preferredWidth: Theme.px(72); Layout.preferredHeight: Theme.px(72); source: appCol.a.icon ? "file://" + appCol.a.icon : ""; sourceSize: Qt.size(144, 144); fillMode: Image.PreserveAspectFit }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { text: appCol.a.name || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(18) * Theme.fontScale; font.weight: Font.DemiBold }
                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: appCol.a.summary || ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                        Text { text: [appCol.a.developer, appCol.a.license].filter(x => x).join("  ·  "); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    }
                    Button { visible: !!appCol.a.installed; text: Tr.t("Open"); onClicked: Quickshell.execDetached(["flatpak", "run", appCol.a.id]) }
                    Button {
                        visible: !!appCol.a.installed
                        kind: "danger"
                        text: win.removing === appCol.a.id ? Tr.t("Click again to remove") : Tr.t("Remove")
                        enabled: !jobProc.running
                        onClicked: { if (win.removing === appCol.a.id) { win.removing = ""; removeTimer.stop(); win.runJob(["remove", appCol.a.id], appCol.a.id); } else { win.removing = appCol.a.id; removeTimer.restart(); } }
                    }
                    Button { visible: !appCol.a.installed; kind: "primary"; text: jobProc.running && win.job === appCol.a.id ? Tr.t("Installing…") : Tr.t("Install"); enabled: !jobProc.running; onClicked: win.runJob(["install", appCol.a.id], appCol.a.id) }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(Theme.px(380), Theme.px(220))
                    visible: (appCol.a.screenshots || []).length > 0
                    orientation: ListView.Horizontal
                    clip: true
                    spacing: Theme.px(8)
                    model: appCol.a.screenshots || []
                    delegate: Image {
                        required property var modelData
                        width: Math.min(Theme.px(560), ListView.view.width - Theme.px(40))
                        height: ListView.view.height
                        source: modelData
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: appCol.a.description || ""
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                // ODRS community rating, shown only where the service has reviews
                Text {
                    Layout.fillWidth: true
                    visible: (appCol.a.ratingCount || 0) > 0
                    text: "★ " + (appCol.a.rating || 0).toFixed(1) + " · " + Tr.t("%1 ratings", appCol.a.ratingCount)
                    color: Theme.amber; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                    Accessible.name: text
                }
                Text {
                    Layout.fillWidth: true
                    visible: (appCol.a.ratingCount || 0) > 0
                    text: "★".repeat(Math.min(5, Math.max(0, Math.round(appCol.a.rating || 0)))) + "☆".repeat(5 - Math.min(5, Math.max(0, Math.round(appCol.a.rating || 0))))
                    color: Theme.amber; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.name: Tr.t("%1 out of 5 stars", appCol.a.rating || 0)
                }
                Text {
                    Layout.fillWidth: true
                    visible: (appCol.a.ratingCount || 0) === 0
                    text: Tr.t("No ratings yet — community reviews come from ODRS.")
                    color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.name: text
                }
                Repeater {
                    model: (appCol.a.reviews || []).slice(0, 3)
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; text: "★".repeat(Math.max(1, Math.round(modelData.rating || 3))) + "  " + (modelData.summary || ""); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: modelData.review || ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: appCol.a.ageDays > 730
                    text: Tr.t("No new release in %1 days — this app may no longer be maintained.", appCol.a.ageDays)
                    color: Theme.amber; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; wrapMode: Text.Wrap
                }
                // version history / per-release changelog
                Text {
                    Layout.fillWidth: true
                    visible: (appCol.a.releases || []).length > 0
                    text: Tr.t("Version history")
                    color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; font.weight: Font.DemiBold
                }
                Repeater {
                    model: win.showAllReleases ? (appCol.a.releases || []) : (appCol.a.releases || []).slice(0, 5)
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; text: (modelData.version || "?") + (modelData.timestamp ? "  ·  " + modelData.timestamp.slice(0, 10) : ""); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.DemiBold }
                        Text { Layout.fillWidth: true; visible: !!modelData.notes; text: modelData.notes || ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale; wrapMode: Text.WordWrap; maximumLineCount: 5; elide: Text.ElideRight }
                    }
                }
                Button {
                    visible: (appCol.a.releases || []).length > 5
                    flat: true
                    text: win.showAllReleases ? Tr.t("Show fewer versions") : Tr.t("Show all %1 versions", (appCol.a.releases || []).length)
                    Accessible.name: text
                    onClicked: win.showAllReleases = !win.showAllReleases
                }
                // add-ons / extensions that extend this app
                Text {
                    Layout.fillWidth: true
                    visible: (appCol.a.addons || []).length > 0
                    text: Tr.t("Add-ons")
                    color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; font.weight: Font.DemiBold
                }
                Flow {
                    Layout.fillWidth: true
                    visible: (appCol.a.addons || []).length > 0
                    spacing: Theme.px(6)
                    Repeater {
                        model: appCol.a.addons || []
                        Choice { required property var modelData; text: modelData.name; onClicked: win.openApp(modelData.id) }
                    }
                }
                Text {
                    visible: !!appCol.a.homepage
                    text: Tr.t("Website: %1", appCol.a.homepage || "")
                    color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["xdg-open", appCol.a.homepage]) }
                }
                // ---- permissions (Flatpak apps) ----
                Text {
                    visible: !win.permsLoading && win.appPermissions !== null && win.appPermissions.length > 0
                    text: Tr.t("Permissions")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Repeater {
                    model: !win.permsLoading && win.appPermissions !== null ? win.appPermissions : []
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Theme.px(8)
                        Text { text: modelData.key; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale; Layout.preferredWidth: Theme.px(120) }
                        Text { text: modelData.value; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }
                Text {
                    visible: !win.permsLoading && win.appPermissions !== null && win.appPermissions.length === 0
                    text: Tr.t("This app declares no special permissions.")
                    color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.name: text
                }
                Text {
                    visible: win.permsLoading
                    text: Tr.t("Reading permissions…")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
        }

        // ---- Installed ----
        RowLayout {
            visible: win.tab === "installed"
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: win.updates ? Tr.t("%1 apps can be updated", win.updates) : Tr.t("Everything is up to date"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
            Button {
                visible: win.updates > 0
                kind: win.confirmUpdateAll ? "danger" : "primary"
                text: win.confirmUpdateAll ? Tr.t("Click again to update all") : Tr.t("Update all")
                enabled: !jobProc.running
                onClicked: {
                    if (win.confirmUpdateAll) { win.confirmUpdateAll = false; win.runJob(["update-all"], "all"); }
                    else { win.confirmUpdateAll = true; confirmTimer.restart(); }
                }
            }
        }
        RowLayout {
            visible: win.tab === "installed"
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField {
                id: installedSearch
                Layout.fillWidth: true
                placeholder: Tr.t("Find installed apps…")
                Accessible.name: Tr.t("Find installed apps…")
                text: win.installedQuery
                onTextChanged: win.installedQuery = text
            }
            Choice {
                text: Tr.t("Updates only")
                selected: win.updatesOnly
                onClicked: win.updatesOnly = !win.updatesOnly
            }
        }
        Rectangle {
            visible: win.confirmUpdateAll && win.updates > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.px(80)
            radius: Theme.px(6)
            color: Theme.alpha(Theme.danger, 0.12)
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(8)
                spacing: 2
                Text { Layout.fillWidth: true; text: Tr.t("Update %1 apps:", win.updates); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; font.weight: Font.DemiBold }
                Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: installedApps.filter(a => a.update).map(a => a.name).join(", "); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Text { Layout.fillWidth: true; visible: win.updateSize() !== ""; text: Tr.t("Total size: %1", win.updateSize()); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            }
        }
        ListView {
            reuseItems: true
            cacheBuffer: 400
            id: ilist
            visible: win.tab === "installed"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            currentIndex: 0
            onCountChanged: ilist.currentIndex = win.clampIndex(ilist.currentIndex, ilist.count)
            highlight: Rectangle { z: 2; color: "transparent"; border.width: 2; border.color: Theme.accent; radius: Theme.px(6); width: ilist.width; height: ilist.currentItem ? ilist.currentItem.height : 0 }
            model: win.installedApps.filter(a =>
                (!win.updatesOnly || a.update) &&
                (!win.installedQuery ||
                 String(a.name || a.id || "").toLowerCase().includes(win.installedQuery.toLowerCase()) ||
                 String(a.id || "").toLowerCase().includes(win.installedQuery.toLowerCase())))
            delegate: RowLayout {
                id: irow
                required property var modelData
                width: ilist.width
                spacing: Theme.px(10)
                Accessible.role: Accessible.ListItem
                Accessible.name: irow.modelData.name + (irow.modelData.update ? " — " + Tr.t("update available") : "")
                Image { Layout.preferredWidth: Theme.px(32); Layout.preferredHeight: Theme.px(32); source: irow.modelData.icon ? "file://" + irow.modelData.icon : ""; sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectFit }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: irow.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: [irow.modelData.version, irow.modelData.size, irow.modelData.installation === "user" ? Tr.t("just for you") : Tr.t("for everyone")].filter(x => x).join("  ·  "); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                }
                Button { visible: irow.modelData.update; text: Tr.t("Update"); enabled: !jobProc.running; onClicked: win.runJob(["update", irow.modelData.id], irow.modelData.id) }
                Button {
                    visible: irow.modelData.update || win.skippedIds.indexOf(irow.modelData.id) >= 0
                    flat: true
                    enabled: !jobProc.running
                    text: win.skippedIds.indexOf(irow.modelData.id) >= 0 ? Tr.t("Resume updates") : Tr.t("Skip this version")
                    onClicked: win.ask(["skip", irow.modelData.id, win.skippedIds.indexOf(irow.modelData.id) >= 0 ? "off" : "on"], () => win.start())
                }
                Button { text: Tr.t("Details"); flat: true; onClicked: { win.tab = "explore"; win.openApp(irow.modelData.id); } }
            }
            EmptyState {
                anchors.centerIn: parent
                visible: ilist.count === 0
                icon: "applications-other"
                title: win.installedQuery || win.updatesOnly ? Tr.t("No apps match your filter") : Tr.t("No apps installed yet")
                subtitle: win.installedQuery || win.updatesOnly ? Tr.t("Try a different name or turn off Updates only.") : Tr.t("Find apps in Explore and install one.")
            }
        }

        // ---- Leftovers (Warehouse) ----
        Text {
            visible: win.tab === "leftovers" && (win.leftoversLoaded || win.leftovers.length > 0)
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: win.leftovers.length ? Tr.t("What apps you removed left behind in your home folder (their settings and data):") : Tr.t("Removed apps left nothing behind.")
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        ListView {
            reuseItems: true
            cacheBuffer: 400
            id: llist
            visible: win.tab === "leftovers"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: win.leftovers
            delegate: RowLayout {
                id: lrow
                required property var modelData
                width: llist.width
                Text { Layout.fillWidth: true; elide: Text.ElideMiddle; text: lrow.modelData.id + "  ·  " + win.human(lrow.modelData.size); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Button {
                    text: win.removingLeftover === lrow.modelData.id ? Tr.t("Click again to remove") : Tr.t("Move to the trash")
                    enabled: !jobProc.running
                    onClicked: { if (win.removingLeftover === lrow.modelData.id) { win.removingLeftover = ""; removeTimer.stop(); win.ask(["leftover-remove", lrow.modelData.id], () => win.loadLeftovers()); } else { win.removingLeftover = lrow.modelData.id; removeTimer.restart(); } }
                }
            }
        }

        // ---- AppImages (Gear Lever) ----
        RowLayout {
            visible: win.tab === "appimages"
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Tr.t("AppImages in ~/Applications; added ones are in the launcher."); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
            Button { text: Tr.t("Add an AppImage…"); onClicked: FilePicker.open({ mode: "open", title: Tr.t("An AppImage"), onPicked: paths => { if (paths.length) win.ask(["appimage-add", paths[0]], () => win.loadAppImages()); } }) }
        }
        ListView {
            reuseItems: true
            cacheBuffer: 400
            id: alist
            visible: win.tab === "appimages"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: win.appimages
            delegate: RowLayout {
                id: arow
                required property var modelData
                width: alist.width
                Text { Layout.fillWidth: true; elide: Text.ElideMiddle; text: arow.modelData.name + (arow.modelData.added ? "  ·  " + Tr.t("in the launcher") : ""); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Button { visible: !arow.modelData.added; text: Tr.t("Add to the launcher"); onClicked: win.ask(["appimage-add", arow.modelData.path], () => win.loadAppImages()) }
                Button {
                    kind: "danger"
                    text: win.removing === arow.modelData.path ? Tr.t("Click again to remove") : Tr.t("Remove")
                    onClicked: { if (win.removing === arow.modelData.path) { win.removing = ""; removeTimer.stop(); win.ask(["appimage-remove", arow.modelData.path], () => win.loadAppImages()); } else { win.removing = arow.modelData.path; removeTimer.restart(); } }
                }
            }
        }

        // ---- History (this session's installs / updates / removes) --------------------
        RowLayout {
            visible: win.tab === "history"
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Tr.t("Apps installed, updated or removed in this session."); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
            Button { flat: true; text: Tr.t("Clear history"); enabled: win.jobHistory.length > 0; Accessible.name: Tr.t("Clear the session history"); onClicked: win.jobHistory = [] }
        }
        ListView {
            id: historyList
            visible: win.tab === "history"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: win.jobHistory
            delegate: RowLayout {
                required property var modelData
                width: historyList.width
                spacing: Theme.px(8)
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.action + " " + modelData.name + " " + modelData.when
                Text { text: modelData.ok ? "✓" : "✗"; color: modelData.ok ? Theme.accent : Theme.danger; font.pixelSize: Theme.px(13) }
                Text { Layout.preferredWidth: Theme.px(110); elide: Text.ElideRight; text: modelData.action; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Text { Layout.fillWidth: true; elide: Text.ElideMiddle; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Text { text: modelData.when; color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
            }
            EmptyState {
                anchors.centerIn: parent
                visible: historyList.count === 0
                icon: "view-refresh"
                title: Tr.t("No activity yet")
                subtitle: Tr.t("Installs, updates and removals appear here while Software is open.")
            }
        }

        // ---- Repositories (Flatpak remotes) -----------------------------------------
        Text {
            visible: win.tab === "repositories"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Tr.t("A disabled repository is kept but its apps are not offered or updated.")
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        ListView {
            id: remoteList
            visible: win.tab === "repositories"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: win.remotes
            delegate: RowLayout {
                required property var modelData
                width: remoteList.width
                spacing: Theme.px(8)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                    Text { Layout.fillWidth: true; elide: Text.ElideMiddle; text: modelData.url; color: Theme.faint; font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale }
                }
                Button { text: modelData.disabled ? Tr.t("Enable") : Tr.t("Disable"); flat: true; onClicked: win.toggleRemote(modelData.name, modelData.disabled) }
            }
            EmptyState {
                anchors.centerIn: parent
                visible: remoteList.count === 0
                icon: "network-server"
                title: Tr.t("No repositories")
                subtitle: Tr.t("Flatpak has no remotes configured")
            }
        }
    }
}
