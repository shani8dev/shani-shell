// Edge strips (docs/FORM-FACTORS.md, the tablet): on a screen whose kind is
// tablet or phone, a thin strip along each edge takes a finger coming in from
// it - from the bottom the launcher, from the top Quick Settings, from the
// left back, from the right the overview (Common/Gestures.js decides which).
// The strips reserve a thin edge for navigation; a tap there does nothing.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services
import "../../Common/Gestures.js" as G

Scope {
    id: root
    required property var modelData
    readonly property real uiScale: FormFactor.of(modelData.name).scale
    readonly property bool on: Settings.data.edgeSwipes && !Lock.locked
        && !(GameMode.top && GameMode.top.fullscreen)   // a game's own edges are its own
        && ["tablet", "phone", "board"].indexOf(FormFactor.of(modelData.name).profile) >= 0
    readonly property bool board: FormFactor.of(modelData.name).profile === "board"
    // where the left rail is, a swipe there must reach the rail, not the
    // shell's Back (Alt+Left)
    readonly property bool railHere: Settings.data.leftRail && FormFactor.hasRail(modelData.name)
    // four layer-shell surfaces, one per edge: Variants, not a Repeater, so the
    // windows are made the way every other surface is (tests/test_qml_patterns.py)
    Variants {
        model: ["top", "bottom", "left", "right"]
        PanelWindow {
            id: strip
            required property string modelData
            readonly property bool across: modelData === "top" || modelData === "bottom"
            screen: root.modelData
            visible: root.on && !(modelData === "left" && root.railHere) && !(root.board && modelData === "top")
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "shani-edge-" + modelData
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors {
                top: modelData !== "bottom"
                bottom: modelData !== "top"
                left: modelData !== "right"
                right: modelData !== "left"
            }
            // the corners belong to the strips across (the bar's, the dock's ends)
            margins.top: across ? 0 : Math.round(48 * root.uiScale)
            margins.bottom: across ? 0 : Math.round(48 * root.uiScale)
            implicitHeight: across ? Math.round(8 * root.uiScale) : 0
            implicitWidth: across ? 0 : Math.round(8 * root.uiScale)
            MouseArea {
                anchors.fill: parent
                property var swipe: null
                readonly property real distance: 60 * root.uiScale
                readonly property real jitter: 8 * root.uiScale
                onPressed: m => {
                    const p = mapToGlobal(m.x, m.y);
                    swipe = G.startSwipe(p.x, p.y);
                }
                onPositionChanged: m => {
                    if (!pressed || !swipe) return;
                    const p = mapToGlobal(m.x, m.y);
                    G.moveSwipe(swipe, strip.modelData, p.x, p.y, distance, jitter, Date.now());
                }
                onCanceled: swipe = null
                onReleased: m => {
                    const to = mapToGlobal(m.x, m.y);
                    let action = G.finishSwipe(swipe, strip.modelData, to.x, to.y, distance, jitter, Date.now());
                    swipe = null;
                    if (root.board) action = G.boardAction(strip.modelData, action);
                    // the Ring opens at the side the finger came from, at its height
                    if (action === "ring-left" || action === "ring-right") {
                        const w = root.modelData.width;
                        EdgeSwipe.last = action;
                        Ui.openRingAt(action === "ring-left" ? 180 * root.uiScale : w - 180 * root.uiScale, to.y - root.modelData.y);
                        return;
                    }
                    EdgeSwipe.run(action);
                }
            }
        }
    }
}
