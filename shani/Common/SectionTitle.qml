import QtQuick
import QtQuick.Layouts
import qs.Common

RowLayout {
    property string text
    default property alias extra: tail.data
    spacing: 8
    Text {
        Layout.fillWidth: true
        text: parent.text
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1
    }
    Row { id: tail; spacing: 6 }
}
