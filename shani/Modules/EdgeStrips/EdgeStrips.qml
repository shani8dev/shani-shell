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
        && ["tablet", "phone"].indexOf(FormFactor.of(modelData.name).profile) >= 0
    // four layer-shell surfaces, one per edge: Variants, not a Repeater, so the
    // windows are made the way every other surface is (tests/test_qml_patterns.py)
    Variants {
        model: ["top", "bottom", "left", "right"]
        PanelWindow {
            id: strip
            required property string modelData
            readonly property bool across: modelData === "top" || modelData === "bottom"
            screen: root.modelData
            visible: root.on
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
                    const action = G.finishSwipe(swipe, strip.modelData, to.x, to.y, distance, jitter, Date.now());
                    swipe = null;
                    EdgeSwipe.run(action);
                }
            }
        }
    }
}
