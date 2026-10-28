// The translucent card every surface is drawn on.
import QtQuick

Rectangle {
    property bool strong: false
    radius: Theme.radius
    color: strong ? Theme.glassStrong : Theme.glass
    border.width: 1
    border.color: Theme.stroke
}
