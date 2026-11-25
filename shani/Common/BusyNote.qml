// One reusable busy row: a spinner and a dim note. Ten windows hand-rolled
// `Row { visible: busy; Spinner {}; Text { ... } }`; this is the shared shape.
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    property string note: ""
    property real iconSize: Theme.px(16)
    property alias align: text.horizontalAlignment
    spacing: Theme.px(8)
    Accessible.role: Accessible.StatusBar
    Accessible.name: root.note
    Spinner { size: root.iconSize }
    Text {
        id: text
        Layout.fillWidth: true
        text: root.note
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
        wrapMode: Text.Wrap
    }
}
