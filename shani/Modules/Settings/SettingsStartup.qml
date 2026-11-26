// Settings > Default apps > Startup apps: what starts at login (XDG
// autostart, which niri's session runs) — the system's and the person's.
// Turning a system one off writes a copy with Hidden=true into
// ~/.config/autostart (the XDG way, as GNOME does); adding one copies the
// app's own desktop file there. Also: where screenshots are saved.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/ToolPath.js" as ToolPath

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    readonly property var d: Settings.data
    readonly property string userDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/autostart"
    property var entries: []              // [{ file, name, on, mine }]
    // named sessions: the draft name, the note, and the action waiting on a tap
    property string note: ""
    property string noteTone: "ok"
    property string confirmName: ""
    property string confirmAction: ""
    property var confirmSession: null
    Timer { id: noteTimer; interval: 5000; onTriggered: page.note = "" }
    onActiveChanged: if (active) refresh(); else { page.confirmName = ""; page.note = ""; }
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) refresh()
    function refresh() { list.running = true; }

    function when(iso) {
        const d = new Date(iso);
        return isNaN(d.getTime()) ? "" : Qt.formatDateTime(d, "dd MMM yyyy hh:mm");
    }
    function saveSession() {
        if (Sessions.saveCurrent(sessionName.text)) {
            sessionName.text = "";
            page.note = Tr.t("Session saved");
            page.noteTone = "ok";
        } else {
            page.note = Sessions.error;
            page.noteTone = "warn";
        }
        noteTimer.restart();
    }
    function ask(action, session) {
        page.confirmAction = action;
        page.confirmName = session.name;
        page.confirmSession = session;
        page.note = "";
    }
    function answer(yes) {
        if (yes) {
            const ok = page.confirmAction === "restore" ? Sessions.restore(page.confirmName) : Sessions.remove(page.confirmName);
            page.note = ok ? (page.confirmAction === "restore" ? Tr.t("Restoring %1").arg(page.confirmName) : Tr.t("Session removed")) : Sessions.error;
            page.noteTone = ok ? "ok" : "warn";
            noteTimer.restart();
        }
        page.confirmName = "";
        page.confirmAction = "";
        page.confirmSession = null;
    }

    // XDG autostart through bridge/autostart.py: the one implementation (the
    // Startup manager window had a second one; it is this page now)
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_AUTOSTART_TOOL"), "autostart.py")
    property string startupError: ""
    Process {
        id: list
        command: ["python3", page.tool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: Tr.t("Could not read the autostart folder") }; }
                page.startupError = r.error || "";
                page.entries = r.entries || [];
            }
        }
    }
    Process {
        id: change
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: Tr.t("Could not change the autostart folder") }; }
                page.startupError = r.error || "";
            }
        }
        onExited: page.refresh()
    }
    function run(args) {
        change.command = ["python3", page.tool].concat(args);
        change.running = true;
    }
    function setOn(e, on) { run(["set", JSON.stringify({ file: e.file, on: on })]); }
    function remove(e) { run(["remove", e.file]); }
    function add(app) { run(["add", JSON.stringify({ id: app.id })]); find.text = ""; }
    // any .desktop file, picked - not typed
    function addFile() {
        FilePicker.open({ mode: "open", title: Tr.t("Start at login"), filters: ["desktop"],
                          startPath: Quickshell.env("HOME") + "/.local/share/applications",
                          onPicked: paths => { if (paths && paths.length) page.run(["add", JSON.stringify({ path: paths[0] })]); } });
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Apps open when you signed out")
        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: [{ id: "ask", label: Tr.t("Offer to reopen them") }, { id: "always", label: Tr.t("Reopen them") }, { id: "never", label: Tr.t("Start fresh") }]
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.d.reopenApps === modelData.id
                    onClicked: page.d.reopenApps = modelData.id
                }
            }
        }
    }
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Sessions")
        Text {
            Layout.fillWidth: true
            text: Tr.t("Save your apps and documents under a name, then bring them all back at once.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.type("small")
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField {
                id: sessionName
                Layout.fillWidth: true
                placeholder: Tr.t("Name this session")
                error: sessionName.text.trim() !== "" && !Sessions.validName(sessionName.text) ? Tr.t("Use a name of 1 to 60 characters, without / or \\") : ""
                onAccepted: page.saveSession()
            }
            Button { kind: "primary"; text: Tr.t("Save current"); enabled: Sessions.validName(sessionName.text); onClicked: page.saveSession() }
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: Sessions.list().length === 0
            tone: "info"
            text: Tr.t("No sessions saved yet")
        }
        Repeater {
            model: Sessions.list()
            SettingRow {
                required property var modelData
                Layout.fillWidth: true
                icon: "view-restore"
                title: modelData.name
                subtitle: Tr.t("%1 apps, %2 places").arg(modelData.apps.length).arg(modelData.paths.length) + (page.when(modelData.savedAt) ? " · " + page.when(modelData.savedAt) : "")
                Button { flat: true; text: Tr.t("Restore"); Accessible.name: Tr.t("Restore %1").arg(modelData.name); onClicked: page.ask("restore", modelData) }
                Button { flat: true; kind: "danger"; text: Tr.t("Remove"); Accessible.name: Tr.t("Remove %1?").arg(modelData.name); onClicked: page.ask("remove", modelData) }
            }
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.confirmName !== ""
            tone: page.confirmAction === "remove" ? "warn" : "accent"
            iconName: page.confirmAction === "remove" ? "edit-delete" : "view-restore"
            title: (page.confirmAction === "remove" ? Tr.t("Remove %1?") : Tr.t("Restore %1?")).arg(page.confirmName)
            text: page.confirmAction === "remove" ? Tr.t("This cannot be undone.")
                  : Tr.t("%1 apps and %2 places will open now.").arg(page.confirmSession ? page.confirmSession.apps.length : 0).arg(page.confirmSession ? page.confirmSession.paths.length : 0)
            Button { flat: true; text: Tr.t("Cancel"); onClicked: page.answer(false) }
            Button { kind: page.confirmAction === "remove" ? "danger" : "primary"; text: page.confirmAction === "remove" ? Tr.t("Remove") : Tr.t("Restore"); onClicked: page.answer(true) }
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.note !== "" && page.confirmName === ""
            tone: page.noteTone
            text: page.note
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Startup apps")
        BusyNote { Layout.fillWidth: true; visible: list.running; note: Tr.t("Loading…"); iconSize: Theme.px(16) }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.entries.length === 0 && page.startupError === "" && !list.running
            tone: "info"
            text: Tr.t("No startup apps")
        }
        Repeater {
            model: page.entries
            RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                SwitchRow {
                    Layout.fillWidth: true
                    text: row.modelData.name
                    // what it is (its Comment), and whose it is
                    hint: (row.modelData.desc ? row.modelData.desc + " · " : "") + (row.modelData.mine ? Tr.t("added by you") : Tr.t("the system's"))
                    checked: row.modelData.on
                    onToggled: on => page.setOn(row.modelData, on)
                }
                // two taps, as the Startup manager asked before removing
                ConfirmButton {
                    visible: row.modelData.mine
                    text: Tr.t("Remove")
                    kind: "danger"
                    Accessible.name: Tr.t("Remove %1 from startup").arg(row.modelData.name)
                    onConfirmed: page.remove(row.modelData)
                }
            }
        }
        // the usual ones, where installed: a tap each
        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: ["dev.shani.Files", "com.vivaldi.Vivaldi", "org.mozilla.firefox", "org.telegram.desktop", "org.signal.Signal",
                        "com.slack.Slack", "org.mozilla.Thunderbird", "com.spotify.Client", "org.localsend.localsend_app", "dev.shani.chronoa"]
                    .map(id => DesktopEntries.byId(id)).filter(a => a && !a.noDisplay).slice(0, 8)
                Choice {
                    required property var modelData
                    text: "+ " + modelData.name
                    onClicked: page.add(modelData)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField { id: find; Layout.fillWidth: true; placeholder: Tr.t("Or find another app…") }
            Button { text: Tr.t("Add a .desktop file…"); onClicked: page.addFile() }
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.startupError !== ""
            tone: "error"
            text: page.startupError
            accessibleRole: Accessible.AlertMessage
        }
        Repeater {
            model: find.text.trim().length < 2 ? [] : DesktopEntries.applications.values
                .filter(a => !a.noDisplay && a.name.toLowerCase().indexOf(find.text.trim().toLowerCase()) >= 0).slice(0, 6)
            SettingRow {
                required property var modelData
                Layout.fillWidth: true
                icon: modelData.icon || "application-x-executable"
                title: modelData.name
                subtitle: Tr.t("start at login")
                onClicked: page.add(modelData)
            }
        }
    }
}
