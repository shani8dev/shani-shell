// One of a row of mutually exclusive chips.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property string text
    property bool selected: false
    property alias checked: root.selected   // the toggle name Button, IconButton and SwitchRow use
    property bool danger: false      // destructive one-shot action, not a choice
    property string accessibleName: ""   // overrides text as the AT name when text is only a hint
    property int columns: 0              // grid width: Up/Down jump a row in the KeyFocus chain
    signal clicked()
    // flashed after a search lands here (see Ui.flashSetting)
    readonly property bool highlighted: Ui.settingsFlash.length > 0 && String(root.text).toLowerCase().indexOf(Ui.settingsFlash) >= 0

    Accessible.role: Accessible.RadioButton
    Accessible.name: root.accessibleName !== "" ? root.accessibleName : root.text
    Accessible.checked: root.selected
    Accessible.onPressAction: root.clicked()
    Accessible.onToggleAction: root.clicked()      // a radio button's action is Toggle
    implicitWidth: Math.max(label.implicitWidth + 20, Theme.touchTarget)
    implicitHeight: Math.max(Theme.px(28), Theme.touchTarget)
    // a disabled chip must not look enabled (WCAG: state is not colour-only)
    opacity: root.enabled ? 1 : 0.45
    radius: Theme.px(9)
    color: root.danger ? Theme.alpha(Theme.danger, 0.18) : (selected ? Theme.accent : (area.containsMouse ? Theme.pressed : Theme.hover))
    border.width: root.danger ? 1 : 0
    border.color: Theme.danger
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.danger ? Theme.danger : (root.selected ? Theme.accentInk : Theme.text)
        // weight is a second cue: selection must not be colour-only (WCAG 1.4.1)
        font.weight: root.selected ? Font.DemiBold : Font.Normal
        font.family: Theme.font
        font.pixelSize: Theme.type("small")
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    KeyFocus { enabled: root.enabled === true && root.visible === true; columns: root.columns; onActivated: root.clicked() }

    // a search landed here: a pulsing accent edge until the flash clears
    Fade {
        id: flashRing
        anchors.fill: parent
        anchors.margins: -3
        radius: root.radius + 3
        color: Theme.alpha(Theme.accent, 0.16)
        border.width: 1.5
        border.color: Theme.alpha(Theme.accent, 0.8)
        visible: root.highlighted
        z: 10
        active: root.highlighted
        duration: Theme.mot(420)
    }
}
