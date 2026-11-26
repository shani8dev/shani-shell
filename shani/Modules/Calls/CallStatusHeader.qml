// One quiet line above the pad: is a phone ready, how it is connected, and a
// way to look again. A green dot means ready; a dim one means nothing yet.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

Glass {
    id: root
    property bool ready: Link.state === "ready" || Link.lines.length > 0
        || Modem.canCall || Link.phone !== null

    readonly property string kind: {
        const chosen = Lines.lines.find(l => l.ready) || Lines.lines[0];
        const id = String((chosen && (chosen.id || chosen.name)) || Link.lines[0] || "");
        const found = Lines.lines.find(l => String(l.id) === id || String(l.name) === id);
        const k = String((found && found.kind) || id).toLowerCase();
        if (k.indexOf("sip") >= 0) return Tr.t("SIP");
        if (k.indexOf("desk") >= 0 || k.indexOf("landline") >= 0) return Tr.t("Landline");
        if (k.indexOf("modem") >= 0 || k.indexOf("mobile") >= 0 || k.indexOf("sim") >= 0) return Tr.t("Mobile");
        if (Link.phone) return Tr.t("Bluetooth");
        return Tr.t("Phone");
    }
    readonly property string summary: {
        if (!root.ready) return Tr.t("No phone connected yet");
        if (Link.phone) {
            let s = Link.phoneName !== ""
                ? Tr.t("%1 over Bluetooth", Link.phoneName) : Tr.t("Bluetooth");
            if (typeof Link.phone.battery === "number" && Link.phone.battery >= 0)
                s += " · " + Link.phone.battery + "% " + Tr.t("battery");
            return Tr.t("Ready") + " · " + s;
        }
        return Tr.t("Ready") + " · " + root.kind;
    }

    implicitHeight: Math.max(Theme.px(48), Theme.touchTarget + Theme.px(6))
    Accessible.role: Accessible.StatusBar
    Accessible.name: root.summary

    RowLayout {
        anchors { fill: parent; leftMargin: Theme.px(12); rightMargin: Theme.px(8) }
        spacing: Theme.px(10)
        Rectangle {
            Layout.preferredWidth: Theme.px(12)
            Layout.preferredHeight: Theme.px(12)
            radius: width / 2
            color: root.ready ? Theme.success : Theme.dim
        }
        Text {
            Layout.fillWidth: true
            text: root.summary
            Accessible.name: root.summary
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
            elide: Text.ElideRight
        }
        IconButton {
            icon: "view-refresh"
            size: Theme.px(20)
            tip: Tr.t("Look again")
            onClicked: { Link.refresh(); Lines.refresh(); PhoneTools.refresh(); }
        }
    }
}
