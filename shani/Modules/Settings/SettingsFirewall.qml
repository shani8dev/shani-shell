// Settings > Firewall: whether firewalld is on, the default zone, and — for the
// zone the person is using — the services and ports let in. firewalld's own
// zones do the talking (public is the safe default, home trusts your own
// devices); this page only reads and changes what is in them.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/ToolPath.js" as ToolPath

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    property string zone: ""             // the zone being edited (the active one at first)
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_NET_TOOL"), "system_net.py")

    property var fail2banInfo: ({})
    property bool fail2banBusy: false
    readonly property var jailRows: Array.isArray(page.fail2banInfo.per_jail) ? page.fail2banInfo.per_jail : []

    onActiveChanged: if (active) { Firewall.refresh(); page.zone = ""; page.reloadFail2ban() }
    Component.onCompleted: if (active) { Firewall.refresh(); page.reloadFail2ban(); page.publishFail2ban() }

    function publishFail2ban() {
        const r = page.fail2banInfo;
        const o = Object.assign({}, Ui.systemState || {});
        o.fail2ban = {
            jails: Array.isArray(r.jails) ? r.jails : [],
            banned: Array.isArray(r.banned) ? r.banned : [],
            per_jail: Array.isArray(r.per_jail) ? r.per_jail : [],
            available: !!r.available,
            error: r.error || ""
        };
        Ui.systemState = o;
    }
    function countText(v) {
        return (v === null || v === undefined) ? Tr.t("not reported") : String(v);
    }
    function bannedText(counts) {
        const c = counts || {};
        return Tr.t("Banned now %1, ever %2", page.countText(c.currently_banned), page.countText(c.total_banned));
    }
    // A JSON array becomes an array-like QVariantList once a delegate holds it;
    // Array.isArray alone would hide the addresses we actually read.
    function bannedList(value) {
        if (!value) return [];
        if (Array.isArray(value)) return value;
        return typeof value.length === "number" ? Array.from(value) : [];
    }
    function reloadFail2ban() {
        page.fail2banBusy = true;
        fail2banProc.running = false;
        fail2banProc.running = true;
    }

    Process {
        id: fail2banProc
        command: ["python3", page.tool, "fail2ban"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text) || {}; }
                catch (e) { r = { available: false, error: Tr.t("Could not read the list") }; }
                page.fail2banInfo = r;
                page.fail2banBusy = false;
                page.publishFail2ban();
            }
        }
        onExited: page.fail2banBusy = false
    }

    // ---- the firewall itself ------------------------------------------------
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Firewall")
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
            font.pixelSize: Theme.type("small")
        }
        Text {
            Layout.fillWidth: true
            visible: Firewall.note !== ""
            text: Firewall.note
            color: Theme.danger
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.type("small")
        }
    }

    // ---- repeated sign-in attempts (read-only) ------------------------------
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Repeated sign-in attempts")
        hint: Tr.t("Jails hold back addresses that keep failing to sign in. This page only reads the list.")

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            Button {
                Layout.alignment: Qt.AlignRight
                text: Tr.t("Refresh the list")
                Accessible.name: Tr.t("Refresh the list of jails and banned addresses")
                enabled: !page.fail2banBusy
                busy: page.fail2banBusy
                onClicked: page.reloadFail2ban()
            }
        }
        BusyNote { Layout.fillWidth: true; visible: page.fail2banBusy; note: Tr.t("Loading…"); iconSize: Theme.px(16) }
        InfoBanner {
            Layout.fillWidth: true
            visible: !page.fail2banBusy && page.fail2banInfo.available === false
            tone: "error"
            title: Tr.t("No list to show")
            text: Tr.t("The check did not answer, so no jail or banned address is shown.") +
                  (page.fail2banInfo.error ? " " + page.fail2banInfo.error : "")
            accessibleRole: Accessible.AlertMessage
        }
        EmptyState {
            visible: !page.fail2banBusy && page.fail2banInfo.available === true &&
                     Array.isArray(page.fail2banInfo.jails) && page.fail2banInfo.jails.length === 0
            icon: "system-lock-screen"
            title: Tr.t("No jails are set up")
            subtitle: Tr.t("No jail is holding back an address right now.")
        }
        ListRow {
            Layout.fillWidth: true
            visible: !page.fail2banBusy && page.fail2banInfo.available === true &&
                     Array.isArray(page.fail2banInfo.jails) && page.fail2banInfo.jails.length > 0
            interactive: false
            icon: "system-lock-screen"
            title: Tr.t("Jails and bans")
            subtitle: Tr.t("Jails set up: %1", (page.fail2banInfo.jails || []).length)
            trailing: page.bannedText(page.fail2banInfo.counts)
        }
        Repeater {
            model: page.jailRows
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.px(2)
                ListRow {
                    Layout.fillWidth: true
                    interactive: false
                    icon: "system-lock-screen"
                    title: modelData.name
                    subtitle: page.bannedList(modelData.banned).join(", ") ||
                              Tr.t("No address is banned right now")
                    extra: Text {
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.type("caption")
                        text: page.bannedText(modelData.counts)
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(36)
                    visible: modelData.error !== ""
                    text: modelData.error
                    color: Theme.danger
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: Tr.t("An address is banned after repeated failed sign-ins. This page only reads the list; it does not change it.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.type("small")
        }
    }

    // ---- the default zone ---------------------------------------------------
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Default zone")
        hint: Tr.t("Every connection that has no zone of its own lands in this one. Public lets nothing in; home trusts the devices on your own network.")
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
    }

    readonly property var editing: Firewall.zone(page.zone || Firewall.defaultZone)

    // ---- the zone being edited ---------------------------------------------
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Rules")
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

    Text { Layout.fillWidth: true; text: Tr.t("Open ports"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small"); font.weight: Font.Medium }
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

    Text { Layout.fillWidth: true; text: Tr.t("Allowed services"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small"); font.weight: Font.Medium }
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
    Text { Layout.fillWidth: true; text: Tr.t("Rich rules"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small"); font.weight: Font.Medium }
    Text {
        Layout.fillWidth: true
        text: Tr.t("A port or a service is open to everyone. A rich rule names who it is open to and what happens — accept, reject or drop — and can limit how often, log it, or forward a port elsewhere.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.type("small")
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
    }

    // ---- zones --------------------------------------------------------------
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Zones")
        hint: Tr.t("A zone is a set of rules. An interface or a connection joins one; everything else lands in the default. The usual ones are already here — a zone of your own keeps them untouched.")
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
}
