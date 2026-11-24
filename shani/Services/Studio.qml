pragma Singleton
// Studio: the AI app builder — describe what you want and Chronoa generates
// a QML app. Each generated app is saved to ~/Developer/<name>/ with a
// .desktop file in ~/.local/share/applications/ so it appears in the launcher.
// The user can open the generated code in TextEditor, run it, or delete it.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    // generated apps: [{ name, path, qmlPath, desktopPath, createdAt }]
    property var apps: []
    property bool busy: false
    property string lastOutput: ""

    readonly property string devDir: Quickshell.env("XDG_DEVELOPER_DIR") || (Quickshell.env("HOME") + "/Developer")

    function refresh() {
        scan.running = true;
    }

    // scan ~/Developer/ for generated apps
    Process {
        id: scan
        command: ["sh", "-c", 'd="$1"; [ -d "$d" ] || exit 0; find "$d" -name "*.qml" -path "*/main.qml" -o -name "*.desktop" -path "*/applications/*" 2>/dev/null | head -50', "sh", root.devDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l !== "");
                const apps = [];
                for (const line of lines) {
                    if (line.endsWith(".qml")) {
                        const path = line.replace(/\/main\.qml$/, "");
                        const name = path.split("/").pop();
                        apps.push({ name: name, path: path, qmlPath: line, desktopPath: "", createdAt: 0 });
                    }
                }
                root.apps = apps;
            }
        }
    }

    // ask Chronoa to generate an app
    function generate(description) {
        if (String(description || "").trim() === "") return;
        busy = true;
        lastOutput = "";
        recordAction("generate", String(description).trim());
        // Chronoa generates the app and writes it to ~/Developer/
        Chronoa.ask("Create a new desktop app for me. Description: " + description
            + "\n\nWrite the QML code to " + devDir + "/<app-name>/main.qml"
            + " and create a .desktop file in ~/.local/share/applications/ so it appears in the launcher."
            + " The app should use the qs.Common and qs.Services imports from the shani-shell framework.");
        // The actual generation happens through Chronoa's bridge. Clear the
        // busy flag when its turn ends, otherwise Generate stays disabled
        // and "Working…" is permanent.
    }
    Connections {
        target: Chronoa
        function onBusyChanged() {
            if (!Chronoa.busy && root.busy) {
                root.busy = false;
                root.refresh();
            }
        }
    }

    // open a generated app's code in TextEditor
    function openCode(app) {
        if (!app || !app.qmlPath) return;
        Ui.closeAll();
        Ui.textEditor = true;
        TextDocs.open(app.qmlPath);
    }

    // run a generated app (launch it via its .desktop file)
    function runApp(app) {
        if (!app) return;
        if (app.desktopPath && Quickshell.env("SHANI_DESKTOP_ENTRY")) {
            Quickshell.execDetached(["gio", "launch", app.desktopPath]);
        } else if (app.qmlPath) {
            // run with qs
            Quickshell.execDetached(["qs", "-p", app.qmlPath]);
        }
    }

    // delete a generated app
    function deleteApp(app) {
        if (!app || !app.path) return;
        Quickshell.execDetached(["sh", "-c", 'rm -rf "$1"', "sh", app.path]);
        if (app.desktopPath)
            Quickshell.execDetached(["sh", "-c", 'rm -f "$1"', "sh", app.desktopPath]);
        Qt.callLater(root.refresh);
    }

    // ---- creator studio: templates, wizard, search, export, tail, widgets ----

    // the four starting points offered next to Generate
    property var templates: [
        { id: "console-app", name: Tr.t("Console app"), description: Tr.t("A terminal app that prints and reads lines of text") },
        { id: "log-viewer", name: Tr.t("Log viewer"), description: Tr.t("A window that tails a log file and filters it by level") },
        { id: "status-board", name: Tr.t("Status board"), description: Tr.t("A compact board of statuses, counts and small numbers") },
        { id: "server-monitor", name: Tr.t("Server monitor"), description: Tr.t("A panel that polls a server and shows health over time") },
    ]
    function templateDescription(id) {
        const t = templates.find(x => x.id === String(id));
        return t ? t.description : "";
    }
    // Generate from a template: the description fills the box, Generate does the rest
    function generateFromTemplate(id) {
        const d = String(templateDescription(id)).trim();
        if (d !== "") generate(d);
    }

    // multi-file projects: a wizard for the files after the first
    property bool wizardActive: false
    property string wizardName: ""
    property var wizardFiles: []
    property int wizardStep: 0
    function startWizard(name, files) {
        wizardActive = true;
        wizardName = name;
        wizardFiles = Array.isArray(files) ? files : [];
        wizardStep = 0;
    }
    function wizardCount() { return wizardFiles.length; }
    function wizardNext() { if (wizardStep < wizardFiles.length) wizardStep++; }
    function wizardPrev() { if (wizardStep > 0) wizardStep--; }
    function wizardFinish() { wizardActive = false; wizardName = ""; wizardStep = 0; wizardFiles = []; }

    // search (case-insensitive over name and path) and sorting of the app list
    property string searchText: ""
    property string sortBy: "name"
    function search(q) {
        const needle = String(q === undefined ? root.searchText : q).trim().toLowerCase();
        let list = root.apps.slice();
        list.sort((a, b) => root.sortBy === "createdAt"
            ? (a.createdAt || 0) - (b.createdAt || 0)
            : String(a.name).localeCompare(String(b.name)));
        if (needle !== "")
            list = list.filter(a => (String(a.name) + " " + String(a.path)).toLowerCase().indexOf(needle) >= 0);
        return list;
    }
    function sortApps(key) {
        sortBy = key;
        root.apps = root.apps.slice().sort((a, b) => root.sortBy === "createdAt"
            ? (a.createdAt || 0) - (b.createdAt || 0)
            : String(a.name).localeCompare(String(b.name)));
    }

    // export an app's folder to a path (Export)
    function exportApp(app, path) {
        if (!app || !app.path || !String(path).trim()) return;
        Quickshell.execDetached(["sh", "-c", 'src="$1"; dst="$2"; [ -d "$src" ] && cp -r "$src" "$dst/" 2>/dev/null',
                                 "sh", app.path, String(path).trim()]);
    }

    // ask Chronoa for a run script for an app
    function generateScript(app) {
        if (!app || !app.path) return;
        Chronoa.ask("Write a run script for the app at " + app.path
            + ": create run.sh there that runs it with qs -p " + app.qmlPath);
    }

    // code preview: read the app's main.qml
    property string previewPath: ""
    property string previewText: ""
    Process {
        id: previewProc
        property string qmlPath
        command: ["cat", previewProc.qmlPath]
        stdout: StdioCollector {
            onStreamFinished: {
                root.previewPath = previewProc.qmlPath;
                root.previewText = text;
            }
        }
    }
    function preview(app) {
        if (!app || !app.qmlPath) return;
        previewProc.qmlPath = app.qmlPath;
        previewProc.running = true;
    }

    // syntax check: qmllint on the app's main.qml
    property var lastLint: ({ ok: true, errors: "" })
    Process {
        id: lintProc
        property string qmlPath
        command: ["qmllint", lintProc.qmlPath]
        stdout: StdioCollector {
            onStreamFinished: {
                root.lastLint = { ok: lintProc.exitCode === 0, errors: text };
            }
        }
    }
    function lintApp(app) {
        if (!app || !app.qmlPath) return;
        lintProc.qmlPath = app.qmlPath;
        lintProc.running = true;
    }

    // live feed tailing: follow the logs of an app
    property string tailText: ""
    property bool tailing: false
    Process {
        id: tailProc
        property string appPath
        command: ["sh", "-c", 'd="$1"; cd "$d" 2>/dev/null; tail -F -n 20 *.log 2>/dev/null || tail -F -n 20 * 2>/dev/null', "sh", tailProc.appPath]
        stdout: StdioCollector {
            onStreamFinished: { if (tailProc.running && root.tailing) root.tailText = (root.tailText + text).slice(-2000); }
        }
        onExited: root.tailing = false;
    }
    function tailApp(app) {
        if (!app || !app.path) return;
        if (tailProc.running) tailProc.running = false;
        tailProc.appPath = app.path;
        root.tailText = "";
        root.tailing = true;
        tailProc.running = true;
    }
    function stopTail() { tailProc.running = false; root.tailing = false; }

    // dashboard widgets: what a project may add, and what it added
    property var widgetTypes: ["stat", "graph", "log", "button"]
    property var widgets: []
    function addWidget(app, type) {
        if (!app) return;
        const t = String(type).trim();
        if (widgetTypes.indexOf(t) < 0) return;
        root.widgets = root.widgets.concat({ id: root.widgets.length + 1, app: app.name, type: t });
        root.recordAction("widget", app.name + ": " + t);
    }

    // recent actions, undo and redo of them
    property var recentActions: []
    property int actionIndex: -1
    property var undone: []
    function recordAction(type, name) {
        root.recentActions = root.recentActions.slice(0, root.actionIndex + 1)
            .concat({ type: type, name: name, ts: Date.now() });
        root.actionIndex = root.recentActions.length - 1;
        root.undone = [];
    }
    function undoLast() {
        if (root.actionIndex < 0) return null;
        const a = root.recentActions[root.actionIndex];
        root.actionIndex--;
        root.undone = root.undone.concat(a);
        // a widget added can be removed again
        if (a.type === "widget" && root.widgets.length > 0)
            root.widgets = root.widgets.slice(0, -1);
        return a;
    }
    function redoLast() {
        if (root.undone.length === 0) return null;
        const a = root.undone.pop();
        root.recentActions = root.recentActions.slice(0, root.actionIndex + 1).concat(a);
        root.actionIndex = root.recentActions.length - 1;
        return a;
    }
}
