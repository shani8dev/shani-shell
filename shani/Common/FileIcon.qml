// What a file looks like: the picture itself when it is one, else the icon of
// its kind (a folder, a document, a sound, a video, an archive).
import QtQuick
import qs.Common
import "FilePaths.js" as FilePaths
import "FileIcons.js" as FileIcons

Item {
    id: root
    property var entry: null
    property real size: 36
    property bool showImage: true          // false: the kind's icon, even for a picture

    implicitWidth: size
    implicitHeight: size

    readonly property bool isImage: entry && entry.image === true

    Image {
        anchors.fill: parent
        anchors.margins: root.showImage ? 2 : 0
        visible: root.isImage && root.showImage
        source: root.isImage ? FilePaths.fileUrl(root.entry.path) : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        // the decode at the size it is drawn: a 4000px photo would be read whole
        sourceSize: Qt.size(Math.round(root.size * 2), Math.round(root.size * 2))
    }

    Icon {
        anchors.fill: parent
        visible: !(root.isImage && root.showImage)
        name: FileIcons.iconFor(root.entry)
        size: root.size * 0.72
        color: root.entry && root.entry.isDir ? Theme.accent : Theme.dim
    }
}
