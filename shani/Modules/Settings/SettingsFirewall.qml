// Settings > Firewall: whether firewalld is on, the default zone, and — for the
// zone the person is using — the services and ports let in. firewalld's own
// zones do the talking (public is the safe default, home trusts your own
// devices); this page only reads and changes what is in them.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    property string zone: ""             // the zone being edited (the active one at first)

    onActiveChanged: if (active) { Firewall.refresh(); page.zone = "" }
    Component.onCompleted: if (active) Firewall.refresh()

    // ---- the firewall itself ------------------------------------------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Firewall") }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Turn on the firewall")
        hint: Tr.t("firewalld keeps unsolicited connections out; the rules below say what is let in")
        checked: Firewall.running
        enabled: Firewall.available
        onToggled: on => Firewall.setEnabled(on)
    }
    Text {
        Layout.fillWidth: true
        visible: !Firewall.available
        text: Tr.t("firewalld is not installed on this computer")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    Text {
        Layout.fillWidth: true
        visible: Firewall.note !== ""
        text: Firewall.note
        color: Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }

    // ---- the default zone ---------------------------------------------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Default zone") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("Every connection that has no zone of its own lands in this one. Public lets nothing in; home trusts the devices on your own network.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Repeater {
            model: Firewall.named.filter(z => Firewall.zones.some(x => x.name === z))
            Choice {
                required property string modelData
                text: modelData
                selected: Firewall.defaultZone === modelData
                enabled: Firewall.running
                onClicked: Firewall.setDefaultZone(modelData)
            }
        }
    }

    // ---- the zone being edited ---------------------------------------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Rules") }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Repeater {
            model: Firewall.zones
            Choice {
                required property var modelData
                text: modelData.name
                // "Edit lab", not "lab": the same zone is also a chip in the
                // default-zone row above, and a screen reader must be able to
                // tell the two apart
                Accessible.name: Tr.t("Edit %1", modelData.name)
                selected: (page.zone || Firewall.defaultZone) === modelData.name
                enabled: Firewall.running
                onClicked: page.zone = modelData.name
            }
        }
    }

    readonly property var editing: Firewall.zone(page.zone || Firewall.defaultZone)

    Text { Layout.fillWidth: true; text: Tr.t("Open ports"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.Medium }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.px(2)
        Repeater {
            model: page.editing.ports
            ListRow {
                required property string modelData
                Layout.fillWidth: true
                icon: "network-server"
                title: modelData
                extra: Button { text: Tr.t("Remove"); flat: true; onClicked: Firewall.removePort(page.editing.name, modelData) }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField {
                id: portField
                Layout.fillWidth: true
                placeholder: Tr.t("80/tcp, 443/tcp, 53/udp…")
            }
            Button {
                text: Tr.t("Open")
                kind: "primary"
                enabled: portField.text.trim() !== ""
                onClicked: { Firewall.addPort(page.editing.name, portField.text.trim()); portField.text = "" }
            }
        }
    }

    Text { Layout.fillWidth: true; text: Tr.t("Allowed services"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.Medium }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.px(2)
        Repeater {
            model: page.editing.services
            ListRow {
                required property string modelData
                Layout.fillWidth: true
                icon: "applications-system"
                title: modelData
                extra: Button { text: Tr.t("Remove"); flat: true; onClicked: Firewall.removeService(page.editing.name, modelData) }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField {
                id: serviceField
                Layout.fillWidth: true
                placeholder: Tr.t("ssh, dhcpv6-client, http…")
            }
            Button {
                text: Tr.t("Allow")
                kind: "primary"
                enabled: serviceField.text.trim() !== ""
                onClicked: { Firewall.addService(page.editing.name, serviceField.text.trim()); serviceField.text = "" }
            }
        }
    }

    // ---- rich rules: who, what, and what happens ---------------------------
    Text { Layout.fillWidth: true; text: Tr.t("Rich rules"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.Medium }
    Text {
        Layout.fillWidth: true
        text: Tr.t("A port or a service is open to everyone. A rich rule names who it is open to and what happens — accept, reject or drop — and can limit how often, log it, or forward a port elsewhere.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.px(2)
        Repeater {
            model: page.editing.rich
            ListRow {
                required property string modelData
                Layout.fillWidth: true
                icon: "network-server"
                title: modelData
                subtitle: Tr.t("rule")
                extra: Button { text: Tr.t("Remove"); flat: true; Accessible.name: Tr.t("Remove %1", modelData); onClicked: Firewall.removeRich(page.editing.name, modelData) }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField {
                id: ruleField
                Layout.fillWidth: true
                placeholder: Tr.t('rule service name="ssh" reject')
            }
            Button {
                text: Tr.t("Add")
                kind: "primary"
                enabled: ruleField.text.trim() !== ""
                onClicked: { Firewall.addRich(page.editing.name, ruleField.text.trim()); ruleField.text = "" }
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: Firewall.richPresets
                Choice {
                    required property var modelData
                    text: modelData.label
                    enabled: Firewall.running
                    onClicked: Firewall.addRich(page.editing.name, modelData.rule)
                }
            }
        }
    }

    // ---- zones --------------------------------------------------------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Zones") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("A zone is a set of rules. An interface or a connection joins one; everything else lands in the default. The usual ones are already here — a zone of your own keeps them untouched.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        TextField {
            id: zoneField
            Layout.fillWidth: true
            placeholder: Tr.t("the name of a new zone")
        }
        Button {
            text: Tr.t("New zone")
            kind: "primary"
            enabled: zoneField.text.trim() !== "" && Firewall.running
            onClicked: { Firewall.newZone(zoneField.text.trim()); zoneField.text = "" }
        }
    }
    Button {
        Layout.fillWidth: true
        visible: (page.zone || Firewall.defaultZone) !== "" && (page.zone || Firewall.defaultZone) !== Firewall.defaultZone
        text: Tr.t("Delete the zone “%1”", page.zone || Firewall.defaultZone)
        enabled: Firewall.running
        onClicked: {
            const gone = page.zone || Firewall.defaultZone;
            Firewall.deleteZone(gone);
            page.zone = "";
        }
    }
}
