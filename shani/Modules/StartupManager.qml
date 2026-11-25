// Startup manager (Modules/StartupManager.qml): the XDG autostart apps of both
// ~/.config/autostart and /etc/xdg/autostart, in a window of its own. One fixed
// Python script does the reading and the edits: the folder, the action and the
// app's details go in as argv (JSON for structured data), never as shell text.
// A system entry turned off gets a Hidden=true copy in the user's folder — the
// XDG way to override one you cannot edit — and turns back on by dropping it.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common

AppWindow {
    id: win
    appName: "Startup manager"
    visible: Ui.startupManager
    onGone: Ui.startupManager = false
    implicitWidth: Theme.px(700)
    implicitHeight: Theme.px(620)
    shortcutRefresh: win.refresh   // Ctrl+R reloads the autostart list; Ctrl+F is N/A (no filter field)
    // refresh lives in AppWindow's tools row, not a second toolbar

    readonly property string pyCode: `
import os, sys, json, shutil
user, mode, arg = sys.argv[1], sys.argv[2], sys.argv[3]
system = "/etc/xdg/autostart"
def fields(path):
    d = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("[") or "=" not in line: continue
                k, v = line.split("=", 1)
                d[k.strip().lower()] = v.strip()
    except Exception:
        pass
    return d
def safe(name):
    return name.endswith(".desktop") and name != ".desktop" and "/" not in name and ".." not in name
def emit(obj):
    print(json.dumps(obj, default=str))
def attempt(fn, fallback=None):
    try:
        return fn()
    except Exception as e:
        return fallback
if mode == "list":
    found = {}
    for folder, mine in ((user, True), (system, False)):
        names = attempt(lambda: sorted(n for n in os.listdir(folder) if n.endswith(".desktop")), [])
        for n in names:
            if n in found: continue
            d = fields(os.path.join(folder, n))
            if not d.get("name") and not d.get("exec"): continue
            hidden = d.get("hidden", "false").lower() == "true" or d.get("x-gnome-autostart-enabled", "true").lower() == "false"
            found[n] = {"file": n, "name": d.get("name") or n[:-8], "desc": d.get("comment") or "", "on": not hidden, "mine": mine}
    emit({"entries": sorted(found.values(), key=lambda e: e["name"].lower())})
elif mode == "set":
    o = attempt(lambda: json.loads(arg), {})
    f = o.get("file", "")
    if not safe(f): emit({"error": "Invalid desktop file"}); sys.exit(0)
    p = os.path.join(user, f)
    if not os.path.isfile(p):
        s = os.path.join(system, f)
        if not os.path.isfile(s): emit({"error": "Not found"}); sys.exit(0)
        os.makedirs(user, exist_ok=True); shutil.copyfile(s, p)
    def do_set():
        with open(p, encoding="utf-8", errors="replace") as fh:
            lines = [l for l in fh if not l.strip().lower().startswith(("hidden=", "x-gnome-autostart-enabled="))]
        if not o.get("on"): lines.append("Hidden=true\n")
        with open(p, "w", encoding="utf-8") as fh: fh.writelines(lines)
        emit({"ok": True})
        return True
    if attempt(do_set) is None: emit({"error": "Could not write the desktop file"})
elif mode == "add":
    o = attempt(lambda: json.loads(arg), {})
    ident, path, base, src = o.get("id", ""), o.get("path", ""), "", ""
    if ident:
        if not all(c.isalnum() or c in "._-" for c in ident): emit({"error": "Invalid app id"}); sys.exit(0)
        base = ident + ".desktop"
        dirs = [os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local/share")] + (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
        for d in dirs:
            cand = os.path.join(d, "applications", base)
            if os.path.isfile(cand): src = cand; break
        if not src: emit({"error": "Desktop file not found"}); sys.exit(0)
    elif path:
        if not path.endswith(".desktop") or not os.path.isfile(path): emit({"error": "Choose a .desktop file"}); sys.exit(0)
        base, src = os.path.basename(path), path
    else:
        emit({"error": "Pick an app first"}); sys.exit(0)
    if not safe(base): emit({"error": "Invalid desktop file"}); sys.exit(0)
    def do_add():
        os.makedirs(user, exist_ok=True)
        shutil.copyfile(src, os.path.join(user, base))
        emit({"ok": True})
    attempt(do_add)
elif mode == "remove":
    if not safe(arg): emit({"error": "Invalid desktop file"}); sys.exit(0)
    def do_remove():
        p = os.path.join(user, arg)
        if os.path.isfile(p): os.remove(p)
        emit({"ok": True})
    attempt(do_remove)
else:
    emit({"error": "Unknown action"})
`
    readonly property string userDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/autostart"

    property var entries: []
    property string pickedId: ""
    property string filePath: ""
    property string error: ""
    property string note: ""
    property string confirmFile: ""
    readonly property var confirming: win.entries.find(e => e.file === win.confirmFile) || null
    Timer { id: noteTimer; interval: 6000; onTriggered: win.note = "" }

    function refresh() {
        win.error = ""; win.confirmFile = "";
        lister.command = ["python3", "-c", win.pyCode, win.userDir, "list", ""];
        lister.running = true;
    }
    function write(mode, arg, note) {
        if (writer.running) return;
        win.error = "";
        writer.note = note || "";
        writer.command = ["python3", "-c", win.pyCode, win.userDir, mode, arg];
        writer.running = true;
    }
    function setOn(e, on) {
        win.write("set", JSON.stringify({ file: e.file, on: on }),
                  on ? Tr.t("Starts at login: %1").arg(e.name) : Tr.t("No longer starts at login: %1").arg(e.name));
    }
    function askRemove(e) { win.confirmFile = e.file; }
    function remove(e) {
        win.write("remove", e.file, Tr.t("Removed %1").arg(e.name));
    }
    function addPicked() {
        const id = win.pickedId.trim();
        if (id === "") { win.error = Tr.t("Pick an app first"); return; }
        win.write("add", JSON.stringify({ id: id }), Tr.t("Added %1 to startup").arg(id));
        win.pickedId = "";
    }
    function addPath() {
        const p = win.filePath.trim();
        if (p === "") { win.error = Tr.t("Choose a .desktop file first"); return; }
        win.write("add", JSON.stringify({ path: p }), Tr.t("Added %1 to startup").arg(p.split("/").pop()));
        win.filePath = "";
    }
    function findApp() {
        const q = win.pickedId.trim();
        if (q === "") { win.error = Tr.t("Pick an app first"); return; }
        // clipboard handoff: the launcher opens on the same text it filters by
        Quickshell.clipboardText = q;
        Ui.startupManager = false;
        Ui.toggleLauncher("app:" + q);
    }

    onVisibleChanged: if (visible) win.refresh()
    Component.onCompleted: win.refresh()

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: Tr.t("Could not read the autostart folder") }; }
                win.error = r.error || "";
                win.entries = win.error ? [] : (r.entries || []);
            }
        }
    }
    Process {
        id: writer
        property string note: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: Tr.t("Could not change the startup app") }; }
                if (r.error) {
                    win.error = r.error;
                } else {
                    win.note = writer.note;
                    noteTimer.restart();
                    win.refresh();
                }
            }
        }
        onExited: code => { if (code !== 0 && win.error === "") win.error = Tr.t("The change could not be made"); }
    }

    // refresh action in AppWindow's header tools
    tools: [
        IconButton {
            icon: "view-refresh"; tip: Tr.t("Refresh the list")
            accessibleName: Tr.t("Refresh the startup apps"); size: Theme.px(30)
            onClicked: win.refresh()
        }
    ]

    Item {
        id: root
        anchors.fill: parent
        focus: true
        // Escape unwinds the confirmation first, then closes through the guard;
        // Ctrl+W closes straight through AppWindow
        Keys.onEscapePressed: win.confirmFile !== "" ? win.confirmFile = "" : win.requestClose()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(12)
            spacing: Theme.px(10)

            SectionTitle {
                Layout.fillWidth: true
                text: Tr.t("Apps that start at login")
                Row { spacing: Theme.px(6)
                    Spinner { visible: lister.running; size: Theme.px(16) }
                }
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Your folder: %1").arg(win.userDir)
                color: Theme.dim; elide: Text.ElideMiddle
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Text {
                Layout.fillWidth: true
                visible: win.error !== ""
                text: win.error
                color: Theme.danger; wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.StaticText; Accessible.name: win.error
            }
            Text {
                Layout.fillWidth: true
                visible: win.note !== "" && win.error === ""
                text: win.note
                color: Theme.dim; wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.StaticText; Accessible.name: win.note
            }

            Repeater {
                model: win.entries
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: Theme.px(8)
                    SwitchRow {
                        Layout.fillWidth: true
                        text: modelData.name
                        hint: (modelData.desc || Tr.t("No description"))
                              + " · " + (modelData.mine ? Tr.t("added by you") : Tr.t("the system's"))
                        checked: modelData.on
                        Accessible.name: Tr.t("Start %1 at login").arg(modelData.name)
                        onToggled: on => win.setOn(modelData, on)
                    }
                    IconButton {
                        visible: modelData.mine
                        icon: "edit-delete"; size: Theme.px(26)
                        tip: Tr.t("Remove")
                        Accessible.name: Tr.t("Remove %1 from startup").arg(modelData.name)
                        onClicked: win.askRemove(modelData)
                    }
                }
            }
            EmptyState {
                Layout.fillWidth: true
                visible: !lister.running && win.error === "" && win.entries.length === 0
                icon: "view-list-details"
                title: Tr.t("No startup apps")
                subtitle: Tr.t("Pick an app below to run it when you sign in")
                actionText: Tr.t("Refresh the list")
                onAction: win.refresh()
            }

            SectionTitle { Layout.fillWidth: true; text: Tr.t("Add an app") }
            AppPicker {
                id: picker
                label: Tr.t("An installed app (its desktop file is copied to your autostart folder)")
                value: win.pickedId
                onPicked: id => win.pickedId = id
            }
            Button {
                flat: true
                text: Tr.t("Find app")
                Accessible.name: Tr.t("Find the picked app in the Launcher")
                onClicked: win.findApp()
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.px(6)
                Button {
                    kind: "primary"; text: Tr.t("Add to startup")
                    enabled: win.pickedId.trim() !== ""
                    Accessible.name: Tr.t("Add the picked app to startup")
                    onClicked: win.addPicked()
                }
                TextField {
                    id: pathField
                    Layout.fillWidth: true
                    label: Tr.t("Or a .desktop file path")
                    placeholder: Tr.t("/path/to/app.desktop")
                    text: win.filePath
                    onTextChanged: win.filePath = text
                }
                Button {
                    text: Tr.t("Add file")
                    enabled: win.filePath.trim() !== ""
                    Accessible.name: Tr.t("Add the chosen desktop file to startup")
                    onClicked: win.addPath()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: win.confirming !== null
                radius: Theme.radiusSmall; color: Theme.surface1; border.width: 1; border.color: Theme.stroke
                RowLayout {
                    anchors.fill: parent; anchors.margins: Theme.px(10); spacing: Theme.px(8)
                    Text {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: win.confirming ? Tr.t("Remove %1 from startup?").arg(win.confirming.name) : ""
                        color: Theme.text; Accessible.name: text
                        font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
                    Button { flat: true; text: Tr.t("Cancel"); onClicked: win.confirmFile = "" }
                    Button {
                        kind: "danger"; text: Tr.t("Remove")
                        onClicked: { if (win.confirming) win.remove(win.confirming); win.confirmFile = ""; }
                    }
                }
            }
        }
    }
}
