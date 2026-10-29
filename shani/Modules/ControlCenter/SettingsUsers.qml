// Settings > Users: everyone who has an account here — add one, make one an
// administrator or not, set someone's password, remove one — and automatic
// login. Reading needs nothing; each change is bridge/shani-admin.py through
// pkexec, so the shell's polkit agent asks (an administrator's password for
// accounts, your own for automatic login). The helper refuses what would lock
// the machine: removing yourself, or the last administrator.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    readonly property string me: Quickshell.env("USER") || ""
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property var users: []                // [{ name, fullname, admin }]
    property string autologin: ""
    property string open: ""              // the user whose actions are shown
    property bool adding: false
    property string note: ""
    property bool busy: false
    readonly property bool iAmAdmin: (users.find(u => u.name === me) || {}).admin === true

    function refresh() { list.running = true; }
    onActiveChanged: if (active) refresh()
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) refresh()

    Process {
        id: list
        command: ["sh", "-c", 'getent passwd | awk -F: "\\$3 >= 1000 && \\$3 < 60000 && \\$7 !~ /(nologin|false)\\$/ {print \\$1 \\":\\" \\$5}"
            echo "--wheel=$(getent group wheel | cut -d: -f4)"
            f=/etc/greetd/shani-niri-autologin.toml; [ -f /etc/systemd/system/greetd.service.d/20-shani-autologin.conf ] && [ -f $f ] && echo "--auto=$(sed -n "s/^user *= *\\"\\(.*\\)\\"/\\1/p" $f | tail -1)"']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                const wheel = ((l.find(x => x.startsWith("--wheel=")) || "").slice(8)).split(",");
                page.autologin = (l.find(x => x.startsWith("--auto=")) || "").slice(7);
                page.users = l.filter(x => x && !x.startsWith("--")).map(x => {
                    const i = x.indexOf(":");
                    return { name: x.slice(0, i), fullname: x.slice(i + 1).split(",")[0], admin: wheel.indexOf(x.slice(0, i)) >= 0 };
                });
            }
        }
    }
    Process {
        id: admin
        stdinEnabled: true
        property string payload: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { ok: false, error: text.trim() || "cancelled" }; }
                page.note = r.ok ? "" : r.error;
                page.busy = false;
                page.refresh();
            }
        }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
    }
    function act(command, req) {
        busy = true;
        note = "";
        admin.payload = JSON.stringify(req);
        admin.command = adminCmd.concat([command]);
        admin.stdinEnabled = true;
        admin.running = true;
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Users") }
    Repeater {
        model: page.users
        ColumnLayout {
            id: urow
            required property var modelData
            Layout.fillWidth: true
            spacing: 4
            ListRow {
                Layout.fillWidth: true
                icon: "avatar-default"
                title: (urow.modelData.fullname || urow.modelData.name) + (urow.modelData.name === page.me ? "  (you)" : "")
                subtitle: urow.modelData.name + " · " + (urow.modelData.admin ? "Administrator" : "Standard")
                    + (page.autologin === urow.modelData.name ? " · signs in automatically" : "")
                trailing: page.iAmAdmin ? "›" : ""
                onClicked: if (page.iAmAdmin) page.open = page.open === urow.modelData.name ? "" : urow.modelData.name
            }
            ColumnLayout {
                visible: page.open === urow.modelData.name
                Layout.leftMargin: 28
                Layout.fillWidth: true
                spacing: 6
                SwitchRow {
                    Layout.fillWidth: true
                    text: Tr.t("Administrator")
                    hint: Tr.t("can install software, change the system and manage users")
                    checked: urow.modelData.admin
                    enabled: !page.busy && urow.modelData.name !== page.me
                    onToggled: on => page.act("user-admin", { username: urow.modelData.name, admin: on })
                }
                SwitchRow {
                    Layout.fillWidth: true
                    text: Tr.t("Sign in automatically")
                    hint: Tr.t("at start-up, without a password — only on a machine nobody else can reach")
                    checked: page.autologin === urow.modelData.name
                    enabled: !page.busy
                    onToggled: on => page.act("autologin", { username: on ? urow.modelData.name : "" })
                }
                TextField {
                    Layout.fillWidth: true
                    visible: urow.modelData.name !== page.me
                    placeholder: "New password for " + urow.modelData.name
                    secret: true
                    onAccepted: if (text !== "") { page.act("user-password", { username: urow.modelData.name, password: text }); text = ""; }
                }
                RowLayout {
                    visible: urow.modelData.name !== page.me
                    spacing: 6
                    property bool confirm: false
                    // what a standard account may run (GNOME's Parental Controls, malcontent)
                    Button {
                        visible: !parent.confirm && !urow.modelData.admin && page.iAmAdmin && AppFilter.canControl
                        text: Tr.t("Parental controls")
                        onClicked: AppFilter.openControls(urow.modelData.name)
                    }
                    Button {
                        visible: !parent.confirm
                        kind: "danger"
                        text: Tr.t("Remove…")
                        onClicked: parent.confirm = true
                    }
                    Button {
                        visible: parent.confirm
                        kind: "danger"
                        text: Tr.t("Remove, keep their files")
                        onClicked: { page.act("user-remove", { username: urow.modelData.name, deleteHome: false }); parent.confirm = false; page.open = ""; }
                    }
                    Button {
                        visible: parent.confirm
                        kind: "danger"
                        text: Tr.t("Remove with their files")
                        onClicked: { page.act("user-remove", { username: urow.modelData.name, deleteHome: true }); parent.confirm = false; page.open = ""; }
                    }
                    Button { visible: parent.confirm; text: Tr.t("Cancel"); onClicked: parent.confirm = false }
                }
            }
        }
    }

    // ---- add someone ------------------------------------------------------------
    Button {
        visible: page.iAmAdmin && !page.adding
        text: Tr.t("Add a user…")
        onClicked: page.adding = true
    }
    ColumnLayout {
        id: addForm
        visible: page.adding
        Layout.fillWidth: true
        spacing: 6
        property string user: ""
        property bool userEdited: false
        function suggest(name) {
            const first = (name.trim().split(/\s+/)[0] || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9_-]/g, "");
            return /^[a-z_]/.test(first) ? first.slice(0, 32) : "";
        }
        TextField { id: newName; Layout.fillWidth: true; placeholder: Tr.t("Their full name"); onTextChanged: if (!addForm.userEdited) addForm.user = addForm.suggest(text) }
        TextField {
            Layout.fillWidth: true
            placeholder: Tr.t("User name")
            text: addForm.user
            onTextChanged: if (text !== addForm.user) { addForm.userEdited = true; addForm.user = text; }
        }
        TextField { id: newPw; Layout.fillWidth: true; placeholder: Tr.t("Password (they can change it)"); secret: true }
        SwitchRow { id: newAdmin; Layout.fillWidth: true; text: Tr.t("Administrator"); checked: false }
        RowLayout {
            spacing: 6
            Button { text: Tr.t("Cancel"); onClicked: page.adding = false }
            Button {
                kind: "primary"
                text: Tr.t("Add")
                enabled: !page.busy && /^[a-z_][a-z0-9_-]{0,31}$/.test(addForm.user) && newPw.text !== ""
                onClicked: {
                    page.act("user-add", { username: addForm.user, fullname: newName.text.trim(), password: newPw.text, admin: newAdmin.checked });
                    newName.text = ""; newPw.text = ""; addForm.user = ""; addForm.userEdited = false;
                    page.adding = false;
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: !page.iAmAdmin && page.users.length > 0
        text: Tr.t("Only an administrator can add or change users.")
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
    Text {
        Layout.fillWidth: true
        visible: page.note !== ""
        text: page.note
        color: Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
