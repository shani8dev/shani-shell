// Settings > Storage: what takes room in your own space, and making it free -
// the Trash, the thumbnails, each app's cache, downloads untouched for months,
// Flatpak runtimes nothing uses (bridge/cleanup.py). Old downloads go to the
// Trash, not away. The system's part (update images, old snapshots) is
// Cassini's Maintenance, one button away; what fills the disk, Disk Usage.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 8
    property bool active: false
    onActiveChanged: if (active) scan()

    readonly property string tool: Quickshell.env("SHANI_CLEANUP_TOOL") || "/usr/lib/shani-shell/cleanup.py"
    property var found: null
    property bool scanning: false
    property string busy: ""                 // what is being cleaned
    property string asking: ""               // the one that needs a second click (it cannot be undone)
    property string done: ""
    readonly property real freeable: !found ? 0 : found.trash.size + found.thumbnails.size + found.downloads.size
        + found.caches.filter(c => c.keep === "").reduce((a, c) => a + c.size, 0)

    function scan() { scanning = true; scanner.running = true; }
    function clean(what, arg, label) {
        busy = what + (arg ? ":" + arg : "");
        asking = "";
        cleaner.label = label;
        cleaner.command = ["python3", page.tool, "clean", what].concat(arg ? [arg] : []);
        cleaner.running = true;
    }
    // emptying the Trash and deleting a cache cannot be undone: a second click
    function confirmThen(key, what, arg, label) {
        if (page.asking !== key) { page.asking = key; askTimer.restart(); return; }
        page.clean(what, arg, label);
    }
    Timer { id: askTimer; interval: 4000; onTriggered: page.asking = "" }
    Component.onCompleted: scan()
    Process {
        id: scanner
        command: ["python3", page.tool, "scan"]
        stdout: StdioCollector { onStreamFinished: { try { page.found = JSON.parse(text); } catch (e) {} page.scanning = false; } }
        onExited: page.scanning = false
    }
    Process {
        id: cleaner
        property string label: ""
        stderr: StdioCollector { id: cleanErr }
        onExited: code => {
            page.done = code === 0 ? Tr.t("Done: %1").arg(cleaner.label) : (cleanErr.text.trim().split("\n").pop() || Tr.t("Could not clean that"));
            page.busy = "";
            page.scan();
        }
    }
    function human(b) {
        const u = ["B", "kB", "MB", "GB", "TB"];
        let v = b, i = 0;
        while (v >= 1000 && i < u.length - 1) { v /= 1000; i++; }
        return (i === 0 ? v : v.toFixed(v < 10 ? 1 : 0)) + " " + u[i];
    }

    component Row_: RowLayout {
        id: r
        property string icon
        property string title
        property string detail
        property real size: 0
        property string action: Tr.t("Clean")
        property bool danger: false
        property bool asking: false
        property bool working: false
        property bool can: size > 0
        signal go()
        Layout.fillWidth: true
        Layout.preferredHeight: 52
        spacing: 12
        Icon { name: r.icon; size: 22; color: Theme.dim }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text { Layout.fillWidth: true; text: r.title; color: Theme.text; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale }
            Text { Layout.fillWidth: true; visible: r.detail !== ""; text: r.detail; color: Theme.dim; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
        }
        Text { text: page.human(r.size); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; font.features: { "tnum": 1 } }
        Button {
            Layout.preferredWidth: 140
            enabled: r.can && !r.working && page.busy === ""
            kind: r.asking ? "danger" : "plain"
            text: r.working ? Tr.t("Cleaning…") : r.asking ? Tr.t("Click again") : r.action
            onClicked: r.go()
        }
    }


    RowLayout {
        Layout.fillWidth: true
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: page.scanning && !page.found ? Tr.t("Measuring…") : Tr.t("Up to %1 can be freed").arg(page.human(page.freeable))
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 20 * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Text {
                text: page.done !== "" ? page.done : Tr.t("Only your own files. Nothing here is needed to use the computer.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
            }
        }
        IconButton { size: 30; icon: "view-refresh"; tip: Tr.t("Measure again"); onClicked: page.scan() }
    }

    Row_ {
        visible: !!page.found
        icon: "user-trash"
        title: Tr.t("Trash")
        detail: page.found ? page.found.trash.count + " " + Tr.t("items") + "  ·  " + Tr.t("emptying it cannot be undone") : ""
        size: page.found ? page.found.trash.size : 0
        action: Tr.t("Empty")
        asking: page.asking === "trash"
        working: page.busy === "trash"
        onGo: page.confirmThen("trash", "trash", "", Tr.t("the Trash is empty"))
    }
    Row_ {
        visible: !!page.found
        icon: "image-x-generic"
        title: Tr.t("Thumbnails")
        detail: Tr.t("small copies of pictures and videos; made again when needed")
        size: page.found ? page.found.thumbnails.size : 0
        working: page.busy === "thumbnails"
        onGo: page.clean("thumbnails", "", Tr.t("thumbnails cleared"))
    }
    Row_ {
        visible: !!page.found
        icon: "folder-download"
        title: Tr.t("Old downloads")
        detail: page.found ? (page.found.downloads.count > 0
            ? Tr.t("%1 untouched for %2 days, into the Trash").arg(page.found.downloads.count).arg(page.found.downloads.days)
            : Tr.t("nothing older than %1 days").arg(page.found.downloads.days)) : ""
        size: page.found ? page.found.downloads.size : 0
        action: Tr.t("Move to Trash")
        working: page.busy === "downloads"
        onGo: page.clean("downloads", "", Tr.t("old downloads are in the Trash"))
    }
    Row_ {
        visible: !!page.found && page.found.flatpak
        icon: "package-x-generic"
        title: Tr.t("Unused Flatpak runtimes")
        detail: Tr.t("left behind by apps that were removed")
        size: 0
        can: true
        action: Tr.t("Remove")
        working: page.busy === "flatpak"
        onGo: page.clean("flatpak", "", Tr.t("unused runtimes removed"))
    }

    SectionTitle { Layout.fillWidth: true; visible: !!page.found && page.found.caches.length > 0; text: Tr.t("App caches") }
    Repeater {
        model: page.found ? page.found.caches.filter(c => c.size > 0) : []
        delegate: Row_ {
            required property var modelData
            Layout.fillWidth: true
            icon: modelData.keep !== "" ? "emblem-readonly" : "folder"
            title: modelData.name
            detail: modelData.keep !== "" ? Tr.t("kept: %1").arg(modelData.keep) : Tr.t("the app makes it again as it needs it")
            size: modelData.size
            can: modelData.keep === "" && modelData.size > 0
            asking: page.asking === "cache:" + modelData.name
            working: page.busy === "cache:" + modelData.name
            onGo: page.confirmThen("cache:" + modelData.name, "cache", modelData.name, modelData.name + " " + Tr.t("cleared"))
        }
    }

    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: Tr.t("Update images, old snapshots and the system's logs are cleaned in Cassini, with your password.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: 11 * Theme.fontScale
        }
        Button { text: Tr.t("System clean-up…"); onClicked: Quickshell.execDetached(["shani-cassini", "--section=maintenance"]) }
    }

    RowLayout {
        Layout.fillWidth: true
        Button { text: Tr.t("What fills the disk…"); flat: true; onClicked: { Ui.closeAll(); Ui.diskUsage = true; } }
    }
}
