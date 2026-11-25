// A titled block of settings: the uppercase SectionTitle, an optional dim hint
// line under it, then the rows. The repeated "SectionTitle + description + rows"
// scaffolding every Settings page had, so one change here updates them all.
// Children are the rows; each keeps its own Layout.fillWidth.
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: root
    property string title
    property string hint: ""
    property bool hintVisible: true
    spacing: Theme.px(12)
    SectionTitle { Layout.fillWidth: true; text: root.title }
    Text {
        Layout.fillWidth: true
        visible: root.hint !== "" && root.hintVisible
        text: root.hint
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
    }
}
