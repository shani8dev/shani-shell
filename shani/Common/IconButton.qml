// A round icon button: hover and press states, optional "on" fill.
// Press gives a scale-down + ripple; hover brightens.
import QtQuick

Rectangle {
    id: root
    property string icon
    property bool on: false
    property real size: 32
    property color iconColor: on ? Theme.accentInk : Theme.text
    property string tip: ""
    signal clicked()
    signal rightClicked()

    // for screen readers: a button named after what it does
    Accessible.role: Accessible.Button
    Accessible.name: root.tip !== "" ? root.tip : root.icon.replace(/-symbolic$/, "").replace(/-/g, " ")
    Accessible.checkable: root.on
    Accessible.checked: root.on
    Accessible.onPressAction: root.clicked()

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    clip: true

    // ---- base fill ---------------------------------------------------------
    color: {
        if (on) return Theme.accent
        if (area.pressed) return Theme.pressed
        if (area.containsMouse) return Theme.hover
        return "transparent"
    }
    Behavior on color { ColorAnimation { duration: Theme.anim } }

    // ---- ripple on press ---------------------------------------------------
    Rectangle {
        id: ripple
        width: 0; height: 0
        radius: width / 2
        color: Theme.text
        opacity: area.pressed ? 0.20 : 0
        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        anchors.centerIn: area.pressed ? Qt.point(area.mouseX, area.mouseY) : Qt.point(parent.width / 2, parent.height / 2)
    }

    // ---- subtle scale-down on press ---------------------------------------
    transform: Scale {
        origin.x: area.pressed ? area.mouseX : width / 2
        origin.y: area.pressed ? area.mouseY : height / 2
        xScale: area.pressed ? 0.94 : 1
        yScale: area.pressed ? 0.94 : 1
        Behavior on xScale { NumberAnimation { duration: 120 } }
        Behavior on yScale { NumberAnimation { duration: 120 } }
    }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: root.size * 0.55
        color: root.iconColor
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        enabled: root.enabled
        onClicked: e => e.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }
}
