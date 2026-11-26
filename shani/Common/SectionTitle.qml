import QtQuick
import QtQuick.Layouts
import qs.Common

RowLayout {
    property string text
    default property alias extra: tail.data
    spacing: Theme.px(8)
    Text {
        Layout.fillWidth: true
        text: parent.text
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.type("caption")
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1
    }
    Row { id: tail; spacing: Theme.px(6) }
}
