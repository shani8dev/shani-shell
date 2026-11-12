// A labelled group box: a titled section that groups related controls.
// A Glass card with a SectionTitle header.
import QtQuick
import QtQuick.Layouts
import qs.Common

Item {
    id: root
    property string title
    default property alias content: col.data

    Glass {
        radius: Theme.radius
        strong: false
        Layout.fillWidth: true
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            SectionTitle {
                text: root.title
                Layout.fillWidth: true
            }

            ColumnLayout {
                id: col
                Layout.fillWidth: true
                spacing: 8
            }
        }
    }
}