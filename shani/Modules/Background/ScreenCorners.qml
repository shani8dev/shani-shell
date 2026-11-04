// Rounded screen corners (noctalia's): four small black quarter-rounds on the top
// layer of each screen. Four tiny surfaces, not one screen-sized transparent one,
// so nothing is blended over the whole screen each frame; drawn once; no input.
// A fullscreen window sits above the top layer, so video keeps its square corners.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common

Variants {
    model: Settings.loaded && Settings.data.screenCorners ? Quickshell.screens : []
    Scope {
        id: scr
        required property var modelData
        Repeater {
            model: [{ top: true, left: true }, { top: true, right: true }, { bottom: true, left: true }, { bottom: true, right: true }]
            PanelWindow {
                id: corner
                required property var modelData
                readonly property int r: 14
                screen: scr.modelData
                anchors { top: !!modelData.top; bottom: !!modelData.bottom; left: !!modelData.left; right: !!modelData.right }
                implicitWidth: r
                implicitHeight: r
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                mask: Region {}
                WlrLayershell.namespace: "shani-corner"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        const c = getContext("2d"), r = corner.r;
                        const cx = corner.modelData.left ? r : 0, cy = corner.modelData.top ? r : 0;
                        c.reset();
                        c.fillStyle = "black";
                        c.beginPath();
                        c.rect(0, 0, r, r);
                        c.arc(cx, cy, r, 0, Math.PI * 2, true);   // the screen's side cut out
                        c.fill("evenodd");
                    }
                }
            }
        }
    }
}
