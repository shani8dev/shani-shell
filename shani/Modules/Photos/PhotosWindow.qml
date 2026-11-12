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
    implicitWidth: 1000
    implicitHeight: 700

    readonly property string pictures: Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")
    property var photos: []           // [{ path, time (s), month "November 2026" }]
    property bool scanning: false
    property string filter: "all"     // all | camera | screenshots
    readonly property var shown: photos.filter(p => filter === "all" || (filter === "camera" ? /\/Camera\//.test(p.path) : /\/Screenshots\//.test(p.path)))
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
    onVisibleChanged: if (visible) scan()
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
            }
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.photos = false

        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
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
                Text {
                    text: win.scanning ? Tr.t("Looking…") : win.shown.length + " " + Tr.t("photos")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                }
                IconButton { size: 30; icon: "view-refresh"; tip: Tr.t("Look again"); onClicked: win.scan() }
                IconButton { size: 30; icon: "folder-pictures"; tip: Tr.t("Open Pictures in Files"); onClicked: Files.show(win.pictures) }
            }

            ListView {
                id: monthList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 14
                boundsBehavior: Flickable.StopAtBounds
                model: win.months
                // one month: its name, then its photos as square tiles
                delegate: Column {
                    id: monthCol
                    required property var modelData
                    width: monthList.width
                    spacing: 8
                    readonly property int cols: Math.max(2, Math.floor(width / 150))
                    readonly property real cell: width / cols
                    Text {
                        text: monthCol.modelData.month + "  ·  " + monthCol.modelData.items.length
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 14 * Theme.fontScale
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
                                    anchors.margins: 3
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
