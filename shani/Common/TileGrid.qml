// Tiles or cards side by side that wrap to the width they are given: four on a
// wide window, two on a tablet, one on a phone (docs/DESIGN.md). The column
// count comes from this grid's own width, never from its children's.
//
//   TileGrid { Layout.fillWidth: true; minTileWidth: Theme.px(200)
//              StatTile { … } StatTile { … } StatTile { … } StatTile { … } }
import QtQuick
import QtQuick.Layouts
import qs.Common

GridLayout {
    id: grid
    property real minTileWidth: Theme.px(200)
    property int maxColumns: 4
    columns: Math.max(1, Math.min(maxColumns, Math.floor((width + columnSpacing) / (minTileWidth + columnSpacing))))
    columnSpacing: Theme.space(4)
    rowSpacing: Theme.space(4)
    // every child takes an equal share of its row
    onChildrenChanged: {
        for (let i = 0; i < children.length; i++) {
            children[i].Layout.fillWidth = true;
            children[i].Layout.preferredWidth = minTileWidth;
        }
    }
}
