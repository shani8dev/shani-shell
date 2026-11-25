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
    property string icon: ""            // non-empty: round icon button instead of text button
    property string armedIcon: ""       // icon while armed; defaults to icon
    property real size: Theme.px(32)
    property string tip: ""             // icon mode: tooltip (flips to armedText when armed)
    property bool on: false             // icon mode: forward "on" fill to inner IconButton
    readonly property bool danger: root.kind === "danger"
    signal confirmed(string id)

    function disarm() { armed = false; timer.stop(); }
    function trigger() {
        if (root.armed) { root.confirmed(root.value); root.disarm(); }
        else { root.armed = true; timer.restart(); }
    }

    implicitWidth: root.icon !== "" ? iconBtn.implicitWidth : 0
    implicitHeight: root.icon !== "" ? iconBtn.implicitHeight : 0

    Button {
        visible: root.icon === ""
        anchors.fill: parent
        enabled: root.enabled
        text: root.armed ? root.armedText : root.text
        kind: root.danger ? "danger" : (root.kind === "outline" ? "outline" : "plain")
        // a caller's name ("Forget Wi-Fi") must reach AT, not the bare label
        Accessible.name: root.Accessible.name !== "" ? root.Accessible.name : root.text
        onClicked: root.trigger()
    }

    IconButton {
        id: iconBtn
        visible: root.icon !== ""
        anchors.centerIn: parent
        enabled: root.enabled
        icon: root.armed && root.armedIcon !== "" ? root.armedIcon : root.icon
        size: root.size
        on: root.on || root.armed
        tip: root.armed ? root.armedText : (root.tip !== "" ? root.tip : root.text)
        iconColor: root.danger && root.armed ? Theme.danger : Theme.text
        // a caller's name must reach AT, not the bare label/tip
        accessibleName: root.Accessible.name !== "" ? root.Accessible.name : (root.armed ? root.armedText : (root.tip !== "" ? root.tip : root.text))
        onClicked: root.trigger()
    }
    Timer { id: timer; interval: root.interval; onTriggered: root.armed = false }
    onVisibleChanged: if (!visible) root.disarm()
    onEnabledChanged: if (!enabled) root.disarm()
}
