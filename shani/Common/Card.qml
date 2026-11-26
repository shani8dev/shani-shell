// A card: one group of related things on its own surface (docs/DESIGN.md).
// An optional header - an icon on a tinted badge, a title, a one-line
// subtitle, and actions on the right - then the content. A card inside
// another card draws flat (no second surface), so pages can nest freely.
//
//   Card { icon: "drive-harddisk-symbolic"; title: Tr.t("Daily backup")
//          subtitle: Tr.t("A copy of your home folder each day")
//          actions: [ Button { text: Tr.t("Back up now"); kind: "primary" } ]
//          SwitchRow { ... } }
import QtQuick
import QtQuick.Layouts
import qs.Common

Rectangle {
    id: root
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property color tint: Theme.accent       // the icon badge's colour (a status colour for a status card)
    property bool flat: false               // no surface of its own (set by itself inside another card)
    readonly property bool isCard: true
    // narrow (a phone, a split window): less padding, the same order
    readonly property bool compact: width > 0 && width < Theme.px(420)
    property int padding: flat ? 0 : Theme.space(compact ? 4 : 5)
    property alias spacing: body.spacing
    property alias actions: actionRow.data
    default property alias content: body.data

    implicitWidth: Theme.px(320)
    implicitHeight: col.implicitHeight + padding * 2
    radius: flat ? 0 : Theme.radiusLarge
    color: flat ? "transparent" : Theme.card
    border.width: flat ? 0 : 1
    border.color: Theme.cardBorder

    Component.onCompleted: {
        for (let p = parent; p; p = p.parent)
            if (p.isCard === true) { flat = true; break; }
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: Theme.space(4)

        RowLayout {
            Layout.fillWidth: true
            visible: root.title !== "" || root.icon !== "" || actionRow.children.length > 0
            spacing: Theme.space(3)

            Rectangle {
                visible: root.icon !== ""
                Accessible.ignored: true
                implicitWidth: Theme.px(36)
                implicitHeight: Theme.px(36)
                radius: Theme.radiusSmall + Theme.px(2)
                color: Theme.alpha(root.tint, 0.16)
                Icon { anchors.centerIn: parent; name: root.icon; size: Theme.px(18); color: root.tint }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(2)
                Text {
                    Layout.fillWidth: true
                    visible: root.title !== ""
                    text: root.title
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.type("heading")
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.Heading
                    Accessible.name: root.title
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.subtitle !== ""
                    text: root.subtitle
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                    wrapMode: Text.Wrap
                }
            }
            RowLayout {
                id: actionRow
                Layout.alignment: Qt.AlignVCenter
                spacing: Theme.space(2)
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            visible: children.length > 0
            spacing: Theme.space(3)
        }
    }
}
