// Maps: a tile grid centred on the current location (GeoClue) — OpenStreetMap
// tiles over Image elements, attribution shown, zoom in/out, recenter.
// Location is opt-in (privacy): off means a typed city, via Weather's
// geocoder (shani weather set). Needs the network for tiles; when offline
// the tiles are blank and the centre + coordinates are what's left.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.maps
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-maps"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: Ui.maps = false }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.maps = false }

    // ---- slippy-map tile math (OSM tiles, z/x/y) ----
    property int z: 14
    property int tile: 256
    // world pixel at center
    readonly property real px: (Location.lon + 180) / 360 * Math.pow(2, z) * tile
    readonly property real py: (0.5 - Math.log(Math.tan(Math.PI / 4 + Location.lat * Math.PI / 360)) / (2 * Math.PI)) * Math.pow(2, z) * tile

    function tileXY(cxp, cyp) {
        const tx = Math.floor((cxp - (grid.width / 2 - 0)) / tile) + Math.floor(win.px / tile);
        const ty = Math.floor(cyp / tile) + Math.floor(win.py / tile);
        return { x: Math.round(win.px / tile + (cxp - grid.width / 2) / tile), y: Math.round(win.py / tile + (cyp - grid.height / 2) / tile) };
    }

    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Math.min(900, parent.width - 80)
        height: Math.min(620, parent.height - 120)
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            x: 20; y: 20
            width: parent.width - 40
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Icon { name: "mappin"; size: 20; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: Location.available ? "Maps · " + (Weather.zoneCity || "current location") : "Maps"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "location"; size: 28; onClicked: Location.refresh(); }
                IconButton { icon: "view-refresh"; size: 28; onClicked: Location.refresh(); }
                IconButton { icon: "window-close"; size: 28; onClicked: Ui.maps = false }
            }

            Rectangle {
                id: grid
                Layout.fillWidth: true
                Layout.preferredHeight: 380
                radius: Theme.radiusSmall
                color: Theme.hover
                clip: true
                // 4x4 tiles centred on the location
                Grid {
                    anchors.centerIn: parent
                    columns: 4; rows: 4; spacing: 0
                    Repeater {
                        model: 16
                        Rectangle {
                            width: 256; height: 256
                            color: "transparent"
                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                source: {
                                    const dx = (index % 4) - 1.5, dy = Math.floor(index / 4) - 1.5;
                                    const n = Math.pow(2, win.z);
                                    const x = Math.floor(win.px / win.tile + dx);
                                    const y = Math.min(n - 1, Math.max(0, Math.floor(win.py / win.tile + dy)));
                                    return "https://tile.openstreetmap.org/" + win.z + "/" + x + "/" + y + ".png";
                                }
                            }
                        }
                    }
                }
                // centre marker + coordinates
                Rectangle {
                    anchors.centerIn: parent
                    width: 14; height: 14
                    radius: 7
                    color: Theme.accent
                    border.width: 2; border.color: "white"
                }
                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Location.available ? (Location.lat.toFixed(4) + ", " + Location.lon.toFixed(4)) : "location off or unknown — set a city in Weather"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Choice { text: "Zoom in"; onClicked: win.z = Math.min(19, win.z + 1) }
                Choice { text: "Zoom out"; onClicked: win.z = Math.max(3, win.z - 1) }
                Item { Layout.fillWidth: true }
                Text {
                    text: "© OpenStreetMap contributors"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
            }
        }
    }
}
