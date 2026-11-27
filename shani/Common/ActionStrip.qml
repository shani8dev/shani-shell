// One row of actions or filters, with room to scroll when labels grow.
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Common

Flickable {
    id: strip
    default property alias actions: actionRow.data
    readonly property alias row: actionRow
    property alias spacing: actionRow.spacing
    readonly property bool overflowing: contentWidth > width
    readonly property real inset: Theme.space(1)
    readonly property real scrollbarSize: Theme.space(2)

    implicitWidth: contentWidth
    implicitHeight: actionRow.implicitHeight + 2 * inset + (overflowing ? scrollbarSize : 0)
    Layout.minimumWidth: 0
    contentWidth: actionRow.implicitWidth + 2 * inset
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    interactive: overflowing
    clip: true

    Controls.ScrollBar.horizontal: Controls.ScrollBar {
        policy: strip.overflowing ? Controls.ScrollBar.AlwaysOn : Controls.ScrollBar.AlwaysOff
        height: strip.scrollbarSize
        activeFocusOnTab: false
    }

    data: [
        RowLayout {
            id: actionRow
            x: strip.inset
            y: strip.inset
            spacing: Theme.space(2)
        }
    ]
}
