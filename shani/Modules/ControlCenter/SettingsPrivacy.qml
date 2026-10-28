// Settings > Privacy: recent files, the trash, clipboard history, and what
// each app has been allowed through the desktop portals (camera, microphone,
// location, screenshots, background) — the portal permission store, read and
// changed with `flatpak permission-*`, revocable one by one.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    readonly property var d: Settings.data
    property var grants: []               // [{ table, id, app, perms }]
    onActiveChanged: if (active) perms.running = true
    readonly property var names: ({ "devices/camera": "Camera", "devices/microphone": "Microphone", "devices/speakers": "Speakers",
                                    "location/location": "Location", "screenshot/screenshot": "Screenshots",
                                    "background/background": "Run in the background", "notifications/notification": "Notifications" })

    // "devices camera org.app.Id yes" … from each table that holds per-app grants
    Process {
        id: perms
        command: ["sh", "-c", 'command -v flatpak >/dev/null || exit 0; for t in devices location screenshot background notifications; do
                flatpak permission-show 2>/dev/null | awk -v t="$t" "\\$1 == t && NF >= 4 {print \\$1, \\$2, \\$3, \\$4}"; done | sort -u']
        stdout: StdioCollector {
            onStreamFinished: page.grants = text.trim().split("\n").filter(x => x).map(l => {
                const f = l.split(/\s+/);
                return { table: f[0], id: f[1], app: f[2], perms: f[3] };
            })
        }
    }
    Process { id: revoke; onExited: perms.running = true }

    SectionTitle { Layout.fillWidth: true; text: "Lock screen" }
    SwitchRow { Layout.fillWidth: true; text: "Show notification titles"; hint: "off: only how many came in"; checked: page.d.lockPreviews; onToggled: on => page.d.lockPreviews = on }

    SectionTitle { Layout.fillWidth: true; text: "Recent files" }
    SwitchRow { Layout.fillWidth: true; text: "Remember recently used files"; hint: "for apps' Recent lists"; checked: page.d.rememberRecent; onToggled: on => page.d.rememberRecent = on }
    Button { text: "Clear the recent files list"; onClicked: Housekeeping.clearRecent() }

    SectionTitle { Layout.fillWidth: true; text: "Trash" }
    RowLayout {
        spacing: 6
        Text { text: "Empty automatically"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
        Repeater {
            model: [{ label: "Never", value: 0 }, { label: "After 7 days", value: 7 }, { label: "After 30 days", value: 30 }]
            Choice {
                required property var modelData
                text: modelData.label
                selected: page.d.trashDays === modelData.value
                onClicked: page.d.trashDays = modelData.value
            }
        }
    }
    Button { text: "Empty the trash now"; onClicked: Housekeeping.emptyTrash() }

    SectionTitle { Layout.fillWidth: true; text: "Clipboard" }
    Button { text: "Clear clipboard history"; onClicked: Clipboard.wipe() }

    SectionTitle { Layout.fillWidth: true; text: "What apps may use" }
    Text {
        Layout.fillWidth: true
        visible: page.grants.length === 0
        text: "No app has asked yet. Apps ask through the desktop portal the first time they need the camera, microphone, location or a screenshot."
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Repeater {
        model: page.grants
        ListRow {
            id: g
            required property var modelData
            Layout.fillWidth: true
            readonly property var entry: DesktopEntries.byId(modelData.app)
            icon: entry && entry.icon ? entry.icon : "application-x-executable"
            title: entry ? entry.name : modelData.app
            subtitle: (page.names[modelData.table + "/" + modelData.id] || modelData.table + " " + modelData.id) + ": " + (modelData.perms.indexOf("yes") >= 0 ? "allowed" : "denied")
            IconButton {
                icon: "edit-delete"
                size: 24
                Accessible.name: "Forget this permission; the app asks again"
                onClicked: {
                    revoke.command = ["flatpak", "permission-remove", g.modelData.table, g.modelData.id, g.modelData.app];
                    revoke.running = true;
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: "Location for the weather comes from the city you type under Personalisation — the shell does not locate this computer."
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
