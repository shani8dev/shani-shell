// Hover peek: a small, non-focusing popup after the pointer rests on a file
// path or a dock tile. Files show their content (image / first lines of text)
// or icon + size; dock tiles show a grim window capture. Never steals focus —
// Space or click in the app still opens the real thing. Copy of Common/Hint.qml's
// LazyLoader + PopupWindow pattern so a thin dock never clips the popup.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../Common/FileIcons.js" as FileIcons

Item {
    id: root
    property string path: ""                 // file to peek (mutually exclusive with win)
    property var win: null                   // Niri window to preview (dock tiles)
    property string output: ""
    property bool active: false              // caller owns the hover state
    property int delay: 420

    HoverHandler { id: hover }
    property bool hovered: hover.hovered || root.active
    function forceActive() { root.active = true; }
    function cancel() { root.active = false; wait.stop(); root.showPeek = false; WindowPreview.clear(); }
    Timer {
        id: wait
        interval: root.delay
        onTriggered: root.showPeek = true
    }
    property bool showPeek: false
    Connections {
        target: root
        function onHoveredChanged() {
            if (root.hovered) wait.restart();
            else { wait.stop(); root.showPeek = false; WindowPreview.clear(); }
        }
    }
    LazyLoader {
        active: root.showPeek && (root.path !== "" || root.win !== null)
        PopupWindow {
            visible: true
            anchor.item: root
            anchor.rect.x: root.width / 2
            anchor.rect.y: -6
            anchor.edges: Edges.Top
            anchor.gravity: Edges.Top
            implicitWidth: peekCol.implicitWidth + 16
            implicitHeight: Math.min(300, peekCol.implicitHeight + 16)
            color: "transparent"
            onVisibleChanged: {
                if (!visible) { textProc.running = false; WindowPreview.clear(); }
                else if (root.win !== null) WindowPreview.capture(root.win, root.output);
                else if (root.path !== "") {
                    textProc.command = ["sh", "-c", 'head -c 4096 "$1" 2>/dev/null', "sh", root.path];
                    textProc.running = true;
                }
            }
            Glass {
                anchors.fill: parent
                strong: true
                radius: Theme.radius
                ColumnLayout {
                    id: peekCol
                    anchors { fill: parent; margins: Theme.px(8) }
                    spacing: Theme.px(4)

                    // window preview (dock tile hover)
                    Image {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(180, sourceSize.height)
                        visible: root.win !== null && WindowPreview.shown
                        source: WindowPreview.shown ? "file://" + WindowPreview.path : ""
                        fillMode: Image.PreserveAspectFit
                        cache: false
                        sourceSize: Qt.size(360, 220)
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: root.win !== null
                        text: WindowPreview.title || (root.win ? (root.win.title || root.win.app_id || "") : "")
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                        elide: Text.ElideRight
                    }

                    // file preview
                    readonly property string ext: root.path.indexOf(".") > 0 ? root.path.split(".").pop().toLowerCase() : ""
                    readonly property bool imageFile: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif"].indexOf(ext) >= 0
                    Image {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(180, 180)
                        visible: root.win === null && peekCol.imageFile
                        source: peekCol.imageFile ? "file://" + root.path.split("/").map(encodeURIComponent).join("/") : ""
                        fillMode: Image.PreserveAspectFit
                        cache: false
                        sourceSize: Qt.size(360, 180)
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(120, implicitHeight)
                        visible: root.win === null && !peekCol.imageFile && textProc.text.trim() !== ""
                        text: textProc.text
                        color: Theme.text
                        opacity: 0.8
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        maximumLineCount: 8
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.win === null
                        spacing: Theme.px(6)
                        Icon {
                            name: FileIcons.iconFor({ ext: "." + peekCol.ext, isDir: false, image: peekCol.imageFile })
                            size: Theme.px(16)
                            color: Theme.dim
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.path.split("/").pop()
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                            elide: Text.ElideMiddle
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: root.win === null && textProc.text.trim() === "" && !peekCol.imageFile
                        text: Tr.t("Press Space in Files to look closer")
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.px(9) * Theme.fontScale
                    }
                }
                Process {
                    id: textProc
                    property string text: ""
                    stdout: StdioCollector { onStreamFinished: textProc.text = text }
                }
            }
        }
    }
}
