// Dashed drop target with a centred message and optional action buttons.
// Ported from Ananta UI (ananta-os/apps/ui/DropZone.qml) onto the shell palette.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.Common

Item {
    id: zone
    property string iconName: "document-import"
    property string title: ""
    property string text: ""
    default property alias actions: actionRow.data
    signal fileDropped(url file)

    implicitWidth: Theme.px(400)
    implicitHeight: column.implicitHeight + Theme.px(48)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: drop.containsDrag ? Theme.alpha(Theme.accent, 0.14) : Theme.surface2
        Behavior on color { ColorAnimation { duration: Theme.anim } }
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: drop.containsDrag ? Theme.accent : Theme.stroke
            strokeWidth: 1.5
            strokeStyle: ShapePath.DashLine
            dashPattern: [5, 4]
            fillColor: "transparent"
            startX: 1; startY: 1
            PathLine { x: zone.width - 1; y: 1 }
            PathLine { x: zone.width - 1; y: zone.height - 1 }
            PathLine { x: 1; y: zone.height - 1 }
            PathLine { x: 1; y: 1 }
        }
    }

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        width: Math.min(zone.width - Theme.px(40), Theme.px(380))
        spacing: Theme.px(8)

        Icon {
            Layout.alignment: Qt.AlignHCenter
            name: zone.iconName
            size: Theme.px(40)
            color: Theme.accent
        }
        Text {
            Layout.fillWidth: true
            visible: zone.title.length > 0
            text: zone.title
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            visible: zone.text.length > 0
            text: zone.text
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.type("small")
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
        RowLayout {
            id: actionRow
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.px(4)
            spacing: Theme.px(8)
        }
    }

    DropArea {
        id: drop
        anchors.fill: parent
        onDropped: event => {
            if (event.hasUrls && event.urls.length > 0)
                zone.fileDropped(event.urls[0])
        }
    }
}
