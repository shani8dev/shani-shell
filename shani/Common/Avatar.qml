// The person's picture: ~/.face, or the AccountsService icon (readable by the
// greeter too); their initial on the accent colour when there is none.
import Quickshell
import Quickshell.Widgets
import QtQuick

Item {
    id: root
    property string user: Quickshell.env("USER") || ""
    property string home: Quickshell.env("HOME") || ""
    property real size: 72
    implicitWidth: size
    implicitHeight: size

    // first one that loads wins
    readonly property var candidates: [
        root.home !== "" && root.user === (Quickshell.env("USER") || "") ? "file://" + root.home + "/.face" : "",
        "file:///var/lib/AccountsService/icons/" + root.user
    ].filter(x => x !== "")
    property int tried: 0

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.accent
        visible: pic.status !== Image.Ready
        Text {
            anchors.centerIn: parent
            text: root.user.slice(0, 1).toUpperCase()
            color: Theme.accentInk
            font.family: Theme.font
            font.pixelSize: root.size * 0.42
            font.weight: Font.DemiBold
        }
    }
    ClippingRectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        visible: pic.status === Image.Ready
        Image {
            id: pic
            anchors.fill: parent
            // a changed picture has the same path: the revision makes it a new URL
            source: root.candidates[root.tried] ? root.candidates[root.tried] + (Ui.faceRev ? "?" + Ui.faceRev : "") : ""
            sourceSize: Qt.size(root.size * 2, root.size * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            onStatusChanged: if (status === Image.Error && root.tried < root.candidates.length - 1) root.tried++
        }
    }
}
