// "Advanced": the expert controls of a Settings page, folded away until asked
// for - proxies, DNS servers, headphone correction curves - so a page shows a
// person what they came for first. One click opens it.
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: root
    property bool open: false
    property string hint: ""                 // what is inside, e.g. "Proxy, DNS servers"
    default property alias content: inner.data
    spacing: 12

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 44
        radius: Theme.radiusSmall
        color: head.containsMouse ? Theme.surface2 : Theme.surface1
        Behavior on color { ColorAnimation { duration: Theme.anim } }
        Accessible.role: Accessible.Button
        Accessible.name: Tr.t("Advanced") + (root.hint ? ": " + root.hint : "")
        Accessible.onPressAction: root.open = !root.open
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10
            Icon { name: "go-next"; size: 14; color: Theme.dim; rotation: root.open ? 90 : 0; Behavior on rotation { NumberAnimation { duration: Theme.anim } } }
            Text { text: Tr.t("Advanced"); color: Theme.text; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale; font.weight: Font.DemiBold }
            Text { Layout.fillWidth: true; text: root.hint; elide: Text.ElideRight; color: Theme.faint; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
        }
        MouseArea { id: head; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.open = !root.open }
    }
    ColumnLayout {
        id: inner
        visible: root.open
        Layout.fillWidth: true
        spacing: 12
    }
}
