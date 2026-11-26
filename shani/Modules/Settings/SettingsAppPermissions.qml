// Settings > Default apps > App permissions (Flatseal parity): for each Flatpak
// app, everything its sandbox lets it reach - sharing, sockets, devices,
// features, folders, persistent folders, environment, the D-Bus names it may
// talk to or own - and the portals' answers for it (notifications, running in
// the background, camera, location). As the app asked, plus your changes:
// `flatpak override --user` (bridge/flatperm.py), each marked, all undone by
// Reset. A change shows at once; the app sees it the next time it starts.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    objectName: "section:apppermissions"     // Software's "Change permissions…" scrolls here
    spacing: Theme.px(12)
    property bool active: false
    property var apps: []                 // [{ id, name }]
    property string open: ""
    property var perms: null              // flatperm.py show's answer for the open app
    property string error: ""
    readonly property string tool: Quickshell.env("SHANI_FLATPERM_TOOL") || "/usr/lib/shani-shell/flatperm.py"
    onActiveChanged: if (active) list.running = true
    Component.onCompleted: if (active) list.running = true

    Process {
        id: list
        command: ["python3", page.tool, "apps"]
        // a list of apps, or {"error"} where there is no flatpak: "No Flatpak apps installed"
        stdout: StdioCollector {
            onStreamFinished: {
                let r = [];
                try { r = JSON.parse(text); } catch (e) { r = []; }
                page.apps = Array.isArray(r) ? r : [];
                Ui.appPermApps = page.apps.map(a => a.id);
                page.takeFocus();
            }
        }
    }
    Process {
        id: bridge
        onExited: {
            if (page.queued) {
                const next = page.queued;
                page.queued = null;
                page.call(next);
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() }; }
                if (r.error) { page.error = r.error; return; }
                page.error = "";
                page.perms = r;
                Ui.appPermShown = JSON.stringify(r);
            }
        }
    }
    property var queued: null
    function call(args) {
        // A second click while flatperm.py is running must not be dropped: an
        // expand would leave the row stuck open with no permissions, and a
        // switch would snap back with nothing changed. Run the latest request
        // when this one exits.
        if (bridge.running) { queued = args; return; }
        bridge.command = ["python3", page.tool].concat(args);
        bridge.running = true;
    }
    function openApp(id) {
        open = open === id ? "" : id;
        perms = null;
        error = "";
        if (open) call(["show", id]);
    }
    // an app asked for from elsewhere (Software): opened once the list is in
    function takeFocus() {
        const id = Ui.appPermFocus;
        if (!id || !page.apps.some(a => a.id === id)) return;
        Ui.appPermFocus = "";
        if (page.open !== id) page.openApp(id);
    }
    Connections { target: Ui; function onAppPermFocusChanged() { page.takeFocus(); } }
    function has(list, x) { return !!perms && (perms[list] || []).indexOf(x) >= 0; }
    function mine(list, x) { return !!perms && ((perms.changed || {})[list] || []).indexOf(x) >= 0; }
    // a switch: on/off are override's own pair of flags
    function flip(on, yes, no, value) { call(["set", open, (on ? yes : no) + "=" + value]); }
    // a bus name is shown as "talk" or "own"; removing it needs the matching no-flag
    function busNoFlag(system, value) { return (system ? "--system-no-" : "--no-") + (value === "own" ? "own-name" : "talk-name"); }

    // the switches, in Flatseal's sections: [list, value, on-flag, off-flag, label, hint]
    readonly property var sections: [
        [Tr.t("Share"), [["shared", "network", "--share", "--unshare", Tr.t("Network"), ""],
                         ["shared", "ipc", "--share", "--unshare", Tr.t("Inter-process communication"), Tr.t("shared memory with the X server")]]],
        [Tr.t("Sockets"), [["sockets", "wayland", "--socket", "--nosocket", Tr.t("Wayland windows"), ""],
                           ["sockets", "x11", "--socket", "--nosocket", Tr.t("X11 windows"), ""],
                           ["sockets", "fallback-x11", "--socket", "--nosocket", Tr.t("X11 when there is no Wayland"), ""],
                           ["sockets", "pulseaudio", "--socket", "--nosocket", Tr.t("Sound"), Tr.t("play and record")],
                           ["sockets", "session-bus", "--socket", "--nosocket", Tr.t("All of the session bus"), Tr.t("talk to any app")],
                           ["sockets", "system-bus", "--socket", "--nosocket", Tr.t("All of the system bus"), ""],
                           ["sockets", "ssh-auth", "--socket", "--nosocket", Tr.t("SSH keys (agent)"), ""],
                           ["sockets", "gpg-agent", "--socket", "--nosocket", Tr.t("GPG keys (agent)"), ""],
                           ["sockets", "pcsc", "--socket", "--nosocket", Tr.t("Smart cards"), ""],
                           ["sockets", "cups", "--socket", "--nosocket", Tr.t("Printing"), ""]]],
        [Tr.t("Devices"), [["devices", "dri", "--device", "--nodevice", Tr.t("Graphics acceleration"), ""],
                           ["devices", "kvm", "--device", "--nodevice", Tr.t("Virtualisation (KVM)"), ""],
                           ["devices", "shm", "--device", "--nodevice", Tr.t("Shared memory"), ""],
                           ["devices", "all", "--device", "--nodevice", Tr.t("All devices"), Tr.t("webcams, game controllers, USB")]]],
        [Tr.t("Allow"), [["features", "bluetooth", "--allow", "--disallow", Tr.t("Bluetooth"), ""],
                         ["features", "devel", "--allow", "--disallow", Tr.t("Development"), Tr.t("debuggers, ptrace")],
                         ["features", "multiarch", "--allow", "--disallow", Tr.t("Other architectures"), Tr.t("32-bit programs")],
                         ["features", "per-app-dev-shm", "--allow", "--disallow", Tr.t("Its own shared memory"), ""],
                         ["features", "canbus", "--allow", "--disallow", Tr.t("CAN bus"), ""]]],
        [Tr.t("Files"), [["filesystems", "home", "--filesystem", "--nofilesystem", Tr.t("Your home folder"), Tr.t("otherwise only what you open with it")],
                         ["filesystems", "host", "--filesystem", "--nofilesystem", Tr.t("All files"), Tr.t("the whole system's")],
                         ["filesystems", "host-os", "--filesystem", "--nofilesystem", Tr.t("System programs"), Tr.t("read-only /usr")],
                         ["filesystems", "host-etc", "--filesystem", "--nofilesystem", Tr.t("System settings"), Tr.t("read-only /etc")],
                         ["filesystems", "xdg-download", "--filesystem", "--nofilesystem", Tr.t("Downloads"), ""],
                         ["filesystems", "xdg-documents", "--filesystem", "--nofilesystem", Tr.t("Documents"), ""],
                         ["filesystems", "xdg-pictures", "--filesystem", "--nofilesystem", Tr.t("Pictures"), ""],
                         ["filesystems", "xdg-music", "--filesystem", "--nofilesystem", Tr.t("Music"), ""],
                         ["filesystems", "xdg-videos", "--filesystem", "--nofilesystem", Tr.t("Videos"), ""]]]
    ]
    readonly property var standardFs: ["home", "host", "host-os", "host-etc", "xdg-download", "xdg-documents", "xdg-pictures", "xdg-music", "xdg-videos"]
    // other folders it reaches (yours or its own), beyond the switches above
    readonly property var otherFs: perms ? (perms.filesystems || []).filter(f => standardFs.indexOf(f.replace(/:(ro|rw|create)$/, "")) < 0) : []
    property bool readOnly: true

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("App permissions")

        Text {
            Layout.fillWidth: true
            visible: page.apps.length === 0
            text: Tr.t("No Flatpak apps installed.")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
        }
    Repeater {
        model: page.apps
        ColumnLayout {
            id: arow
            required property var modelData
            Layout.fillWidth: true
            spacing: Theme.px(4)
            readonly property var entry: DesktopEntries.byId(modelData.id)
            readonly property bool isOpen: page.open === modelData.id && page.perms !== null
            SettingRow {
                Layout.fillWidth: true
                icon: arow.entry && arow.entry.icon ? arow.entry.icon : "application-x-executable"
                title: arow.modelData.name
                subtitle: arow.modelData.id
                trailing: page.open === arow.modelData.id ? "⌄" : "›"
                onClicked: page.openApp(arow.modelData.id)
            }
            ColumnLayout {
                visible: arow.isOpen
                Layout.leftMargin: Theme.px(28)
                Layout.fillWidth: true
                spacing: 2
                Text {
                    visible: page.error !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: page.error
                    color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.type("small")
                }
                Repeater {
                    model: arow.isOpen ? page.sections : []
                    ColumnLayout {
                        id: sec
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        Text { text: sec.modelData[0]; color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.type("caption"); Layout.topMargin: Theme.px(8) }
                        Repeater {
                            model: sec.modelData[1]
                            SwitchRow {
                                required property var modelData
                                Layout.fillWidth: true
                                text: modelData[4] + (page.mine(modelData[0], modelData[1]) ? "  ·  " + Tr.t("changed") : "")
                                hint: modelData[5]
                                checked: page.has(modelData[0], modelData[1]) || (modelData[0] === "filesystems" && page.has("filesystems", modelData[1] + ":ro"))
                                onToggled: on => page.flip(on, modelData[2], modelData[3], modelData[1])
                            }
                        }
                    }
                }
                // other folders: each with its access, removed with a click; another added from a picker
                Text { visible: arow.isOpen; text: Tr.t("Other folders"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.type("caption"); Layout.topMargin: Theme.px(8) }
                Repeater {
                    model: arow.isOpen ? page.otherFs : []
                    RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            text: modelData.replace(/:ro$/, "  ·  " + Tr.t("read only")).replace(/:(rw|create)$/, "")
                            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body")
                        }
                        IconButton { icon: "window-close"; size: Theme.px(22); tip: Tr.t("No longer"); onClicked: page.call(["set", page.open, "--nofilesystem=" + modelData.replace(/:(ro|rw|create)$/, "")]) }
                    }
                }
                RowLayout {
                    visible: arow.isOpen
                    Layout.fillWidth: true
                    FolderPicker { id: addFolder; Layout.fillWidth: true; label: Tr.t("Add a folder") }
                    Choice { text: Tr.t("Read only"); selected: page.readOnly; onClicked: page.readOnly = !page.readOnly }
                    Button {
                        text: Tr.t("Add")
                        enabled: addFolder.value !== ""
                        onClicked: { page.call(["set", page.open, "--filesystem=" + addFolder.value + (page.readOnly ? ":ro" : "")]); addFolder.value = ""; }
                    }
                }
                // what the portals answer for it
                Text { visible: arow.isOpen; text: Tr.t("Asks through the desktop"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.type("caption"); Layout.topMargin: Theme.px(8) }
                Repeater {
                    model: arow.isOpen ? [["notifications", Tr.t("Notifications")], ["background", Tr.t("Running in the background")],
                                          ["camera", Tr.t("Camera")], ["microphone", Tr.t("Microphone")],
                                          ["location", Tr.t("Your location")], ["screenshot", Tr.t("Screenshots")]] : []
                    RowLayout {
                        id: prow
                        required property var modelData
                        Layout.fillWidth: true
                        readonly property string now: (page.perms && page.perms.portals || {})[modelData[0]] || ""
                        Text { Layout.fillWidth: true; text: prow.modelData[1]; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body") }
                        Repeater {
                            model: [["", Tr.t("Ask")], ["yes", Tr.t("Allowed")], ["no", Tr.t("Not allowed")]]
                            Choice {
                                required property var modelData
                                text: modelData[1]
                                selected: prow.now === modelData[0]
                                onClicked: page.call(["portal", page.open, prow.modelData[0], modelData[0] || "reset"])
                            }
                        }
                    }
                }
                // environment and D-Bus names: listed (yours marked); typed only to add one
                Text { visible: arow.isOpen && page.perms && Object.keys(page.perms.env || {}).length > 0; text: Tr.t("Environment"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.type("caption"); Layout.topMargin: Theme.px(8) }
                Repeater {
                    model: arow.isOpen && page.perms ? Object.keys(page.perms.env || {}) : []
                    RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData + "=" + page.perms.env[modelData]; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.type("small") }
                        IconButton { icon: "window-close"; size: Theme.px(22); tip: Tr.t("Unset it"); onClicked: page.call(["set", page.open, "--unset-env=" + modelData]) }
                    }
                }
                Text { visible: arow.isOpen && page.perms && Object.keys(page.perms.session || {}).length > 0; text: Tr.t("Session bus names"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.type("caption"); Layout.topMargin: Theme.px(8) }
                Repeater {
                    model: arow.isOpen && page.perms ? Object.keys(page.perms.session || {}) : []
                    RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; elide: Text.ElideMiddle; text: modelData + "  ·  " + page.perms.session[modelData]; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.type("small") }
                        IconButton { icon: "window-close"; size: Theme.px(22); tip: Tr.t("No longer"); onClicked: page.call(["set", page.open, page.busNoFlag(false, page.perms.session[modelData]) + "=" + modelData]) }
                    }
                }
                Text { visible: arow.isOpen && page.perms && Object.keys(page.perms.system || {}).length > 0; text: Tr.t("System bus names"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.type("caption"); Layout.topMargin: Theme.px(8) }
                Repeater {
                    model: arow.isOpen && page.perms ? Object.keys(page.perms.system || {}) : []
                    RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; elide: Text.ElideMiddle; text: modelData + "  ·  " + page.perms.system[modelData]; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.type("small") }
                        IconButton { icon: "window-close"; size: Theme.px(22); tip: Tr.t("No longer"); onClicked: page.call(["set", page.open, page.busNoFlag(true, page.perms.system[modelData]) + "=" + modelData]) }
                    }
                }
                RowLayout {
                    visible: arow.isOpen
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.px(6)
                    TextField { id: addEnv; Layout.fillWidth: true; placeholderText: Tr.t("Add a variable: NAME=value") }
                    Button { text: Tr.t("Add"); enabled: /^[A-Za-z_][A-Za-z0-9_]*=/.test(addEnv.text); onClicked: { page.call(["set", page.open, "--env=" + addEnv.text.trim()]); addEnv.text = ""; } }
                }
                RowLayout {
                    visible: arow.isOpen
                    Layout.fillWidth: true
                    TextField { id: addName; Layout.fillWidth: true; placeholderText: Tr.t("Let it talk to a bus name: org.example.Name") }
                    Button { text: Tr.t("Add"); enabled: /^[A-Za-z_][\w-]*(\.[\w-]+)+\*?$/.test(addName.text.trim()); onClicked: { page.call(["set", page.open, "--talk-name=" + addName.text.trim()]); addName.text = ""; } }
                }
                Button {
                    Layout.topMargin: Theme.px(6)
                    visible: arow.isOpen
                    text: Tr.t("Back to what the app asked for")
                    onClicked: page.call(["reset", page.open])
                }
            }
        }
    }
    }
}
