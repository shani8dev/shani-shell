// Settings > Privacy: recent files, the trash, clipboard history, and what
// each app has been allowed through the desktop portals (camera, microphone,
// location, screenshots, background) — the portal permission store, read and
// changed with `flatpak permission-*`, revocable one by one.
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
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
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) perms.running = true
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

    // privacy dashboard: a one-glance summary of what apps can do
    readonly property var permCounts: {
        const m = {};
        for (const g of page.grants) {
            const k = g.table;
            m[k] = (m[k] || 0) + 1;
        }
        return m;
    }
    Glass {
        Layout.fillWidth: true
        implicitHeight: dashCol.implicitHeight + 20
        radius: Theme.radiusSmall
        edge: "none"
        ColumnLayout {
            id: dashCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 6
            Text {
                text: Tr.t("Privacy dashboard")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: page.grants.length === 0
                    ? Tr.t("No app has asked for camera, microphone, location or a screenshot yet.")
                    : Tr.t("Apps with access: ") + Object.keys(page.permCounts).map(k => (page.names[k + "/" + page.grants.find(g => g.table === k).id] || k) + " " + page.permCounts[k]).join("  ·  ")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: Object.keys(page.permCounts)
                    Choice {
                        required property string modelData
                        text: (page.names[modelData + "/" + page.grants.find(g => g.table === modelData).id] || modelData) + " · " + page.permCounts[modelData]
                        selected: false
                        onClicked: { }
                    }
                }
            }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Lock screen") }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Show notification titles"); hint: Tr.t("off: only how many came in"); checked: page.d.lockPreviews; defaultValue: false; onToggled: on => page.d.lockPreviews = on; onReset: page.d.lockPreviews = false }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Show the clock"); checked: page.d.lockScreenClock; defaultValue: true; onToggled: on => page.d.lockScreenClock = on; onReset: page.d.lockScreenClock = true }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Show the date"); checked: page.d.lockScreenDate; defaultValue: true; onToggled: on => page.d.lockScreenDate = on; onReset: page.d.lockScreenDate = true }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Show battery"); checked: page.d.lockScreenBattery; defaultValue: true; onToggled: on => page.d.lockScreenBattery = on; onReset: page.d.lockScreenBattery = true }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Blur the wallpaper"); hint: Tr.t("a soft, out-of-reach desktop behind the lock"); checked: page.d.lockScreenBlur; defaultValue: true; onToggled: on => page.d.lockScreenBlur = on; onReset: page.d.lockScreenBlur = true }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Show media controls"); hint: Tr.t("play, pause and skip on the lock screen"); checked: page.d.lockScreenMedia; defaultValue: true; onToggled: on => page.d.lockScreenMedia = on; onReset: page.d.lockScreenMedia = true }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Lock when my phone leaves") }
    Text {
        Layout.fillWidth: true
        text: Bluetooth.devices.values.some(d => d.paired) ? "Pick a paired phone or watch: when it goes out of Bluetooth range for half a minute, the screen locks."
            : "Pair your phone over Bluetooth first."
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Choice { text: Tr.t("Off"); selected: page.d.dynamicLockDevice === ""; onClicked: page.d.dynamicLockDevice = "" }
        Repeater {
            model: Bluetooth.devices.values.filter(d => d.paired)
            Choice {
                required property var modelData
                text: modelData.name || modelData.address
                selected: page.d.dynamicLockDevice === modelData.address
                onClicked: page.d.dynamicLockDevice = modelData.address
            }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Recent files") }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Remember recently used files"); hint: Tr.t("for apps' Recent lists"); checked: page.d.rememberRecent; onToggled: on => page.d.rememberRecent = on }
    Button { text: Tr.t("Clear the recent files list"); onClicked: Housekeeping.clearRecent() }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Trash") }
    RowLayout {
        spacing: 6
        Text { text: Tr.t("Empty automatically"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
        Repeater {
            model: [{ label: Tr.t("Never"), value: 0 }, { label: Tr.t("After 7 days"), value: 7 }, { label: Tr.t("After 30 days"), value: 30 }]
            Choice {
                required property var modelData
                text: modelData.label
                selected: page.d.trashDays === modelData.value
                onClicked: page.d.trashDays = modelData.value
            }
        }
    }
    Button { text: Tr.t("Empty the trash now"); onClicked: Housekeeping.emptyTrash() }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Clipboard") }
    Button { text: Tr.t("Clear clipboard history"); onClicked: Clipboard.wipe() }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("What apps may use") }
    Text {
        Layout.fillWidth: true
        visible: page.grants.length === 0
        text: Tr.t("No app has asked yet. Apps ask through the desktop portal the first time they need the camera, microphone, location or a screenshot.")
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
                Accessible.name: Tr.t("Forget this permission; the app asks again")
                onClicked: {
                    revoke.command = ["flatpak", "permission-remove", g.modelData.table, g.modelData.id, g.modelData.app];
                    revoke.running = true;
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: Tr.t("Location for the weather comes from the city you type under Personalisation — the shell does not locate this computer.")
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
