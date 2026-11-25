// Two-tap confirmation, extracted from ~28 hand-rolled copies: the first tap
// arms, a 4 s timer disarms, and the second tap emits confirmed(id). Exposes
// armed and disarm() so a caller can cancel on tab/hide/context switch.
import QtQuick
import QtQuick.Controls
import qs.Common

Item {
    id: root
    property string text: ""
    property string armedText: Tr.t("Tap again")
    property string id: ""
    property int interval: 4000
    property string kind: "plain"       // plain | danger | outline
    property bool armed: false
    readonly property bool danger: root.kind === "danger"
    signal confirmed(string id)

    function disarm() { armed = false; timer.stop(); }

    Button {
        anchors.fill: parent
        text: root.armed ? root.armedText : root.text
        kind: root.danger ? "danger" : (root.kind === "outline" ? "outline" : "plain")
        Accessible.name: text
        onClicked: {
            if (root.armed) { root.confirmed(root.id); root.disarm(); }
            else { root.armed = true; timer.restart(); }
        }
    }
    Timer { id: timer; interval: root.interval; onTriggered: root.armed = false }
}
