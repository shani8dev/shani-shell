// What a file looks like: the picture itself when it is one, its thumbnail when
// it has one (a video's frame, a PDF's first page - Files' freedesktop
// thumbnails), else the icon of its kind (a folder, a document, a sound, an archive).
import QtQuick
import qs.Common
import "FilePaths.js" as FilePaths
import "FileIcons.js" as FileIcons

Item {
    id: root
    property var entry: null
    property real size: Theme.px(36)
    property bool showImage: true          // false: the kind's icon, even for a picture
    property string thumbnail: ""          // a thumbnail PNG's path (Services/Files' thumbs), "" none

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

    Image {
        id: thumb
        anchors.fill: parent
        anchors.margins: 2
        visible: !root.isImage && root.showImage && root.thumbnail !== "" && status === Image.Ready
        source: !root.isImage && root.showImage && root.thumbnail !== "" ? "file://" + root.thumbnail : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        sourceSize: Qt.size(Math.round(root.size * 2), Math.round(root.size * 2))
    }

    Icon {
        anchors.fill: parent
        visible: !(root.isImage && root.showImage) && !thumb.visible
        name: FileIcons.iconFor(root.entry)
        size: root.size * 0.72
        color: root.entry && root.entry.isDir ? Theme.accent : Theme.dim
    }
}
