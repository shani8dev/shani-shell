// One page of an app (docs/DESIGN.md): a title, a one-line subtitle, the
// page's actions on the right, then the content in a centred column that
// scrolls. Narrow (a phone, a split), the title steps down and the actions
// go under it; wide (a TV, a big screen), the column stops at a readable width.
//
//   AppWindow { appName: "Backup"; sidePane: nav
//       AppPage { title: Tr.t("Backup"); subtitle: Tr.t("Your files, kept safe")
//                 actions: [ Button { text: Tr.t("Back up now"); kind: "primary" } ]
//                 StatusHero { … }  Card { … } } }
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common

Item {
    id: page
    property string title: ""
    property string subtitle: ""
    property int maxContentWidth: Theme.px(1100)
    property alias actions: actionRow.data
    default property alias content: contentColumn.data
    property alias spacing: contentColumn.spacing
    readonly property bool compact: width > 0 && width < Theme.px(600)
    readonly property alias flickable: flick
    readonly property real contentWidth: column.width

    implicitWidth: Theme.px(720)
    implicitHeight: Theme.px(560)

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + Theme.space(page.compact ? 8 : 14)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        ColumnLayout {
            id: column
            width: Math.min(page.maxContentWidth, flick.width - Theme.space(page.compact ? 8 : 14))
            x: (flick.width - width) / 2
            y: Theme.space(page.compact ? 4 : 7)
            spacing: Theme.space(page.compact ? 4 : 6)

            GridLayout {
                Layout.fillWidth: true
                visible: page.title !== "" || page.subtitle !== "" || actionRow.children.length > 0
                columns: page.compact ? 1 : 2
                columnSpacing: Theme.space(4)
                rowSpacing: Theme.space(3)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space(1)
                    Text {
                        Layout.fillWidth: true
                        visible: page.title !== ""
                        text: page.title
                        color: Theme.text
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: Theme.type(page.compact ? "subtitle" : "title")
                        font.weight: Font.DemiBold
                        Accessible.role: Accessible.Heading
                        Accessible.name: page.title
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: page.subtitle !== ""
                        text: page.subtitle
                        color: Theme.dim
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: Theme.type("body")
                    }
                }
                RowLayout {
                    id: actionRow
                    Layout.alignment: page.compact ? Qt.AlignLeft : (Qt.AlignRight | Qt.AlignBottom)
                    spacing: Theme.space(2)
                }
            }

            ColumnLayout {
                id: contentColumn
                Layout.fillWidth: true
                spacing: Theme.space(page.compact ? 4 : 5)
            }
        }
    }
}
