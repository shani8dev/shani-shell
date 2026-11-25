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

    // one line each: file<TAB>name<TAB>hidden(true|false)<TAB>user|system — the user's copy wins
    Process {
        id: list
        command: ["sh", "-c", 'u="$1"; for f in "$u"/*.desktop /etc/xdg/autostart/*.desktop; do [ -f "$f" ] || continue
                b=${f##*/}; case "$f" in /etc/*) [ -f "$u/$b" ] && continue; src=system;; *) src=user;; esac
                n=$(sed -n "s/^Name=//p" "$f" | head -1); h=$(grep -qiE "^Hidden=true|^X-GNOME-Autostart-enabled=false" "$f" && echo true || echo false)
                printf "%s\\t%s\\t%s\\t%s\\n" "$b" "${n:-$b}" "$h" "$src"; done', "sh", page.userDir]
        stdout: StdioCollector {
            onStreamFinished: page.entries = text.trim().split("\n").filter(x => x).map(l => {
                const f = l.split("\t");
                return { file: f[0], name: f[1], on: f[2] !== "true", mine: f[3] === "user" };
            }).sort((a, b) => a.name.localeCompare(b.name))
        }
    }
    Process { id: change; onExited: page.refresh() }
    function setOn(e, on) {
        // a system entry: a user copy, hidden or not; a user entry: edited in place
        change.command = ["sh", "-c", 'u="$1"; f="$2"; mkdir -p "$u"; [ -f "$u/$f" ] || cp "/etc/xdg/autostart/$f" "$u/$f"
            sed -i "/^Hidden=/d; /^X-GNOME-Autostart-enabled=/d" "$u/$f"; [ "$3" = off ] && printf "Hidden=true\\n" >> "$u/$f"; true', "sh", userDir, e.file, on ? "on" : "off"];
        change.running = true;
    }
    function remove(e) {
        change.command = ["rm", "-f", userDir + "/" + e.file];
        change.running = true;
    }
    function add(app) {
        // the app's own desktop file, wherever XDG keeps it
        change.command = ["sh", "-c", 'u="$1"; id="$2"; mkdir -p "$u"; for d in "${XDG_DATA_HOME:-$HOME/.local/share}" $(echo "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | tr ":" " "); do
                f="$d/applications/$id.desktop"; [ -f "$f" ] && { cp "$f" "$u/$id.desktop"; exit 0; }; done; exit 1', "sh", userDir, app.id];
        change.running = true;
        find.text = "";
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
            font.pixelSize: Theme.px(11) * Theme.fontScale
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
        Repeater {
            model: page.entries
            RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                SwitchRow {
                    Layout.fillWidth: true
                    text: row.modelData.name
                    hint: row.modelData.mine ? "added by you" : "the system's"
                    checked: row.modelData.on
                    onToggled: on => page.setOn(row.modelData, on)
                }
                IconButton {
                    visible: row.modelData.mine
                    icon: "edit-delete"
                    size: Theme.px(24)
                    Accessible.name: "Remove " + row.modelData.name + " from startup"
                    onClicked: page.remove(row.modelData)
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
        TextField { id: find; Layout.fillWidth: true; placeholder: Tr.t("Or find another app…") }
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
