// One round keypad key: a digit with its letters, a short press and, on 0, a
// long press for "+". It only reports what was pressed; the caller decides
// whether that becomes a digit in a number or a tone in a call.
import QtQuick
import qs.Common

Rectangle {
    id: key
    required property string digit
    required property string letters
    property real keySize: Theme.px(56)
    property var digitHandler: function (digit) {}
    property var longHandler: function () {}
    property bool fired: false

    width: key.keySize
    height: key.keySize
    radius: width / 2
    color: area.pressed ? Theme.pressed : (area.containsMouse ? Theme.hover : Theme.surface2)
    border.width: 1
    border.color: Theme.stroke

    Accessible.role: Accessible.Button
    Accessible.name: key.digit === "0" ? Tr.t("0, or plus") : key.digit + " " + key.letters
    Accessible.onPressAction: key.digitHandler(key.digit)

    Column {
        anchors.centerIn: parent
        spacing: 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: key.digit
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(22) * Theme.fontScale
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: key.letters !== ""
            text: key.letters
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(9) * Theme.fontScale
        }
    }

    function press() { key.digitHandler(key.digit) }
    function hold() { if (key.digit === "0") key.longHandler() }

    Timer {
        id: holdTimer
        interval: 450
        onTriggered: { key.fired = true; key.hold() }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: { key.fired = false; if (key.digit === "0") holdTimer.restart(); }
        onReleased: { holdTimer.stop(); if (!key.fired) key.press(); }
        onCanceled: holdTimer.stop()
    }
    KeyFocus {
        enabled: key.visible
        name: key.Accessible.name
        menuable: key.digit === "0"
        onActivated: key.press()
        onMenu: key.hold()
    }
}
