// One of a row of mutually exclusive chips.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property string text
    property bool selected: false
    signal clicked()
    // flashed after a search lands here (see Ui.flashSetting)
    readonly property bool highlighted: Ui.settingsFlash.length > 0 && String(root.text).toLowerCase().indexOf(Ui.settingsFlash) >= 0

    Accessible.role: Accessible.RadioButton
    Accessible.name: root.text
    Accessible.checked: root.selected
    Accessible.onPressAction: root.clicked()
    Accessible.onToggleAction: root.clicked()      // a radio button's action is Toggle
    implicitWidth: Math.max(label.implicitWidth + 20, Theme.touchTarget)
    implicitHeight: Math.max(Theme.px(28), Theme.touchTarget)
    radius: Theme.px(9)
    color: selected ? Theme.accent : (area.containsMouse ? Theme.pressed : Theme.hover)
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.selected ? Theme.accentInk : Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    KeyFocus { enabled: root.enabled; onActivated: root.clicked() }

    // a search landed here: a pulsing accent edge until the flash clears
    Rectangle {
        id: flashRing
        anchors.fill: parent
        anchors.margins: -3
        radius: root.radius + 3
        color: Theme.alpha(Theme.accent, 0.16)
        border.width: 1.5
        border.color: Theme.alpha(Theme.accent, 0.8)
        visible: root.highlighted
        z: 10
        SequentialAnimation on opacity {
            running: root.highlighted && !Settings.data.reduceMotion
            loops: Animation.Infinite
            NumberAnimation { from: 0.35; to: 1; duration: Theme.mot(420); easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0.35; duration: Theme.mot(420); easing.type: Easing.InOutSine }
        }
    }
}
