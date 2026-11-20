// Containers (Pods' and BoxBuddy's jobs, the way Ananta Dev does them): Distrobox
// toolboxes - a whole Ubuntu, Fedora, Arch or Debian sharing your home folder -
// made from a chip, opened in your terminal, their apps put in your menu, upgraded,
// removed; and your rootless Podman containers (start, stop, restart, logs, remove)
// and images (remove, prune). Everything through bridge/containers.py, as you - no
// administrator password. Cassini's Containers page stays the read-only inventory.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Containers"
    visible: Ui.containers
    onGone: Ui.containers = false
    implicitWidth: Theme.px(680)
    implicitHeight: Theme.px(620)

    readonly property string tool: Quickshell.env("SHANI_CONTAINERS_TOOL") || "/usr/lib/shani-shell/containers.py"
    // the toolboxes Ananta Dev offers, and the images they come from
    readonly property var distros: [
        ["ubuntu", "Ubuntu 24.04", "docker.io/library/ubuntu:24.04"],
        ["fedora", "Fedora", "registry.fedoraproject.org/fedora-toolbox:latest"],
        ["arch", "Arch Linux", "docker.io/library/archlinux:latest"],
        ["debian", "Debian 13", "docker.io/library/debian:13"]
    ]
    property string tab: "boxes"
    property var containers: []
    property var images: []
    property bool hasPodman: true
    property bool hasDistrobox: true
    property string error: ""
    property string note: ""
    property string removing: ""
    property string logsOf: ""
    property string logsText: ""
    property string appsOf: ""             // the toolbox whose apps are listed
    property var apps: []
    property string distro: "ubuntu"
    property string jobLine: ""
    readonly property var boxes: containers.filter(c => c.box)
    readonly property var others: containers.filter(c => !c.box)

    function refresh() { lister.running = true; }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()
    Timer { interval: 5000; repeat: true; running: win.visible && !job.running; onTriggered: win.refresh() }

    Process {
        id: lister
        command: ["python3", win.tool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { return; }
                win.hasPodman = !!r.podman;
                win.hasDistrobox = !!r.distrobox;
                win.containers = r.containers || [];
                win.images = r.images || [];
                Ui.containersList = win.containers.map(c => (c.box ? "box:" : "") + c.name + ":" + c.state);
                Ui.containersImages = win.images.map(i => i.name);
            }
        }
    }
    Process {
        id: act
        property var after: null
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() }; }
                win.error = r.error || "";
                if (act.after) act.after(r);
                win.refresh();
            }
        }
    }
    function run(args, after) {
        if (act.running) return;
        act.command = ["python3", win.tool].concat(args);
        act.after = after || null;
        act.running = true;
    }
    // the long ones (a toolbox made, upgraded): a line at a time
    Process {
        id: job
        property string what: ""
        stdout: SplitParser {
            onRead: line => {
                let r = {};
                try { r = JSON.parse(line); } catch (e) { return; }
                if (r.line) win.jobLine = r.line;
                if (r.error) win.error = r.error;
                if (r.ok) { Ui.containersDone = job.what + ":ok"; win.note = Tr.t("Done: %1", job.what); }
            }
        }
        onExited: { win.jobLine = ""; win.refresh(); }
    }
    function startJob(what, args) {
        if (job.running) return;
        win.error = "";
        job.what = what;
        job.command = ["python3", win.tool].concat(args);
        job.running = true;
    }
    function nextName(d) {
        let n = d, i = 2;
        while (win.containers.some(c => c.name === n)) n = d + "-" + i++;
        return n;
    }
    function enter(name) {
        Quickshell.execDetached(["xdg-terminal-exec", "distrobox", "enter", name]);
        Ui.containersEntered = name;
    }
    function showLogs(name) {
        if (win.logsOf === name) { win.logsOf = ""; return; }
        win.run(["logs", name], r => { win.logsOf = name; win.logsText = r.text || ""; });
    }
    function showApps(name) {
        if (win.appsOf === name) { win.appsOf = ""; return; }
        win.apps = [];
        win.appsOf = name;
        win.run(["box-apps", name], r => { win.apps = Array.isArray(r) ? r : []; Ui.containersApps = win.apps.map(a => a.id); });
    }
    function size(b) { return b > 1e9 ? (b / 1e9).toFixed(1) + " GB" : Math.round(b / 1e6) + " MB"; }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(14)
        spacing: Theme.px(8)
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: [["boxes", Tr.t("Toolboxes")], ["containers", Tr.t("Containers")], ["images", Tr.t("Images")]]
                Choice { required property var modelData; text: modelData[1]; selected: win.tab === modelData[0]; onClicked: win.tab = modelData[0] }
            }
            Item { Layout.fillWidth: true }
            IconButton { icon: "view-refresh"; size: Theme.px(28); tip: Tr.t("Read again"); onClicked: win.refresh() }
        }
        Text {
            visible: !win.hasPodman || win.error !== "" || win.note !== "" || win.jobLine !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: !win.hasPodman ? Tr.t("Podman is not installed") : win.error !== "" ? win.error : win.jobLine !== "" ? win.jobLine : win.note
            color: win.error !== "" || !win.hasPodman ? Theme.danger : Theme.dim
            font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }

        // ---- toolboxes (Distrobox) ----
        ColumnLayout {
            visible: win.tab === "boxes" && win.hasDistrobox
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Tr.t("A toolbox is a whole Linux that shares your home folder: install its packages without touching the system, and put its apps in your menu.")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: win.distros
                    Choice { required property var modelData; text: modelData[1]; selected: win.distro === modelData[0]; onClicked: win.distro = modelData[0] }
                }
                Item { Layout.fillWidth: true }
                Button {
                    kind: "primary"
                    text: job.running && job.what.indexOf("create") === 0 ? Tr.t("Making it…") : Tr.t("New toolbox")
                    enabled: !job.running
                    onClicked: {
                        const d = win.distros.find(x => x[0] === win.distro);
                        const n = win.nextName(d[0]);
                        win.startJob("create " + n, ["box-create", n, d[2]]);
                    }
                }
            }
        }
        Text {
            visible: win.tab === "boxes" && !win.hasDistrobox
            text: Tr.t("Distrobox is not installed")
            color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        Text {
            visible: win.tab === "boxes" && win.hasDistrobox && win.boxes.length === 0
            text: Tr.t("No toolboxes yet - pick a Linux above")
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        ListView {
            id: blist
            visible: win.tab === "boxes"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.px(4)
            model: win.boxes
            delegate: ColumnLayout {
                id: brow
                required property var modelData
                width: blist.width
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Icon { name: "utilities-terminal"; size: Theme.px(22); color: brow.modelData.state === "running" ? Theme.accent : Theme.dim }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: brow.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                        Text {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            text: [brow.modelData.state === "running" ? Tr.t("running") : Tr.t("stopped"), brow.modelData.image].join("  ·  ")
                            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                    }
                    Button { text: Tr.t("Open"); onClicked: win.enter(brow.modelData.name) }
                    IconButton { icon: "view-app-grid"; size: Theme.px(26); tip: Tr.t("Its apps, for your menu"); onClicked: win.showApps(brow.modelData.name) }
                    IconButton { icon: "system-software-update"; size: Theme.px(26); tip: Tr.t("Update its packages"); enabled: !job.running; onClicked: win.startJob("upgrade " + brow.modelData.name, ["box-upgrade", brow.modelData.name]) }
                    IconButton {
                        visible: brow.modelData.state === "running"
                        icon: "media-playback-stop"; size: Theme.px(26); tip: Tr.t("Stop"); onClicked: win.run(["stop", brow.modelData.name])
                    }
                    IconButton {
                        icon: win.removing === brow.modelData.name ? "edit-delete" : "window-close"
                        size: Theme.px(26)
                        tip: win.removing === brow.modelData.name ? Tr.t("Click again: %1 and its apps are removed (your home folder stays)", brow.modelData.name) : Tr.t("Remove")
                        onClicked: { if (win.removing === brow.modelData.name) { win.removing = ""; win.run(["box-remove", brow.modelData.name]); } else win.removing = brow.modelData.name; }
                    }
                }
                ColumnLayout {
                    visible: win.appsOf === brow.modelData.name
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(30)
                    spacing: 2
                    Text {
                        visible: win.apps.length === 0
                        text: act.running ? Tr.t("Looking…") : Tr.t("No apps inside yet - install some in its terminal")
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Repeater {
                        model: win.appsOf === brow.modelData.name ? win.apps : []
                        RowLayout {
                            id: arow
                            required property var modelData
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: arow.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                            Button {
                                text: Tr.t("Add to menu")
                                onClicked: win.run(["box-export", brow.modelData.name, arow.modelData.id],
                                                   r => { if (r.ok) { win.note = Tr.t("%1 is in your menu", arow.modelData.name); Ui.containersExported = arow.modelData.id; } })
                            }
                        }
                    }
                }
            }
        }

        // ---- containers (Podman) ----
        Text {
            visible: win.tab === "containers" && win.others.length === 0
            text: Tr.t("No containers - podman run, docker compose or an IDE's dev container show up here")
            wrapMode: Text.WordWrap; Layout.fillWidth: true
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        ListView {
            id: clist
            visible: win.tab === "containers"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.px(4)
            model: win.others
            delegate: ColumnLayout {
                id: crow
                required property var modelData
                readonly property bool up: modelData.state === "running"
                width: clist.width
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Icon { name: "package-x-generic"; size: Theme.px(22); color: crow.up ? Theme.accent : Theme.dim }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: crow.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                        Text {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            text: [crow.modelData.state, crow.modelData.image, crow.modelData.ports].filter(x => x).join("  ·  ")
                            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                    }
                    IconButton { icon: crow.up ? "media-playback-stop" : "media-playback-start"; size: Theme.px(26); tip: crow.up ? Tr.t("Stop") : Tr.t("Start"); onClicked: win.run([crow.up ? "stop" : "start", crow.modelData.name]) }
                    IconButton { visible: crow.up; icon: "view-refresh"; size: Theme.px(26); tip: Tr.t("Restart"); onClicked: win.run(["restart", crow.modelData.name]) }
                    IconButton { icon: "text-x-generic"; size: Theme.px(26); tip: Tr.t("Logs"); onClicked: win.showLogs(crow.modelData.name) }
                    IconButton {
                        icon: win.removing === crow.modelData.name ? "edit-delete" : "window-close"
                        size: Theme.px(26)
                        tip: win.removing === crow.modelData.name ? Tr.t("Click again: %1 is removed", crow.modelData.name) : Tr.t("Remove")
                        onClicked: { if (win.removing === crow.modelData.name) { win.removing = ""; win.run(["remove", crow.modelData.name]); } else win.removing = crow.modelData.name; }
                    }
                }
                Rectangle {
                    visible: win.logsOf === crow.modelData.name
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(180)
                    color: Theme.card
                    radius: Theme.px(6)
                    Flickable {
                        id: lf
                        anchors.fill: parent
                        anchors.margins: Theme.px(6)
                        clip: true
                        contentHeight: lt.implicitHeight
                        onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                        Text {
                            id: lt
                            width: lf.width
                            wrapMode: Text.WrapAnywhere
                            text: win.logsOf === crow.modelData.name ? (win.logsText || Tr.t("Nothing logged")) : ""
                            color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                    }
                }
            }
        }

        // ---- images ----
        RowLayout {
            visible: win.tab === "images"
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: Tr.t("%1 images, %2", win.images.length, win.size(win.images.reduce((s, i) => s + (i.size || 0), 0)))
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Button {
                text: Tr.t("Remove unused")
                enabled: win.images.some(i => !i.used)
                onClicked: win.run(["prune"], r => { if (r.ok) win.note = Tr.t("%1 images removed", r.removed); })
            }
        }
        ListView {
            id: ilist
            visible: win.tab === "images"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: win.images
            delegate: RowLayout {
                id: irow
                required property var modelData
                width: ilist.width
                spacing: Theme.px(8)
                Icon { name: "media-optical"; size: Theme.px(20); color: Theme.dim }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: irow.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                    Text {
                        text: [win.size(irow.modelData.size || 0), irow.modelData.used ? Tr.t("in use") : Tr.t("unused")].join("  ·  ")
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
                IconButton {
                    visible: !irow.modelData.used
                    icon: win.removing === irow.modelData.id ? "edit-delete" : "window-close"
                    size: Theme.px(26)
                    tip: win.removing === irow.modelData.id ? Tr.t("Click again: the image is removed") : Tr.t("Remove")
                    onClicked: { if (win.removing === irow.modelData.id) { win.removing = ""; win.run(["image-remove", irow.modelData.id]); } else win.removing = irow.modelData.id; }
                }
            }
        }
    }
}
