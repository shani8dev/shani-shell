// A hover label for anything that shows only an icon or a number - what it is,
// what a click does, and its key when it has one ("Apps · Super"). Put it
// inside the item: Hint { text: "…"; keys: "Super" }. It appears after a
// moment of hovering, below the item (above it with `above`, for the dock), in
// its own popup surface, so the bar's and the dock's thin windows never clip
// it; it is made only while shown.
import Quickshell
import QtQuick
import qs.Common

Item {
    id: root
    property string text: ""
    property string keys: ""             // a shortcut to show beside it
    property bool above: false
    property bool enabled: true
    anchors.fill: parent
    HoverHandler { id: hover }
    property bool shown: false
    Timer { id: wait; interval: 550; onTriggered: root.shown = true }
    Connections {
        target: hover
        function onHoveredChanged() {
            if (hover.hovered && root.enabled && root.text !== "") wait.restart();
            else { wait.stop(); root.shown = false; }
        }
    }
    LazyLoader {
        active: root.shown
        PopupWindow {
            visible: true
            anchor.item: root
            anchor.rect.x: root.width / 2
            anchor.rect.y: root.above ? -6 : root.height + 6
            anchor.edges: root.above ? Edges.Top : Edges.Bottom
            anchor.gravity: root.above ? Edges.Top : Edges.Bottom
            implicitWidth: label.implicitWidth + 20
            implicitHeight: 28
            color: "transparent"
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Theme.glassStrong
                border.width: 1
                border.color: Theme.stroke
                Row {
                    id: label
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: root.text; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                    Rectangle {
                        visible: root.keys !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: keyText.implicitWidth + 10
                        height: 18
                        radius: 5
                        color: Theme.alpha(Theme.text, 0.1)
                        Text { id: keyText; anchors.centerIn: parent; text: root.keys; color: Theme.dim; font.family: Theme.font; font.pixelSize: 10.5 * Theme.fontScale }
                    }
                }
            }
        }
    }
}
