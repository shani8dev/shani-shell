// Settings > Phone: internet calling accounts, the landline box, and every line
// this computer currently has. Changes go through Services/Lines as plain
// objects, never a command line. The line list is read-only; it shows what the
// service actually has, so an empty list is an empty state, not a blank page.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    property string editId: ""           // "" = adding a new account
    property string transport: "udp"
    property string port: "5060"
    property bool accountEnabled: true

    onActiveChanged: if (active) Lines.refresh()
    Component.onCompleted: if (active) Lines.refresh()

    function clearForm() {
        editId = "";
        nameField.text = "";
        userField.text = "";
        passField.text = "";
        serverField.text = "";
        port = "5060";
        portField.text = "";
        transport = "udp";
        accountEnabled = true;
    }
    function editAccount(a) {
        editId = a.id || "";
        nameField.text = a.name || "";
        userField.text = a.username || "";
        passField.text = "";             // a saved password is never shown again
        serverField.text = a.domain || a.server || "";
        port = String(a.port || "5060");
        portField.text = (port === "5060" || port === "5061") ? "" : port;
        transport = String(a.transport || "udp").toLowerCase();
        accountEnabled = a.enabled !== false;
    }
    function saveAccount() {
        const fields = {
            name: nameField.text.trim(),
            username: userField.text.trim(),
            domain: serverField.text.trim(),
            port: page.port !== "" ? parseInt(page.port, 10) : 0,
            transport: page.transport,
            enabled: page.accountEnabled
        };
        if (passField.text !== "") fields.password = passField.text;
        if (editId !== "") Lines.updateAccount(editId, fields);
        else Lines.addAccount(fields);
        clearForm();
    }
    function accountSubtitle(a) {
        const host = a.domain || a.server || a.address || "";
        const where = host ? host + (a.port ? ":" + a.port : "") : "";
        return [a.username || "", where, a.enabled === false ? Tr.t("Off") : Tr.t("On")].filter(x => x).join(" · ");
    }
    function lineSubtitle(l) {
        return (l.ready ? Tr.t("Ready") : Tr.t("Not ready")) + (l.kind ? " · " + l.kind : "");
    }
    function landlineDetail() {
        const s = Lines.landline || {};
        return (s.state && typeof s.state === "object") ? s.state : {};
    }
    function landlineReady() {
        const st = page.landlineDetail();
        return !!(st.set_up || st.ready);
    }
    function landlineWaiting() {
        const st = page.landlineDetail();
        return !!(st.sent_to && !st.set_up);
    }
    function landlineState() {
        const s = Lines.landline || {};
        if (s.error) return String(s.error);
        const st = page.landlineDetail();
        if (st.set_up) return st.ready ? Tr.t("Ready — the landline can make calls")
                                       : Tr.t("Connected, but not ready yet");
        if (st.sent_to) return Tr.t("Waiting for the code sent to %1", st.sent_to);
        return Tr.t("Not set up");
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Phone lines")
        hint: Tr.t("Every line this computer can use, shown as it is. Lines are set up below and cannot be changed here.")
        EmptyState {
            visible: Lines.lines.length === 0
            icon: "phone"
            title: Tr.t("No phone lines yet")
            subtitle: Tr.t("A line appears here once an account is added or a landline is set up.")
        }
        Repeater {
            model: Lines.lines
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: "phone"
                title: modelData.name || modelData.id || Tr.t("Unnamed line")
                subtitle: page.lineSubtitle(modelData)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Internet calling accounts")
        hint: Tr.t("Add an account from your calling provider to make and take calls over the internet.")
        EmptyState {
            visible: Lines.accounts.length === 0
            icon: "phone"
            title: Tr.t("No calling accounts yet")
            subtitle: Tr.t("Fill in the form below and choose Add account. You can edit or remove it later.")
        }
        Repeater {
            model: Lines.accounts
            ColumnLayout {
                id: accRow
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.px(4)
                ListRow {
                    Layout.fillWidth: true
                    interactive: false
                    icon: "phone"
                    title: accRow.modelData.name || accRow.modelData.username || Tr.t("Unnamed account")
                    subtitle: page.accountSubtitle(accRow.modelData)
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.px(10)
                    spacing: Theme.px(6)
                    Button {
                        text: Tr.t("Edit")
                        onClicked: page.editAccount(accRow.modelData)
                    }
                    ConfirmButton {
                        id: removeAccount
                        implicitWidth: Math.max(Theme.touchTarget, removeAccount.armedText.length * 8 + 28)
                        implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                        text: Tr.t("Remove")
                        armedText: Tr.t("Tap again to remove")
                        kind: removeAccount.armed ? "danger" : "plain"
                        interval: 4000
                        Accessible.name: Tr.t("Remove %1", accRow.modelData.name || accRow.modelData.username || "")
                        onConfirmed: Lines.removeAccount(accRow.modelData.id)
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            SectionTitle {
                Layout.fillWidth: true
                text: page.editId !== "" ? Tr.t("Edit this account") : Tr.t("Add an account")
            }
            TextField {
                id: nameField
                Layout.fillWidth: true
                label: Tr.t("Name")
                placeholder: Tr.t("A name you will recognise")
            }
            TextField {
                id: userField
                Layout.fillWidth: true
                label: Tr.t("Username")
                placeholder: Tr.t("The name your provider gave you")
            }
            TextField {
                id: passField
                Layout.fillWidth: true
                secret: true
                label: Tr.t("Password")
                placeholder: Tr.t("Your account password")
            }
            TextField {
                id: serverField
                Layout.fillWidth: true
                label: Tr.t("Server")
                placeholder: Tr.t("The address of your provider's server")
            }
            Picks {
                label: Tr.t("Connection type")
                options: [
                    { label: "UDP", value: "udp" },
                    { label: "TCP", value: "tcp" },
                    { label: "TLS", value: "tls" }
                ]
                current: page.transport
                onPicked: v => page.transport = v
            }
            Picks {
                label: Tr.t("Port")
                options: [
                    { label: "5060", value: "5060" },
                    { label: "5061", value: "5061" },
                    { label: Tr.t("Other…"), value: "" }
                ]
                current: (page.port === "5060" || page.port === "5061") ? page.port : ""
                onPicked: v => { page.port = v; if (v !== "") portField.text = ""; }
            }
            TextField {
                id: portField
                Layout.fillWidth: true
                visible: page.port !== "5060" && page.port !== "5061"
                label: Tr.t("Port")
                placeholder: Tr.t("Type a port number")
                mode: "digits"
                onAccepted: { if (/^\d+$/.test(text.trim())) { page.port = text.trim(); text = ""; } }
            }
            SwitchRow {
                Layout.fillWidth: true
                text: Tr.t("Use this account")
                hint: Tr.t("Off keeps the account without making calls")
                checked: page.accountEnabled
                onToggled: on => page.accountEnabled = on
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Button {
                    text: page.editId !== "" ? Tr.t("Save changes") : Tr.t("Add account")
                    kind: "primary"
                    enabled: nameField.text.trim() !== "" && userField.text.trim() !== ""
                             && serverField.text.trim() !== "" && page.port !== ""
                             && (page.editId !== "" || passField.text !== "")
                    onClicked: page.saveAccount()
                }
                Button {
                    visible: page.editId !== ""
                    text: Tr.t("Cancel")
                    onClicked: page.clearForm()
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Landline")
        hint: Tr.t("A box that connects an ordinary phone line. It is set up with the address of that box on your network.")
        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: page.landlineState()
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        TextField {
            id: hostField
            Layout.fillWidth: true
            label: Tr.t("Address of the box")
            placeholder: Tr.t("Its address on your network")
            visible: !page.landlineReady()
        }
        RowLayout {
            Layout.fillWidth: true
            visible: !page.landlineReady()
            spacing: Theme.px(6)
            Button {
                text: Tr.t("Start setup")
                enabled: hostField.text.trim() !== ""
                onClicked: Lines.landlineSetup(hostField.text.trim())
            }
        }
        TextField {
            id: codeField
            Layout.fillWidth: true
            label: Tr.t("Verification code")
            placeholder: Tr.t("The code sent to your phone")
            mode: "digits"
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Button {
                text: Tr.t("Finish setup")
                enabled: codeField.text.trim() !== ""
                onClicked: Lines.landlineFinish(codeField.text.trim())
            }
            ConfirmButton {
                id: forgetLandline
                implicitWidth: Math.max(Theme.touchTarget, forgetLandline.armedText.length * 8 + 28)
                implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                text: Tr.t("Forget the landline")
                armedText: Tr.t("Tap again to forget")
                kind: forgetLandline.armed ? "danger" : "plain"
                interval: 4000
                enabled: page.landlineReady() || page.landlineWaiting()
                onConfirmed: Lines.landlineForget()
            }
        }
    }

    BusyNote {
        Layout.fillWidth: true
        visible: Lines.busy
        note: Tr.t("Saving…")
    }
    InfoBanner {
        Layout.fillWidth: true
        visible: Lines.note !== ""
        tone: "info"
        text: Lines.note
    }
}
