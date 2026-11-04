// A labelled on/off switch.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common

// an Item holding the row, so the search flash can lie over it (a layout
// would place the ring as one more column)
Item {
    id: root
    property string text
    property string hint: ""
    property string info: ""     // hover tooltip for the “why”
    property bool checked: false
    property var defaultValue: undefined   // when set, a reset icon appears when changed
    signal toggled(bool on)
    signal reset()
    // flashed after a search lands here (see Ui.flashSetting)
    readonly property bool highlighted: Ui.settingsFlash.length > 0 && String(root.text).toLowerCase().indexOf(Ui.settingsFlash) >= 0

    Accessible.role: Accessible.CheckBox
    Accessible.name: root.text
    Accessible.description: root.hint
    Accessible.checkable: true
    Accessible.checked: root.checked
    Accessible.onToggleAction: root.toggled(!root.checked)
    Accessible.onPressAction: root.toggled(!root.checked)
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 10

        Column {
            Layout.fillWidth: true
            Text { text: root.text; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
            Text { visible: root.hint !== ""; text: root.hint; color: Theme.faint; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
        }
        Icon {
            visible: root.info !== ""
            name: "help-about-symbolic"
            size: 14
            color: Theme.faint
            ToolTip.visible: infoArea.containsMouse
            ToolTip.text: root.info
            ToolTip.delay: 300
            MouseArea {
                id: infoArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.WhatsThisCursor
            }
        }
        Rectangle {
            implicitWidth: 40
            implicitHeight: 22
            radius: 11
            color: root.checked ? Theme.accent : Theme.pressed
            Behavior on color { ColorAnimation { duration: Theme.anim } }
            Rectangle {
                width: 16
                height: 16
                radius: 8
                y: 3
                x: root.checked ? parent.width - width - 3 : 3
                color: root.checked ? Theme.accentInk : Theme.text
                Behavior on x { NumberAnimation { duration: Theme.anim } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggled(!root.checked)
            }
        }

        IconButton {
            visible: root.defaultValue !== undefined && root.checked !== root.defaultValue
            icon: "view-refresh"
            size: 18
            Accessible.name: Tr.t("Reset this setting")
            onClicked: root.reset()
        }
    }

    // a search landed here: a pulsing accent ring until the flash clears
    Rectangle {
        id: flashRing
        anchors.fill: parent
        anchors.margins: -4
        radius: 10
        color: Theme.alpha(Theme.accent, 0.18)
        border.width: 1.5
        border.color: Theme.alpha(Theme.accent, 0.8)
        visible: root.highlighted
        z: 10
        SequentialAnimation on opacity {
            running: root.highlighted
            loops: Animation.Infinite
            NumberAnimation { from: 0.35; to: 1; duration: 420; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0.35; duration: 420; easing.type: Easing.InOutSine }
        }
    }
}
