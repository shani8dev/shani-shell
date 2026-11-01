// A text button: plain, accent (primary) or danger.
// Press gives a scale-down + ripple; hover brightens; disabled dims.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property string text
    property string kind: "plain"      // plain | primary | danger
    signal clicked()

    Accessible.role: Accessible.Button
    Accessible.name: root.text
    Accessible.onPressAction: root.clicked()

    implicitWidth: label.implicitWidth + 28
    implicitHeight: 36
    radius: 10
    clip: true

    // ---- base fill ---------------------------------------------------------
    color: {
        if (!enabled) return Theme.alpha(Theme.text, 0.12)
        if (kind === "primary") return area.pressed ? Theme.accentPressed : (area.containsMouse ? Theme.accentHover : Theme.accent)
        if (kind === "danger") return area.pressed ? Theme.alpha(Theme.danger, 0.45) : (area.containsMouse ? Theme.alpha(Theme.danger, 0.35) : Theme.alpha(Theme.danger, 0.22))
        return area.pressed ? Theme.pressed : (area.containsMouse ? Theme.hover : "transparent")
    }
    border.width: kind === "plain" && !area.containsMouse ? 0 : 1
    border.color: kind === "plain" ? Theme.stroke : (area.pressed ? Theme.accentPressed : Theme.accentLine)
    opacity: enabled ? 1 : 0.5

    // ---- ripple on press ---------------------------------------------------
    Rectangle {
        id: ripple
        width: 0; height: 0
        radius: width / 2
        color: kind === "primary" ? "white" : Theme.text
        opacity: area.pressed ? 0.25 : 0
        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        anchors.centerIn: area.pressed ? Qt.point(area.mouseX, area.mouseY) : Qt.point(parent.width / 2, parent.height / 2)
    }

    // ---- subtle scale-down on press ---------------------------------------
    transform: Scale {
        origin.x: area.pressed ? area.mouseX : width / 2
        origin.y: area.pressed ? area.mouseY : height / 2
        xScale: area.pressed ? 0.97 : 1
        yScale: area.pressed ? 0.97 : 1
        Behavior on xScale { NumberAnimation { duration: 120 } }
        Behavior on yScale { NumberAnimation { duration: 120 } }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.kind === "primary" ? Theme.accentInk : root.kind === "danger" ? Theme.danger : Theme.text
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
        font.weight: Font.DemiBold
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.enabled
        onClicked: root.clicked()
    }
}
