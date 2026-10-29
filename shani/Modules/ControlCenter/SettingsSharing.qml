// Settings > Sharing: your folders on the local network (Samba usershares -
// what Nautilus's and Dolphin's "Share" write; the niri image has no such
// plugin, so it is here). Three things must hold, each shown and each fixable:
// the file-sharing service runs, this account may share (group sambashare),
// and it has a network password (Samba keeps its own). System-wide shares in
// smb.conf are Cassini's (its SMB page); these are yours alone. Remote login
// is the on/off GNOME also has; how sshd lets people in is Cassini's page.
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
    readonly property string user: Quickshell.env("USER") || ""
    property bool smbOn: false
    property bool sshOn: false
    // remote desktop: niri cannot be reached over VNC or RDP; Sunshine captures
    // the screen through KMS (it needs cap_sys_admin) and Moonlight shows it on
    // another computer, a phone or a TV (niri discussion #680). Its user service
    // is the switch; pairing is a PIN on its own page.
    property string sunUnit: ""           // Sunshine's user unit, when installed
    property bool sunOn: false
    property bool sunCap: false
    property bool inGroup: false
    property bool groupNext: false        // added, takes effect at the next sign-in
    property var shares: []               // [{ name, path, write }]
    property string host: ""
    property string note: ""
    onActiveChanged: if (active) state.running = true
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) state.running = true

    function run(cmd, done, input) { act.command = cmd; act.done = done || ""; act.input = input || ""; act.running = true; }
    Process {
        id: state
        command: ["sh", "-c", 'systemctl is-active -q smb && echo smb=on; systemctl is-active -q sshd && echo ssh=on; id -nG | tr " " "\\n" | grep -qx sambashare && echo group=yes
            getent group sambashare | grep -qw "$(id -un)" && echo groupnext=yes; echo "host=$(hostnamectl hostname 2>/dev/null || uname -n)"
            for u in app-dev.lizardbyte.app.Sunshine.service sunshine.service; do systemctl --user cat "$u" >/dev/null 2>&1 || continue
                echo "sun=$u"; systemctl --user is-active -q "$u" && echo sunon=yes
                getcap "$(command -v sunshine)" 2>/dev/null | grep -q cap_sys_admin && echo suncap=yes; break; done
            command -v net >/dev/null && net usershare info 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                page.smbOn = /^smb=on$/m.test(text);
                page.sshOn = /^ssh=on$/m.test(text);
                page.sunUnit = (/^sun=(.*)$/m.exec(text) || [])[1] || "";
                page.sunOn = /^sunon=yes$/m.test(text);
                page.sunCap = /^suncap=yes$/m.test(text);
                page.inGroup = /^group=yes$/m.test(text);
                page.groupNext = /^groupnext=yes$/m.test(text);
                page.host = (/^host=(.*)$/m.exec(text) || [])[1] || "";
                const out = [];
                let cur = null;
                for (const l of text.split("\n")) {
                    const h = /^\[(.+)\]$/.exec(l);
                    if (h) { cur = { name: h[1], path: "", write: false }; out.push(cur); continue; }
                    if (!cur) continue;
                    const kv = /^(\w+)=(.*)$/.exec(l);
                    if (kv && kv[1] === "path") cur.path = kv[2];
                    if (kv && kv[1] === "usershare_acl") cur.write = /:F/.test(kv[2]);
                }
                page.shares = out;
            }
        }
    }
    Process {
        id: act
        property string done: ""
        property string input: ""
        stdinEnabled: true
        stderr: StdioCollector { id: actErr }
        onStarted: { if (act.input !== "") write(act.input); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            page.note = code === 0 ? act.done : (actErr.text.trim().split("\n").pop() || Tr.t("That did not work"));
            state.running = true;
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Share folders on this network") }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("File sharing")
        hint: page.smbOn ? Tr.t("On — others on this network can open what you share") : Tr.t("Off")
        checked: page.smbOn
        onToggled: on => page.run(["pkexec", "systemctl", on ? "enable" : "disable", "--now", "smb"], on ? Tr.t("File sharing is on") : Tr.t("File sharing is off"))
    }
    RowLayout {
        visible: !page.inGroup
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: page.groupNext ? Tr.t("This account may share folders from your next sign-in.")
                                 : Tr.t("This account may not share folders yet.")
            color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale
        }
        Button { visible: !page.groupNext; text: Tr.t("Allow"); onClicked: page.run(["pkexec", "gpasswd", "-a", page.user, "sambashare"], Tr.t("Allowed — sign out and in again to share")) }
    }
    // Samba's own password for this account: what someone types when opening your share
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        TextField { id: pw; Layout.fillWidth: true; secret: true; placeholder: Tr.t("Network password for your shares"); label: Tr.t("Network password") }
        Button {
            text: Tr.t("Set")
            enabled: pw.text.length >= 4
            onClicked: { page.run(["pkexec", "smbpasswd", "-s", "-a", page.user], Tr.t("Network password set"), pw.text + "\n" + pw.text + "\n"); pw.text = ""; }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Remote login") }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Secure Shell (SSH)")
        hint: page.sshOn ? "ssh " + page.user + "@" + page.host + ".local" : Tr.t("Off — sign-in rules are on Cassini's Remote access page")
        checked: page.sshOn
        onToggled: on => page.run(["pkexec", "systemctl", on ? "enable" : "disable", "--now", "sshd"], on ? Tr.t("Remote login is on") : Tr.t("Remote login is off"))
    }

    SwitchRow {
        Layout.fillWidth: true
        visible: page.sunUnit !== ""
        text: Tr.t("Remote desktop (Sunshine)")
        hint: !page.sunCap ? Tr.t("Sunshine cannot capture the screen: it needs cap_sys_admin (sudo setcap cap_sys_admin+p $(command -v sunshine))")
            : page.sunOn ? Tr.t("Open Moonlight on the other device and pick %1", page.host) : Tr.t("Off — this screen can be shown on another computer, phone or TV with Moonlight")
        checked: page.sunOn
        onToggled: on => page.run(["systemctl", "--user", on ? "enable" : "disable", "--now", page.sunUnit], on ? Tr.t("Remote desktop is on") : Tr.t("Remote desktop is off"))
    }
    Button {
        visible: page.sunUnit !== "" && page.sunOn
        text: Tr.t("Pair a device…")
        onClicked: Quickshell.execDetached(["xdg-open", "https://localhost:47990/pin"])
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Shared folders") }
    Text {
        visible: page.shares.length === 0
        text: Tr.t("Nothing shared.")
        color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale
    }
    Repeater {
        model: page.shares
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 10
            Icon { name: "folder-remote"; size: 20; color: Theme.accent }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { text: modelData.name + " — " + modelData.path; elide: Text.ElideMiddle; Layout.fillWidth: true; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale }
                Text { text: "smb://" + page.host + ".local/" + modelData.name + " · " + (modelData.write ? Tr.t("others can change files") : Tr.t("read only")); color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
            }
            IconButton { icon: "edit-delete"; tip: Tr.t("Stop sharing"); Accessible.name: Tr.t("Stop sharing %1", modelData.name); onClicked: page.run(["net", "usershare", "delete", modelData.name], Tr.t("%1 is no longer shared", modelData.name)) }
        }
    }
    RowLayout {
        visible: page.inGroup
        Layout.fillWidth: true
        spacing: 8
        TextField { id: folder; Layout.fillWidth: true; placeholder: Tr.t("Folder, e.g. ~/Public"); label: Tr.t("Folder to share") }
        Choice { id: writable; text: Tr.t("Others can change files"); selected: false; onClicked: selected = !selected }
        Button {
            text: Tr.t("Share")
            enabled: folder.text.trim() !== ""
            onClicked: {
                const path = folder.text.trim().replace(/^~/, Quickshell.env("HOME"));
                const name = path.replace(/\/+$/, "").split("/").pop().replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 60) || "share";
                page.run(["net", "usershare", "add", name, path, "", "Everyone:" + (writable.selected ? "F" : "R"), "guest_ok=n"],
                         Tr.t("%1 is shared", name));
                folder.text = "";
            }
        }
    }
    Text {
        visible: page.note !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: page.note
        color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale
    }
}
