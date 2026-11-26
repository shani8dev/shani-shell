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
    // Same token names as InfoBanner: callers can tune one without breaking
    // the many windows that rely on these defaults.
    property int iconSize: Theme.px(40)
    property int padding: Theme.px(8)
    property int accessibleRole: Accessible.StaticText
    signal action()

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignHCenter
    spacing: root.padding

    Icon {
        Layout.alignment: Qt.AlignHCenter
        name: root.icon
        size: root.iconSize
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
        font.pixelSize: Theme.type("heading")
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
        font.pixelSize: Theme.type("small")
        visible: root.subtitle !== ""
    }
    Button {
        Layout.alignment: Qt.AlignHCenter
        visible: root.actionText !== ""
        text: root.actionText
        kind: "primary"
        onClicked: root.action()
    }

    Accessible.role: root.accessibleRole
    Accessible.name: root.title.length ? root.title + ". " + root.subtitle : (root.title || root.subtitle)
}
