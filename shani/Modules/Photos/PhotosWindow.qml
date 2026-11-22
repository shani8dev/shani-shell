// Photos: every picture in Pictures (the camera's, the screenshots, the
// wallpapers…), newest first and by month - Photos, Gallery, Shotwell. A click
// opens it in the Image Viewer, with its folder around it. Small copies are
// what the grid draws (sourceSize), so a thousand photos stay light.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Photos"
    visible: Ui.photos
    onGone: Ui.photos = false
    implicitWidth: Theme.px(1000)
    implicitHeight: Theme.px(700)

    readonly property string pictures: Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")
    property var photos: []           // [{ path, time (s), month "November 2026" }]
    property bool scanning: false
    property string filter: "all"     // all | camera | screenshots
    property string groupBy: "month"  // day | month | year
    property string sortOrder: "newest"  // newest | oldest | name
    property bool importBusy: false
    property string importNote: ""
    property var selected: []         // multi-select: batch trash / album add
    property string detailPath: ""    // the photo the details panel describes
    property bool detailsShown: false
    property var meta: ({})           // path -> { rating, tags }, kept in shani-photos/meta.json
    readonly property var shown: photos.filter(p =>
        (filter === "all" || (filter === "camera" ? /\/Camera\/|\/DCIM\/|\/camera\//i.test(p.path) : /\/Screenshot/i.test(p.path))) &&
        (activeAlbum === "" || activeAlbum === "all" || albums.find(a => a.name === activeAlbum)?.members?.includes(p.path)))
    // [{ key, items: [...] }] — the key is a day, a month or a year. The sort
    // order is applied here (not in scan's `sort -rn`) so it works for every
    // grouping; same-key groups are merged so a name sort cannot split a month.
    readonly property var groups: {
        const fmt = win.groupBy === "day" ? "d MMM yyyy" : win.groupBy === "year" ? "yyyy" : "MMMM yyyy";
        let list = shown;
        if (win.sortOrder === "oldest") list = list.slice().sort((a, b) => a.time - b.time);
        else if (win.sortOrder === "name") list = list.slice().sort((a, b) =>
            a.path.split("/").pop().localeCompare(b.path.split("/").pop()));
        const out = [];
        for (const p of list) {
            const key = Qt.formatDate(new Date(p.time * 1000), fmt);
            let group = out.find(g => g.key === key);
            if (!group) { group = { key: key, items: [] }; out.push(group); }
            group.items.push(p);
        }
        return out;
    }

    // ---- per-photo ratings and tags (path-keyed, beside the albums) --------------
    readonly property string metaFile: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/shani-photos/meta.json"
    readonly property string metaWriteCode: 'import json,sys,os\np=sys.argv[1]\nos.makedirs(os.path.dirname(p),exist_ok=True)\nopen(p,"w").write(json.dumps(json.loads(sys.argv[2])))'
    function loadMeta() { metaLister.running = true; }
    function saveMeta() {
        metaWrite.command = ["python3", "-c", win.metaWriteCode, win.metaFile, JSON.stringify(win.meta)];
        metaWrite.running = true;
    }
    function ratingOf(path) { return (win.meta[path] && win.meta[path].rating) || 0; }
    function tagsOf(path) { return (win.meta[path] && win.meta[path].tags) || ""; }
    function setRating(path, stars) {
        if (!path) return;
        const m = Object.assign({}, win.meta);
        m[path] = Object.assign({ tags: "" }, m[path], { rating: stars });
        win.meta = m;
        saveMeta();
    }
    function setTags(path, tags) {
        if (!path) return;
        const m = Object.assign({}, win.meta);
        m[path] = Object.assign({ rating: 0 }, m[path], { tags: tags });
        win.meta = m;
        saveMeta();
    }
    Process {
        id: metaLister
        command: ["sh", "-c", 'cat "$1" 2>/dev/null || echo "{}"', "sh", win.metaFile]
        stdout: StdioCollector {
            onStreamFinished: { try { win.meta = JSON.parse(text) || {}; } catch (e) { win.meta = {}; } }
        }
    }
    Process { id: metaWrite }

    // ---- multi-select ------------------------------------------------------------
    function toggleSelect(path) {
        win.selected = win.selected.indexOf(path) < 0 ? win.selected.concat([path]) : win.selected.filter(p => p !== path);
    }
    function clearSelect() { win.selected = []; }
    function trashSelected() {
        if (!win.selected.length) return;
        const paths = win.selected.slice();
        Files.trash(paths, r => {
            if (r && r.error) win.importNote = Tr.t("Could not move to trash: %1", r.error);
            win.selected = [];
            win.scan();
        });
    }
    function albumSelected() {
        if (!win.selected.length) return;
        const name = (win.newAlbumName || "").trim() || Tr.t("Selection");
        Photos.createAlbum(name, win.selected.slice());
        win.newAlbumName = "";
        win.selected = [];
        win.albumLister.running = true;
    }
    onDetailPathChanged: if (win.detailPath) PhotoMeta.read(win.detailPath)

    function scan() {
        scanning = true;
        lister.command = ["sh", "-c", 'find "$1" -maxdepth 4 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.avif" -o -iname "*.bmp" \\) -not -path "*/.*" -printf "%T@ %p\\n" 2>/dev/null | sort -rn | head -5000', "sh", pictures];
        lister.running = true;
    }
    Component.onCompleted: { scan(); loadMeta(); }
    onVisibleChanged: if (visible) { scan(); albumLister.running = true; loadMeta(); }

    // the Viewer's edit mode is its crop / rotate / markup mode
    function adjust(path) {
        if (!path) return;
        Viewer.open(path);
        Viewer.startEdit();
    }

    // ---- import from a mounted phone / camera / USB -------------------------------
    function importPhotos(paths) {
        if (!paths || !paths.length || importer.running) return;
        importer.count = paths.length;
        importer.command = ["sh", "-c", 'd=$1; shift; mkdir -p -- "$d" && cp -n -- "$@" "$d"', "sh", win.pictures].concat(paths);
        win.importBusy = true;
        win.importNote = Tr.t("Copying %1 photo%2…", paths.length, paths.length === 1 ? "" : "s");
        importer.running = true;
    }
    Process {
        id: importer
        property int count: 0
        property string err: ""
        stderr: StdioCollector { onStreamFinished: importer.err = text.trim().split("\n").pop() || "" }
        onExited: code => {
            win.importBusy = false;
            if (code === 0) {
                win.importNote = Tr.t("Imported %1 photo%2", importer.count, importer.count === 1 ? "" : "s");
                win.scan();
            } else {
                win.importNote = Tr.t("Import failed: %1", importer.err || Tr.t("copy error"));
            }
        }
    }

    // ---- albums ------------------------------------------------------------------
    property var albums: []              // [{ name, members: [paths] }] — user albums
    property string activeAlbum: ""      // the selected album name, "" for All
    property string newAlbumName: ""

    function refresh() { if (lister.running) lister.running = true; if (albumLister.running) albumLister.running = true; }

    Process {
        id: albumLister
        command: ["sh", "-c", 'd="${XDG_DATA_HOME:-$HOME/.local/share}/shani-photos/albums.json"; [ -f "$d" ] && cat "$d" || echo "[]"']
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.albums = JSON.parse(text); } catch (e) { win.albums = []; }
            }
        }
    }

    function createAlbum(name, photoPaths) {
        Quickshell.execDetached(["sh", "-c",
            'd="$1/albums.json"; mkdir -p "$2"; ex=$(cat "$d" 2>/dev/null || echo "[]");'
            + 'echo "$ex" | python3 -c "import json,sys; a=json.loads(sys.stdin.read() or \"[]\"); a.append({\\\"name\\\":$3, \\\"members\\\":$4}); print(json.dumps(a))" > "$d.tmp" 2>/dev/null && mv "$d.tmp" "$d" || true'
        , "sh", Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share") + "/shani-photos", Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share") + "/shani-photos", JSON.stringify(String(name)), JSON.stringify(photoPaths)]);
    }
    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const at = line.indexOf(" ");
                    if (at <= 0)
                        continue;
                    const t = parseFloat(line.substring(0, at));
                    out.push({ path: line.substring(at + 1), time: t, month: Qt.formatDate(new Date(t * 1000), "MMMM yyyy") });
                }
                win.photos = out;
                win.scanning = false;
                if (win.activeAlbum !== "")
                    win.activeAlbum = win.activeAlbum; // re-evaluate shown filter
            }
        }
    }

    // keep albums refreshed on scan
    onShownChanged: {}
    function _refreshAlbums() { if (albumLister.running) albumLister.running = true; }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.photos = false

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(10)
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [["all", Tr.t("All")], ["camera", Tr.t("Camera")], ["screenshots", Tr.t("Screenshots")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.filter === modelData[0]
                        onClicked: win.filter = modelData[0]
                    }
                }
                Repeater {
                    model: [["day", Tr.t("Day")], ["month", Tr.t("Month")], ["year", Tr.t("Year")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.groupBy === modelData[0]
                        onClicked: win.groupBy = modelData[0]
                    }
                }
                // sort order: newest (the scan default), oldest or by file name
                Repeater {
                    model: [["newest", Tr.t("Newest")], ["oldest", Tr.t("Oldest")], ["name", Tr.t("Name")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.sortOrder === modelData[0]
                        onClicked: win.sortOrder = modelData[0]
                    }
                }
                Item { Layout.fillWidth: true }
                // ---- albums ----
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    visible: win.albums.length > 0
                    Repeater {
                        model: win.albums
                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: Math.min(label.implicitWidth + 30, 120)
                            height: Theme.px(26)
                            radius: Theme.px(13)
                            color: win.activeAlbum === modelData.name ? Theme.accent : (area.containsMouse ? Theme.hover : Theme.surface1)
                            Text {
                                id: label
                                anchors.centerIn: parent
                                text: modelData.name + " (" + (modelData.members ? modelData.members.length : 0) + ")"
                                color: win.activeAlbum === modelData.name ? "white" : Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(10) * Theme.fontScale
                                elide: Text.ElideMiddle
                            }
                            MouseArea { id: area; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { win.activeAlbum = win.activeAlbum === modelData.name ? "" : modelData.name; } }
                        }
                    }
                }
                // "New album" button
                Button {
                    visible: true
                    text: Tr.t("+ Album")
                    flat: true
                    onClicked: {
                        // Create an album from current filter
                        const selected = win.shown;
                        if (selected.length > 0) {
                            const name = selected[0].split("/").slice(-2, -1)[0] + (selected.length > 1 ? " +" + (selected.length - 1) : "");
                            Photos.createAlbum(name, selected);
                        }
                    }
                }
                Button {
                    text: Tr.t("Import…")
                    flat: true
                    enabled: !win.importBusy
                    onClicked: FilePicker.open({
                        mode: "open", multiple: true,
                        title: Tr.t("Photos to import (phone, camera, USB)"),
                        filters: ["jpg", "jpeg", "png", "webp", "gif", "avif", "bmp", "heic", "heif"],
                        onPicked: paths => win.importPhotos(paths)
                    })
                }
                Text {
                    text: win.scanning ? Tr.t("Looking…") : win.shown.length + " " + Tr.t("photos")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                IconButton { size: Theme.px(30); icon: "view-refresh"; tip: Tr.t("Look again"); onClicked: win.scan() }
                IconButton { size: Theme.px(30); icon: "folder-pictures"; tip: Tr.t("Open Pictures in Files"); onClicked: Files.show(win.pictures) }
                IconButton { size: Theme.px(30); icon: "document-properties"; tip: Tr.t("Details"); on: win.detailsShown; onClicked: win.detailsShown = !win.detailsShown }
            }
            // batch operations on the multi-selection (Ctrl/Shift-click tiles)
            RowLayout {
                Layout.fillWidth: true
                visible: win.selected.length > 0
                spacing: Theme.px(6)
                Text {
                    text: Tr.t("%1 selected", win.selected.length)
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                TextField {
                    id: albumField
                    Layout.preferredWidth: Theme.px(140)
                    placeholderText: Tr.t("Album name")
                    text: win.newAlbumName
                    onTextChanged: win.newAlbumName = text
                }
                Button { text: Tr.t("Add to album"); flat: true; onClicked: win.albumSelected() }
                Button { text: Tr.t("Move to trash"); flat: true; onClicked: win.trashSelected() }
                Button { text: Tr.t("Clear"); flat: true; onClicked: win.clearSelect() }
                Item { Layout.fillWidth: true }
            }
            Text {
                visible: win.importNote !== ""
                Layout.fillWidth: true
                text: win.importNote
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.px(8)
            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: monthList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.px(14)
                boundsBehavior: Flickable.StopAtBounds
                model: win.groups
                // one group: its name, then its photos as square tiles
                delegate: Column {
                    id: monthCol
                    required property var modelData
                    width: monthList.width
                    spacing: Theme.px(8)
                    readonly property int cols: Math.max(2, Math.floor(width / 150))
                    readonly property real cell: width / cols
                    Text {
                        text: monthCol.modelData.key + "  ·  " + monthCol.modelData.items.length
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(14) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Grid {
                        columns: monthCol.cols
                        spacing: 0
                        Repeater {
                            model: monthCol.modelData.items
                            Item {
                                id: tile
                                required property var modelData
                                width: monthCol.cell
                                height: monthCol.cell
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(3)
                                    radius: Theme.radiusSmall
                                    color: Theme.surface1
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        sourceSize: Qt.size(300, 300)
                                        source: "file://" + tile.modelData.path.split("/").map(encodeURIComponent).join("/")
                                    }
                                    Rectangle { anchors.fill: parent; color: "transparent"; radius: parent.radius; border.width: win.selected.indexOf(tile.modelData.path) >= 0 ? 3 : (tileArea.containsMouse ? 2 : 0); border.color: Theme.accent }
                                }
                                Accessible.role: Accessible.Graphic
                                Accessible.name: tile.modelData.path.split("/").pop()
                                Accessible.onPressAction: Viewer.open(tile.modelData.path)
                                MouseArea {
                                    id: tileArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        const p = tile.modelData.path;
                                        if (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) {
                                            win.toggleSelect(p);
                                            return;
                                        }
                                        if (win.selected.length) { win.clearSelect(); return; }
                                        win.detailPath = p;
                                        Viewer.open(p);
                                    }
                                }
                                RowLayout {
                                    anchors { right: parent.right; bottom: parent.bottom; margins: Theme.px(4) }
                                    spacing: Theme.px(2)
                                    IconButton {
                                        size: Theme.px(22)
                                        icon: "media-playlist-play"
                                        tip: Tr.t("Slideshow from here")
                                        opacity: tileArea.containsMouse ? 1 : 0.7
                                        onClicked: { Viewer.open(tile.modelData.path); Viewer.toggleSlideshow(); }
                                    }
                                    IconButton {
                                        size: Theme.px(22)
                                        icon: "user-trash"
                                        tip: Tr.t("Move to trash")
                                        opacity: tileArea.containsMouse ? 1 : 0.7
                                        onClicked: { Viewer.trash(); win.scan(); }
                                    }
                                    IconButton {
                                        size: Theme.px(22)
                                        icon: "document-edit"
                                        tip: Tr.t("Adjust…")
                                        opacity: tileArea.containsMouse ? 1 : 0.7
                                        onClicked: win.adjust(tile.modelData.path)
                                    }
                                }
                                KeyFocus { name: tile.modelData.path.split("/").pop(); onActivated: Viewer.open(tile.modelData.path) }
                            }
                        }
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: !win.scanning && win.shown.length === 0
                    icon: "folder-pictures"
                    title: Tr.t("No photos yet")
                    subtitle: Tr.t("Pictures in %1 show here — the camera's and the screenshots too").arg(win.pictures.replace(Quickshell.env("HOME"), "~"))
                }
            }
            // ---- EXIF, rating and tags for the last-clicked photo ------------------
            Rectangle {
                visible: win.detailsShown
                Layout.preferredWidth: Theme.px(260)
                Layout.minimumWidth: Theme.px(200)
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.stroke
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(10)
                    spacing: Theme.px(8)
                    Text {
                        Layout.fillWidth: true
                        text: win.detailPath ? win.detailPath.split("/").pop() : Tr.t("No photo selected")
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(13) * Theme.fontScale
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                    }
                    Repeater {
                        model: PhotoMeta.details
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text {
                                text: modelData.label
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.value
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                                elide: Text.ElideRight
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("Rating")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Row {
                        spacing: Theme.px(2)
                        Repeater {
                            model: 5
                            Text {
                                required property int index
                                text: (index + 1) <= win.ratingOf(win.detailPath) ? "★" : "☆"
                                color: Theme.accent
                                font.pixelSize: Theme.px(18) * Theme.fontScale
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.setRating(win.detailPath, index + 1) }
                            }
                        }
                    }
                    TextField {
                        id: tagsField
                        Layout.fillWidth: true
                        placeholderText: Tr.t("Tags (comma separated)")
                        text: win.tagsOf(win.detailPath)
                        onEditingFinished: win.setTags(win.detailPath, text)
                    }
                    Item { Layout.fillHeight: true }
                }
            }
            }  // RowLayout
        }      // main ColumnLayout
    }          // Item
}              // AppWindow
