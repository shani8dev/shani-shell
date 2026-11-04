// The desktop: what is in ~/Desktop (xdg-user-dirs' name for it) over the
// wallpaper, under every window, and nothing while the folder is empty. They
// go where this layout leaves room: down the left - the control centre opens
// on the right and the pop-ups come in there - below the bar and the clock
// widget, above the dock. Connected drives come first, as Finder
// puts external disks there. "Use stacks" piles the files by kind (Images,
// Screenshots, Documents …) - a click fans a pile out. Double-click opens;
// drag to place (remembered), or onto an app to hand it the file;
// right-click: open, show in Files, what to do with it (convert, fit a size),
// rename, move to the trash. Settings > Personalisation > "Files on the
// desktop", with Clean up there. Input only over the icons, so the desktop
// widgets on the same layer stay draggable.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel
import qs.Common
import qs.Services

PanelWindow {
    id: win
    screen: Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "shani-desktop-icons"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: renaming !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    visible: Settings.loaded && Settings.data.desktopIcons && !Lock.locked && !Niri.overviewOpen && entries.length > 0
    mask: Region { item: menu.visible || stack.visible ? whole : iconsArea }

    readonly property string dir: Quickshell.env("XDG_DESKTOP_DIR") || Quickshell.env("HOME") + "/Desktop"
    property string selected: ""
    property string renaming: ""
    readonly property real cell: 96
    readonly property real top: Theme.barHeight + 20
    // the first row: under the clock widget while it sits at the top left
    readonly property real startY: {
        const w = Array.from(Settings.data.desktopWidgets || []);
        const c = (Settings.data.deskPos || {}).clock || { x: 24, y: 64 };
        return w.indexOf("clock") >= 0 && c.x < win.cell + 40 && c.y < 200 ? c.y + 150 : win.top;
    }

    // the folder is made first (as xdg-user-dirs would): a FolderListModel on a
    // folder that is not there lists / instead
    Process { running: true; command: ["mkdir", "-p", win.dir]; onExited: files.folder = "file://" + win.dir }
    FolderListModel {
        id: files
        showDirsFirst: true
        showHidden: false
        sortField: FolderListModel.Name
    }
    function kindOf(name, isDir) {
        if (isDir) return "folder";
        const e = (name.split(".").pop() || "").toLowerCase();
        if (/^screenshot/i.test(name)) return "screenshot";
        return /^(png|jpe?g|webp|gif|bmp|svg|avif|heic)$/.test(e) ? "image"
            : /^(mp4|mkv|webm|mov|avi)$/.test(e) ? "video"
            : /^(mp3|ogg|flac|wav|m4a|opus)$/.test(e) ? "audio"
            : e === "pdf" ? "pdf"
            : /^(zip|tar|gz|xz|7z|rar|zst)$/.test(e) ? "archive"
            : /^(odt|docx?|rtf|txt|md|ods|xlsx?|csv|odp|pptx?)$/.test(e) ? "document" : "other";
    }
    readonly property var kinds: ({
        folder: { label: Tr.t("Folders"), icon: "folder" }, image: { label: Tr.t("Images"), icon: "image-x-generic" },
        screenshot: { label: Tr.t("Screenshots"), icon: "applets-screenshooter" }, video: { label: Tr.t("Videos"), icon: "video-x-generic" },
        audio: { label: Tr.t("Music"), icon: "audio-x-generic" }, pdf: { label: Tr.t("PDFs"), icon: "application-pdf" },
        archive: { label: Tr.t("Archives"), icon: "package-x-generic" }, document: { label: Tr.t("Documents"), icon: "x-office-document" },
        other: { label: Tr.t("Other"), icon: "text-x-generic" }
    })
    // drives, then files or stacks: [{ key, type, name, path, icon, image, files, drive }]
    readonly property var entries: {
        const out = [];
        for (const d of Drives.drives)
            out.push({ key: "drive:" + d.dev, type: "drive", name: d.label || d.dev, icon: "drive-removable-media", drive: d });
        const fs = [];
        for (let i = 0; i < files.count; i++) {
            const name = files.get(i, "fileName"), path = files.get(i, "filePath"), dir = files.get(i, "fileIsDir");
            fs.push({ key: "file:" + name, type: "file", name: name, path: path, kind: win.kindOf(name, dir) });
        }
        if (Settings.data.deskStacks) {
            const groups = {};
            for (const f of fs) (groups[f.kind] = groups[f.kind] || []).push(f);
            for (const k of Object.keys(win.kinds))
                if (groups[k])
                    out.push({ key: "stack:" + k, type: "stack", name: win.kinds[k].label + " (" + groups[k].length + ")", icon: win.kinds[k].icon, files: groups[k],
                               image: (k === "image" || k === "screenshot") ? groups[k][groups[k].length - 1].path : "" });
        } else {
            for (const f of fs)
                out.push(Object.assign(f, { icon: win.kinds[f.kind].icon, image: (f.kind === "image" || f.kind === "screenshot") ? f.path : "" }));
        }
        return out;
    }
    // the next free slot: down the left, clear of the dock, then the next column
    function slot(i) {
        const rows = Math.max(1, Math.floor((win.height - win.startY - 110) / win.cell));
        return { x: 16 + Math.floor(i / rows) * win.cell, y: win.startY + (i % rows) * win.cell };
    }
    function posOf(key, i) { return (Settings.data.deskIconPos || {})[key] || slot(i); }
    function savePos(key, x, y) {
        const keep = JSON.parse(JSON.stringify(Settings.data.deskIconPos || {}));
        keep[key] = { x: Math.round(x / 8) * 8, y: Math.round(y / 8) * 8 };
        Settings.data.deskIconPos = keep;
    }
    function activate(e) {
        if (e.type === "drive") { if (e.drive.mount) Drives.open(e.drive); else Drives.mount(e.drive); }
        else if (e.type === "stack") { stack.entry = e; stack.visible = true; }
        else Qt.openUrlExternally("file://" + e.path);
    }
    function showInFiles(path) {
        Quickshell.execDetached(["gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1", "--object-path", "/org/freedesktop/FileManager1",
            "--method", "org.freedesktop.FileManager1.ShowItems", "['file://" + path.replace(/'/g, "%27") + "']", ""]);
    }
    function rename(path, to) {
        to = to.trim();
        if (to && to.indexOf("/") < 0) Quickshell.execDetached(["gio", "rename", path, to]);
        win.renaming = "";
    }

    Item { id: whole; anchors.fill: parent }
    MouseArea { anchors.fill: parent; visible: menu.visible || stack.visible; onClicked: { menu.visible = false; stack.visible = false; } }

    // the icons' bounding box: the input mask
    Item {
        id: iconsArea
        x: childrenRect.x
        y: childrenRect.y
        width: childrenRect.width
        height: childrenRect.height
        Repeater {
            model: win.entries
            Item {
                id: ic
                required property var modelData
                required property int index
                readonly property var p: win.posOf(modelData.key, index)
                x: p.x - iconsArea.x; y: p.y - iconsArea.y
                width: win.cell - 8
                height: win.cell - 4
                Accessible.role: Accessible.Button
                Accessible.name: modelData.name
                Accessible.onPressAction: win.activate(modelData)
                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: win.selected === ic.modelData.key ? Theme.accentSoft : area.containsMouse ? Theme.alpha(Theme.bg, 0.35) : "transparent"
                    border.width: win.selected === ic.modelData.key ? 1 : 0
                    border.color: Theme.accentLine
                }
                // a stack shows its top card offset behind it
                Rectangle {
                    visible: ic.modelData.type === "stack"
                    x: parent.width / 2 - 20; y: 2
                    width: 48; height: 48; radius: 8
                    rotation: 6
                    color: Theme.alpha(Theme.text, 0.15)
                }
                Image {
                    id: thumb
                    visible: status === Image.Ready
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 6
                    width: 48; height: 48
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(96, 96)
                    source: ic.modelData.image ? "file://" + ic.modelData.image : ""
                }
                AppIcon {
                    visible: !thumb.visible
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 6
                    implicitSize: 48
                    icon: ic.modelData.icon
                    name: ic.modelData.name
                }
                Text {
                    visible: win.renaming !== ic.modelData.path || !ic.modelData.path
                    anchors.top: parent.top
                    anchors.topMargin: 58
                    width: parent.width - 4
                    x: 2
                    horizontalAlignment: Text.AlignHCenter
                    text: ic.modelData.name
                    color: "white"
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.45)
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                TextField {
                    visible: ic.modelData.path !== undefined && win.renaming === ic.modelData.path
                    anchors.top: parent.top
                    anchors.topMargin: 56
                    width: parent.width + 40
                    x: -20
                    text: ic.modelData.name
                    onVisibleChanged: if (visible) input.forceActiveFocus()
                    onAccepted: win.rename(ic.modelData.path, text)
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    drag.target: ic
                    drag.threshold: 10
                    onPressed: win.selected = ic.modelData.key
                    onDoubleClicked: if (ic.modelData.type !== "stack") win.activate(ic.modelData)
                    onClicked: e => {
                        if (e.button === Qt.RightButton && ic.modelData.type === "file") {
                            menu.target = ic.modelData.path;
                            menu.x = Math.min(ic.x + iconsArea.x + e.x, win.width - menu.width - 8);
                            menu.y = Math.min(ic.y + iconsArea.y + e.y, win.height - menu.height - 8);
                            menu.visible = true;
                        } else if (ic.modelData.type === "stack")
                            win.activate(ic.modelData);
                    }
                    onReleased: if (drag.active) win.savePos(ic.modelData.key, ic.x + iconsArea.x, ic.y + iconsArea.y)
                }
                // dragged out onto an app: the file itself (text/uri-list)
                Drag.active: area.drag.active && ic.modelData.type === "file"
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.mimeData: ic.modelData.path ? { "text/uri-list": "file://" + ic.modelData.path } : {}
                Hint {
                    text: ic.modelData.type === "stack" ? Tr.t("Click to see them") : ic.modelData.type === "drive" ? Tr.t("Double-click to open the drive")
                        : Tr.t("Double-click to open, right-click for more")
                }
            }
        }
    }

    // a stack, fanned out: its files, each opening on a click
    Glass {
        id: stack
        property var entry: null
        visible: false
        strong: true
        radius: Theme.radiusLarge
        width: 380
        height: Math.min(win.height - win.top - 120, stackCol.implicitHeight + 24)
        x: win.cell + 24
        y: win.startY
        z: 20
        Flickable {
            anchors.fill: parent
            anchors.margins: 12
            contentHeight: stackCol.implicitHeight
            clip: true
            Column {
                id: stackCol
                width: parent.width
                spacing: 2
                Text { text: stack.entry ? stack.entry.name : ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; font.weight: Font.DemiBold; bottomPadding: 6 }
                Repeater {
                    model: stack.entry ? stack.entry.files : []
                    ListRow {
                        required property var modelData
                        width: stackCol.width
                        icon: win.kinds[modelData.kind].icon
                        title: modelData.name
                        onClicked: { stack.visible = false; Qt.openUrlExternally("file://" + modelData.path); }
                    }
                }
            }
        }
    }

    // the right-click menu
    Glass {
        id: menu
        property string target: ""
        visible: false
        strong: true
        radius: 12
        width: 220
        height: menuCol.implicitHeight + 12
        z: 20
        Column {
            id: menuCol
            x: 6; y: 6
            width: parent.width - 12
            Repeater {
                model: [{ label: Tr.t("Open"), run: () => Qt.openUrlExternally("file://" + menu.target) },
                        { label: Tr.t("Show in Files"), run: () => win.showInFiles(menu.target) },
                        { label: Tr.t("What to do with it…"), run: () => FileActions.offer([menu.target]) },
                        { label: Tr.t("Rename"), run: () => win.renaming = menu.target },
                        { label: Tr.t("Move to the trash"), run: () => Quickshell.execDetached(["gio", "trash", menu.target]) }]
                ListRow {
                    required property var modelData
                    width: menuCol.width
                    icon: ""
                    title: modelData.label
                    onClicked: { menu.visible = false; modelData.run(); }
                }
            }
        }
    }
}
