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
        // Chronoa generates the app and writes it to ~/Developer/
        Chronoa.ask("Create a new desktop app for me. Description: " + description
            + "\n\nWrite the QML code to " + devDir + "/<app-name>/main.qml"
            + " and create a .desktop file in ~/.local/share/applications/ so it appears in the launcher."
            + " The app should use the qs.Common and qs.Services imports from the shani-shell framework.");
        // The actual generation happens through Chronoa's bridge
        // When Chronoa finishes, we refresh the list
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
}