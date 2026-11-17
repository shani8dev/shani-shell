// Edge strips (docs/FORM-FACTORS.md, the tablet): on a screen whose kind is
// tablet or phone, a thin strip along each edge takes a finger coming in from
// it - from the bottom the launcher, from the top Quick Settings, from the
// left back, from the right the overview (Common/Gestures.js decides which).
// The strips are thin and take only what starts on them: a tap at the very
// edge still reaches what is there once it is not a swipe.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services
import "../../Common/Gestures.js" as G

Scope {
    id: root
    required property var modelData
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
            margins.top: across ? 0 : Theme.px(48)
            margins.bottom: across ? 0 : Theme.px(48)
            implicitHeight: across ? Theme.px(8) : 0
            implicitWidth: across ? 0 : Theme.px(8)
            MouseArea {
                anchors.fill: parent
                property point from
                property real down: 0        // when the finger went down: a swipe that
                                             // stops and waits is the overview (Android's, iOS's)
                onPressed: m => { from = mapToGlobal(m.x, m.y); down = Date.now() }
                onReleased: m => {
                    const to = mapToGlobal(m.x, m.y);
                    EdgeSwipe.run(G.classifyHold(strip.modelData, to.x - from.x, to.y - from.y, Theme.px(60), Date.now() - down));
                }
            }
        }
    }
}
