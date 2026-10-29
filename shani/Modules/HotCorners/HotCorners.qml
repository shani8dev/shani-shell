// Hot corners (after GNOME / macOS): push the pointer into a screen corner
// and rest a moment — 2 px surfaces in the corners, one action each, set in
// the settings (overview, launcher, sidebar, Chronoa, lock, or none). The short
// dwell is what keeps a quick pass to a menu or a close button from firing it.
// Over a fullscreen window (a game, a film) they are off unless chosen
// (Pantheon's "hot corners in fullscreen"): a game's own corner is its own.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services

Variants {
    model: Quickshell.screens

    Scope {
        id: screenCorners
        required property var modelData

        // Variants, not a Repeater: a Repeater makes its items only under a
        // visual parent, and a Scope is not one - the corners were never made
        Variants {
            model: [
                { key: "hotCornerTopLeft", top: true, left: true },
                { key: "hotCornerTopRight", top: true, left: false },
                { key: "hotCornerBottomLeft", top: false, left: true },
                { key: "hotCornerBottomRight", top: false, left: false }
            ]
            PanelWindow {
                id: corner
                required property var modelData
                readonly property string action: Settings.data[modelData.key] || "none"
                screen: screenCorners.modelData
                visible: action !== "none" && !Lock.locked && (Settings.data.hotCornersInFullscreen || !(GameMode.top && GameMode.top.fullscreen))
                anchors {
                    top: modelData.top
                    bottom: !modelData.top
                    left: modelData.left
                    right: !modelData.left
                }
                implicitWidth: 2
                implicitHeight: 2
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "shani-hot-corner"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: dwell.restart()
                    onExited: dwell.stop()
                }
                Timer {
                    id: dwell
                    interval: 120
                    onTriggered: HotCornerActions.run(corner.action)
                }
            }
        }
    }
}
