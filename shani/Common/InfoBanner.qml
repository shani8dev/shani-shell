// Inline status message: info | ok | warn | error | accent, with an optional
// icon and action buttons. Ported from Ananta UI (ananta-os/apps/ui/InfoBanner.qml).
import QtQuick
import QtQuick.Layouts
import qs.Common

Rectangle {
    id: banner
    property string tone: "info"
    property string title: ""
    property string text: ""
    property string iconName: ""
    default property alias actions: actionRow.data
    readonly property color toneColor: tone === "ok" ? Theme.accent
                                      : tone === "warn" ? Theme.amber
                                      : tone === "error" || tone === "danger" ? Theme.danger
                                      : tone === "accent" ? Theme.accent
                                      : Theme.blue

    implicitHeight: row.implicitHeight + Theme.px(20)
    radius: Theme.radius
    color: Theme.alpha(toneColor, 0.12)
    border.width: 1
    border.color: Theme.alpha(toneColor, 0.28)

    RowLayout {
        id: row
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Theme.px(12) }
        spacing: Theme.px(10)

        Icon {
            visible: banner.iconName.length > 0
            name: banner.iconName
            size: Theme.px(18)
            color: banner.toneColor
            Layout.alignment: Qt.AlignTop
        }
        StatusGlyph {
            visible: banner.iconName.length === 0
            tone: banner.tone
            size: Theme.px(18)
            Layout.alignment: Qt.AlignTop
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.px(3)
            Text {
                visible: banner.title.length > 0
                Layout.fillWidth: true
                text: banner.title
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }
            Text {
                visible: banner.text.length > 0
                Layout.fillWidth: true
                text: banner.text
                // An error in a dim label is an error nobody reads.
                color: banner.tone === "error" || banner.tone === "danger" || banner.tone === "warn" ? Theme.text : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                wrapMode: Text.Wrap
            }
            RowLayout {
                id: actionRow
                Layout.fillWidth: true
                spacing: Theme.px(8)
            }
        }
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: banner.title.length ? banner.title + ". " + banner.text : banner.text
}
