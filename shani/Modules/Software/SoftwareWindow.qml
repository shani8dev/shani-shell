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
    property var installedApps: []
    property var leftovers: []
    property var appimages: []
    property bool busy: false
    Timer { id: removeTimer; interval: 4000; onTriggered: win.removing = "" }
    property string job: ""                   // the app a job runs for
    property real progress: -1
    property string jobLine: ""
    property string error: ""
    property string removing: ""
    readonly property int updates: installedApps.filter(a => a.update).length

    readonly property var categories: [["AudioVideo", Tr.t("Music and video")], ["Development", Tr.t("Developer tools")], ["Education", Tr.t("Learning")],
                                       ["Game", Tr.t("Games")], ["Graphics", Tr.t("Graphics")], ["Network", Tr.t("Internet")], ["Office", Tr.t("Office")],
                                       ["Science", Tr.t("Science")], ["System", Tr.t("System")], ["Utility", Tr.t("Utilities")]]

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
        if (!win.results.length) showCategory("Utility");
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
        win.showing = "search:" + words;
        ask(["search", words], r => { win.results = Array.isArray(r) ? r : []; Ui.softwareResults = win.results.map(a => a.id); });
    }
    function showCategory(c) {
        win.showing = "category:" + c;
        ask(["category", c], r => { win.results = Array.isArray(r) ? r : []; Ui.softwareResults = win.results.map(a => a.id); });
    }
    function openApp(id) { ask(["info", id], r => { if (r && !r.error) { win.app = r; Ui.softwareApp = r.id; } }); }
    function runJob(args, forId) {
        if (jobProc.running) return;
        win.error = ""; win.progress = 0; win.jobLine = ""; win.job = forId || "";
        jobProc.command = ["python3", win.tool].concat(args);
        jobProc.running = true;
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
        onExited: {
            win.progress = -1;
            win.job = "";
            win.start();
            if (win.app) win.openApp(win.app.id);
            if (win.tab === "leftovers") win.loadLeftovers();
        }
    }
    function loadLeftovers() { ask(["leftovers"], r => { win.leftovers = Array.isArray(r) ? r : []; Ui.softwareLeftovers = win.leftovers.map(l => l.id); }); }
    function loadAppImages() { ask(["appimages"], r => { win.appimages = Array.isArray(r) ? r : []; Ui.softwareAppImages = win.appimages.map(a => a.name + (a.added ? ":added" : "")); }); }
    function human(n) { return n >= 1073741824 ? (n / 1073741824).toFixed(1) + " GB" : n >= 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.round(n / 1024) + " KB"; }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(14)
        spacing: Theme.px(8)
        focus: true
        // Escape goes back to the list first, then closes the window: never traps
        Keys.onEscapePressed: { if (win.app !== null) win.app = null; else win.visible = false; }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: [["explore", Tr.t("Explore")], ["installed", win.updates ? Tr.t("Installed · %1 updates", win.updates) : Tr.t("Installed")],
                        ["leftovers", Tr.t("Leftovers")], ["appimages", Tr.t("AppImages")]]
                Choice {
                    required property var modelData
                    text: modelData[1]
                    selected: win.tab === modelData[0]
                    onClicked: { win.tab = modelData[0]; win.app = null; if (modelData[0] === "leftovers") win.loadLeftovers(); if (modelData[0] === "appimages") win.loadAppImages(); }
                }
            }
            Item { Layout.fillWidth: true }
            IconButton { icon: "view-refresh"; size: Theme.px(28); tip: Tr.t("Fetch Flathub's list again"); onClicked: win.runJob(["refresh"], "") }
        }
        // a job under way: how far, flatpak's own words
        ColumnLayout {
            visible: jobProc.running
            Layout.fillWidth: true
            spacing: 2
            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: win.jobLine || Tr.t("Working…"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(4)
                radius: Theme.px(2)
                color: Theme.alpha(Theme.text, 0.15)
                Accessible.role: Accessible.ProgressBar
                Rectangle { width: parent.width * Math.max(0, win.progress) / 100; height: parent.height; radius: parent.radius; color: Theme.accent }
            }
        }
        Text {
            visible: win.error !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            // bridge stderr is not user-facing copy: map the common failure
            text: /flatpak/.test(win.error) && /No such file|not found/.test(win.error)
                ? Tr.t("Flatpak isn't installed — install it to browse apps.")
                : /flatpak/.test(win.error) && /permission.*denied/i.test(win.error)
                ? Tr.t("Permission denied. Try running the software manager as Administrator.")
                : win.error
            color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }

        // ---- Explore: search, categories, results; an app's page over them ----
        RowLayout {
            visible: win.tab === "explore" && !win.app
            Layout.fillWidth: true
            TextField { id: q; Layout.fillWidth: true; placeholderText: Tr.t("Find apps on Flathub"); onAccepted: if (text.trim()) win.search(text.trim()) }
            Button { text: Tr.t("Find"); enabled: q.text.trim() !== ""; onClicked: win.search(q.text.trim()) }
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
            model: win.results
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
                        kind: "danger"
                        text: win.removing === appCol.a.id ? Tr.t("Click again to remove") : Tr.t("Remove")
                        enabled: !jobProc.running
                        onClicked: { if (win.removing === appCol.a.id) { win.removing = ""; removeTimer.stop(); win.runJob(["remove", appCol.a.id], appCol.a.id); } else { win.removing = appCol.a.id; removeTimer.restart(); } }
                    }
                    Button { visible: !appCol.a.installed; kind: "primary"; text: jobProc.running && win.job === appCol.a.id ? Tr.t("Installing…") : Tr.t("Install"); enabled: !jobProc.running; onClicked: win.runJob(["install", appCol.a.id], appCol.a.id) }
                }
                Image {
                    Layout.fillWidth: true
                    Layout.preferredHeight: status === Image.Ready ? Math.min(Theme.px(380), width * implicitHeight / Math.max(1, implicitWidth)) : 0
                    source: (appCol.a.screenshots || [])[0] || ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: appCol.a.description || ""
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                Text {
                    visible: !!appCol.a.homepage
                    text: Tr.t("Website: %1", appCol.a.homepage || "")
                    color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["xdg-open", appCol.a.homepage]) }
                }
            }
        }

        // ---- Installed ----
        RowLayout {
            visible: win.tab === "installed"
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: win.updates ? Tr.t("%1 apps can be updated", win.updates) : Tr.t("Everything is up to date"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
            Button { visible: win.updates > 0; kind: "primary"; text: Tr.t("Update all"); enabled: !jobProc.running; onClicked: win.runJob(["update-all"], "all") }
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
            model: win.installedApps
            delegate: RowLayout {
                id: irow
                required property var modelData
                width: ilist.width
                spacing: Theme.px(10)
                Image { Layout.preferredWidth: Theme.px(32); Layout.preferredHeight: Theme.px(32); source: irow.modelData.icon ? "file://" + irow.modelData.icon : ""; sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectFit }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: irow.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: [irow.modelData.version, irow.modelData.size, irow.modelData.installation === "user" ? Tr.t("just for you") : Tr.t("for everyone")].filter(x => x).join("  ·  "); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                }
                Button { visible: irow.modelData.update; text: Tr.t("Update"); enabled: !jobProc.running; onClicked: win.runJob(["update", irow.modelData.id], irow.modelData.id) }
                Button { text: Tr.t("Details"); flat: true; onClicked: { win.tab = "explore"; win.openApp(irow.modelData.id); } }
            }
        }

        // ---- Leftovers (Warehouse) ----
        Text {
            visible: win.tab === "leftovers"
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
                    visible: win.removingLeftover === lrow.modelData.id ? Tr.t("Click again to remove") : Tr.t("Move to the trash")
                    enabled: !jobProc.running
                    onClicked: { if (win.removingLeftover === lrow.modelData.id) { win.removingLeftover = ""; win.ask(["leftover-remove", lrow.modelData.id], () => win.loadLeftovers()); } else win.removingLeftover = lrow.modelData.id; }
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
    }
}
