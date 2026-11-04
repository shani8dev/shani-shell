// An empty state: icon + title + subtitle + optional action button.
// Use where a list or panel has nothing to show, so the screen is never blank.
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: root
    property string icon: "preferences-system"
    property string title: ""
    property string subtitle: ""
    property string actionText: ""
    signal action()

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignHCenter
    spacing: 8

    Icon {
        Layout.alignment: Qt.AlignHCenter
        name: root.icon
        size: 40
        color: Theme.faint
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.title
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 14 * Theme.fontScale
        font.weight: Font.DemiBold
        visible: root.title !== ""
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.subtitle
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
        visible: root.subtitle !== ""
    }
    Button {
        Layout.alignment: Qt.AlignHCenter
        visible: root.actionText !== ""
        text: root.actionText
        kind: "primary"
        onClicked: root.action()
    }
}
