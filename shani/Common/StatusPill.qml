// Small rounded status label with an optional dot, tone: ok | warn | error | accent | neutral.
// Ported from Ananta UI (ananta-os/apps/ui/StatusPill.qml) onto the shell's palette.
import QtQuick
import QtQuick.Layouts
import qs.Common

Rectangle {
    id: pill
    property string text: ""
    property string tone: "accent"
    property bool dot: true
    readonly property color toneColor: Theme.toneColor(tone)

    implicitWidth: row.implicitWidth + Theme.px(20)
    implicitHeight: Theme.px(24)
    radius: height / 2
    color: Theme.alpha(toneColor, 0.14)
    border.width: 1
    border.color: Theme.alpha(toneColor, 0.3)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.px(6)
        Rectangle {
            visible: pill.dot
            width: Theme.px(6)
            height: width
            radius: width / 2
            color: pill.toneColor
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: pill.text
            color: pill.toneColor
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: pill.text
}
