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
    readonly property var shown: photos.filter(p => activeAlbum === "" || activeAlbum === "all" || albums.find(a => a.name === activeAlbum)?.members?.includes(p.path))
    // [{ month, items: [...] }], newest first
    readonly property var months: {
        const out = [];
        for (const p of shown) {
            if (!out.length || out[out.length - 1].month !== p.month)
                out.push({ month: p.month, items: [] });
            out[out.length - 1].items.push(p);
        }
        return out;
    }

    function scan() {
        scanning = true;
        lister.command = ["sh", "-c", 'find "$1" -maxdepth 4 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.avif" -o -iname "*.bmp" \\) -not -path "*/.*" -printf "%T@ %p\\n" 2>/dev/null | sort -rn | head -5000', "sh", pictures];
        lister.running = true;
    }
    Component.onCompleted: scan()
    onVisibleChanged: if (visible) { scan(); albumLister.running = true; }

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
                Text {
                    text: win.scanning ? Tr.t("Looking…") : win.shown.length + " " + Tr.t("photos")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                IconButton { size: Theme.px(30); icon: "view-refresh"; tip: Tr.t("Look again"); onClicked: win.scan() }
                IconButton { size: Theme.px(30); icon: "folder-pictures"; tip: Tr.t("Open Pictures in Files"); onClicked: Files.show(win.pictures) }
            }

            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: monthList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.px(14)
                boundsBehavior: Flickable.StopAtBounds
                model: win.months
                // one month: its name, then its photos as square tiles
                delegate: Column {
                    id: monthCol
                    required property var modelData
                    width: monthList.width
                    spacing: Theme.px(8)
                    readonly property int cols: Math.max(2, Math.floor(width / 150))
                    readonly property real cell: width / cols
                    Text {
                        text: monthCol.modelData.month + "  ·  " + monthCol.modelData.items.length
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
                                    Rectangle { anchors.fill: parent; color: "transparent"; radius: parent.radius; border.width: tileArea.containsMouse ? 2 : 0; border.color: Theme.accent }
                                }
                                Accessible.role: Accessible.Graphic
                                Accessible.name: tile.modelData.path.split("/").pop()
                                Accessible.onPressAction: Viewer.open(tile.modelData.path)
                                MouseArea { id: tileArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Viewer.open(tile.modelData.path) }
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
        }
    }
}
