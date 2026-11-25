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
    property string value: ""        // `id` is a reserved QML attribute, not a property
    property int interval: 4000
    property string kind: "plain"       // plain | danger | outline
    property bool armed: false
    readonly property bool danger: root.kind === "danger"
    signal confirmed(string id)

    function disarm() { armed = false; timer.stop(); }

    Button {
        anchors.fill: parent
        enabled: root.enabled
        text: root.armed ? root.armedText : root.text
        kind: root.danger ? "danger" : (root.kind === "outline" ? "outline" : "plain")
        // a caller's name ("Forget Wi-Fi") must reach AT, not the bare label
        Accessible.name: root.Accessible.name !== "" ? root.Accessible.name : root.text
        onClicked: {
            if (root.armed) { root.confirmed(root.value); root.disarm(); }
            else { root.armed = true; timer.restart(); }
        }
    }
    Timer { id: timer; interval: root.interval; onTriggered: root.armed = false }
}
