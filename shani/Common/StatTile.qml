// One fact at a glance (docs/DESIGN.md): a small label with its icon, the
// value large, a line of detail, and an optional bar. Put a few side by
// side in a Common/TileGrid-like GridLayout; they wrap on a narrow window.
//
//   StatTile { icon: "drive-harddisk-symbolic"; label: Tr.t("Storage")
//              value: Tr.t("%1 free", Theme.bytes(free)); detail: ...; progress: used / total }
import QtQuick
import QtQuick.Layouts
import qs.Common

Rectangle {
    id: root
    property string icon: ""
    property string label: ""
    property string value: ""
    property string detail: ""
    property real progress: -1               // 0..1 shows a bar; below 0 none
    property color tint: Theme.accent
    signal clicked()
    property bool interactive: false

    Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: [label, value, detail].filter(s => s !== "").join(", ")
    Accessible.onPressAction: if (interactive) root.clicked()

    implicitWidth: Theme.px(220)
    implicitHeight: col.implicitHeight + Theme.space(8)
    radius: Theme.radiusLarge
    color: interactive && area.containsMouse ? Theme.surface2 : Theme.card
    border.width: 1
    border.color: Theme.cardBorder

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.space(4)
        spacing: Theme.space(2)

        RowLayout {
            spacing: Theme.space(2)
            Rectangle {
                visible: root.icon !== ""
                Accessible.ignored: true
                implicitWidth: Theme.px(28)
                implicitHeight: Theme.px(28)
                radius: Theme.radiusSmall
                color: Theme.alpha(root.tint, 0.16)
                Icon { anchors.centerIn: parent; name: root.icon; size: Theme.px(15); color: root.tint }
            }
            Text {
                Layout.fillWidth: true
                text: root.label
                color: Theme.dim
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.type("small")
            }
        }
        Text {
            Layout.fillWidth: true
            text: root.value
            color: Theme.text
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.type("subtitle")
            font.weight: Font.DemiBold
        }
        Rectangle {
            Layout.fillWidth: true
            visible: root.progress >= 0
            implicitHeight: Theme.px(6)
            radius: height / 2
            color: Theme.pressed
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, root.progress))
                height: parent.height
                radius: parent.radius
                color: root.tint
            }
        }
        Text {
            Layout.fillWidth: true
            visible: root.detail !== ""
            text: root.detail
            color: Theme.dim
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.type("small")
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
    KeyFocus { enabled: root.interactive && root.visible; name: root.label; onActivated: root.clicked() }
}
