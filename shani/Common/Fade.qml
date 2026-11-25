// One accent pulse, shared by every module that flashed a ring or a glow by
// hand: a Rectangle that breathes its opacity while `active` (a search landed
// on a row, Chronoa is working), or one shot through flash(). Reduce motion is
// honoured in one place — Theme.mot makes `duration` 0 ms and the loop never
// runs, so a person who asked for no movement gets a still accent, not a pulse.
import QtQuick
import qs.Common

Rectangle {
    id: root
    // per phase; 0 under reduce motion (Theme.anim is 0 there, and call sites
    // pass Theme.mot(ms) which is 0 too)
    property int duration: Theme.anim * 4
    property var easing: Easing.InOutSine
    property real pulseFrom: 0.35
    property real pulseTo: 1.0
    // continuous: breathe while true (loops until it clears)
    property bool active: false

    // one-shot: pulse once, then settle back to pulseFrom (no-op under reduce motion)
    function flash() { if (!Settings.data.reduceMotion) once.restart(); }

    SequentialAnimation {
        id: loop
        running: root.active && !Settings.data.reduceMotion
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "opacity"; from: root.pulseFrom; to: root.pulseTo; duration: root.duration; easing.type: root.easing }
        NumberAnimation { target: root; property: "opacity"; from: root.pulseTo; to: root.pulseFrom; duration: root.duration; easing.type: root.easing }
    }
    SequentialAnimation {
        id: once
        NumberAnimation { target: root; property: "opacity"; from: root.pulseFrom; to: root.pulseTo; duration: root.duration; easing.type: root.easing }
        NumberAnimation { target: root; property: "opacity"; from: root.pulseTo; to: root.pulseFrom; duration: root.duration; easing.type: root.easing }
    }
}
