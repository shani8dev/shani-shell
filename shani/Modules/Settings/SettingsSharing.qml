// Settings > Sharing: your folders on the local network (Samba usershares -
// what Nautilus's and Dolphin's "Share" write; the niri image has no such
// plugin, so it is here). Three things must hold, each shown and each fixable:
// the file-sharing service runs, this account may share (group sambashare),
// and it has a network password (Samba keeps its own). System-wide shares in
// smb.conf are managed by the system SMB configuration; these are yours alone. Remote login
// is the on/off GNOME also has; sshd_config controls how people sign in.
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
    readonly property string user: Quickshell.env("USER") || ""
    property bool smbOn: false
    property bool sshOn: false
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property bool sshPassword: true
    property bool sshPubkey: true
    property bool sshRoot: false
    property string sshAllowUsers: ""
    property string sshAllowGroups: ""
    property bool sshTcpForwarding: true
    property bool sshX11Forwarding: false
    property string sshMaxAuthTries: "6"
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
    property bool noteOk: false
    property string pairUrl: "https://localhost:47990/pin"
    property string pairPin: ""
    property bool pairLoading: false

    readonly property string accessTool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_ACCESS_TOOL"), "system_access.py")
    readonly property string nfsTool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_SHARING_TOOL"), "system_nfs.py")
    readonly property string smbTool: ToolPath.of(Quickshell.env("SHANI_SYSTEM_SMB_TOOL"), "system_smb.py")

    // Remote login rules are staged first: the bridge hands back the file text,
    // its digest and any lines it cannot represent. Only then is it written as
    // root. `sshPendingNote` is the one note shown when the write succeeds.
    property string sshPendingNote: ""
    property string sshStageText: ""
    property string sshStageSha: ""
    property bool sshRefuse: false
    property string sshStageError: ""
    property var sshKept: []
    property var sshUnreadable: []

    // Network folders (NFS): rows are the whole file as the person wants it.
    property var nfsRows: []
    property var nfsKept: []
    property var nfsUnreadable: []
    property string nfsAccess: "rw"
    property string nfsSync: "sync"
    property bool nfsNoSubtreeCheck: true
    property string nfsSquash: "root_squash"
    property string nfsNote: ""
    property bool nfsNoteOk: false

    // System-wide shares (Samba), read through the state tool.
    property var smbState: ({})
    property string smbUser: ""
    property bool smbReadOnly: true
    property string smbNote: ""
    property bool smbNoteOk: false
    readonly property var smbAccounts: page.smbState.accounts || []
    readonly property var smbUnits: page.smbState.units || ({})

    property bool busy: act.running || state.running || stageProc.running || writeProc.running
                        || nfsReadProc.running || nfsStageProc.running || nfsWriteProc.running
                        || smbReadProc.running || smbStageProc.running || smbWriteProc.running
                        || pinProc.running

    onActiveChanged: if (active) { state.running = true; page.loadNfs(); page.loadSmb(); }
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) { state.running = true; page.loadNfs(); page.loadSmb(); }

    function run(cmd, done, input) { act.command = cmd; act.done = done || ""; act.input = input || ""; act.running = true; }
    Process {
        id: state
        command: ["sh", "-c", 'systemctl is-active -q smb && echo smb=on; systemctl is-active -q sshd && echo ssh=on; id -nG | tr " " "\\n" | grep -qx sambashare && echo group=yes
            getent group sambashare | grep -qw "$(id -un)" && echo groupnext=yes; echo "host=$(hostnamectl hostname 2>/dev/null || uname -n)"
            for u in app-dev.lizardbyte.app.Sunshine.service sunshine.service; do systemctl --user cat "$u" >/dev/null 2>&1 || continue
                echo "sun=$u"; systemctl --user is-active -q "$u" && echo sunon=yes
                getcap "$(command -v sunshine)" 2>/dev/null | grep -q cap_sys_admin && echo suncap=yes; break; done
            f=/etc/ssh/sshd_config.d/50-shani-shell.conf; [ -r "$f" ] && grep -iE \'^(PasswordAuthentication|PubkeyAuthentication|PermitRootLogin) \' "$f" | sed \'s/^/sshd_/\' || true
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
                const get = k => { const m = new RegExp("^sshd_" + k + "\\s+(\\S+)", "mi").exec(text); return m ? m[1].toLowerCase() : ""; };
                page.sshPassword = get("PasswordAuthentication") !== "no";
                page.sshPubkey = get("PubkeyAuthentication") !== "no";
                page.sshRoot = get("PermitRootLogin") === "yes";
                const raw = k => { const m = new RegExp("^sshd_" + k + "\\s+(.*)", "mi").exec(text); return m ? m[1].trim() : ""; };
                page.sshAllowUsers = raw("AllowUsers"); page.sshAllowGroups = raw("AllowGroups");
                page.sshTcpForwarding = get("AllowTcpForwarding") !== "no";
                page.sshX11Forwarding = get("X11Forwarding") === "yes";
                page.sshMaxAuthTries = raw("MaxAuthTries") || "6";
                sshAllowUsersField.text = page.sshAllowUsers; sshAllowGroupsField.text = page.sshAllowGroups;
                sshMaxAuthTriesField.text = page.sshMaxAuthTries;
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
            page.noteOk = code === 0;
            state.running = true;
        }
    }

    // ---- shared helpers ----------------------------------------------------
    function flagNote(text, ok) { page.note = text || ""; page.noteOk = !!ok; }

    function textOf(v) {
        if (v === null || v === undefined || v === "") return "";
        if (Array.isArray(v)) return v.join(", ");
        if (typeof v === "object") {
            const parts = [];
            for (const k in v) parts.push(k + ": " + String(v[k]));
            return parts.join(", ");
        }
        return String(v);
    }

    function warningText(code) {
        if (code === "no_root_squash") return Tr.t("A remote user can act as root on this folder. Files they make may be owned by root.");
        if (code === "all_squash") return Tr.t("Every remote user is treated as one local account, so file owners may look unexpected.");
        return String(code);
    }

    // ---- remote login rules: stage, show kept lines, then write as root ----
    function sshBody(over) {
        const body = {
            password: page.sshPassword, pubkey: page.sshPubkey, root: page.sshRoot,
            allowUsers: sshAllowUsersField.text.trim(), allowGroups: sshAllowGroupsField.text.trim(),
            tcpForwarding: page.sshTcpForwarding, x11Forwarding: page.sshX11Forwarding,
            maxAuthTries: sshMaxAuthTriesField.text.trim() || "6"
        };
        if (over) for (const k in over) body[k] = over[k];
        return body;
    }
    function sshApply(over, done) {
        page.sshPendingNote = done || Tr.t("Remote login rules updated");
        page.sshRefuse = false; page.sshStageError = "";
        page.sshKept = []; page.sshUnreadable = [];
        stageProc.payload = JSON.stringify(sshBody(over));
        stageProc.running = false; stageProc.running = true;
    }
    Process {
        id: stageProc
        stdinEnabled: true
        property string payload: ""
        command: ["python3", page.accessTool, "sshd-stage"]
        stdout: StdioCollector { id: stageOut }
        stderr: StdioCollector { id: stageErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            let d = {};
            try { d = JSON.parse(stageOut.text); } catch (e) {}
            const err = d.error || stageErr.text.trim().split("\n").pop() || "";
            page.sshStageText = d.text || ""; page.sshStageSha = d.sha256 || "";
            page.sshRefuse = !!d.refuse; page.sshStageError = err || "";
            page.sshKept = d.kept || []; page.sshUnreadable = d.unreadable || [];
            if (code !== 0 || err !== "" || page.sshRefuse || page.sshUnreadable.length > 0 || !page.sshStageText || !page.sshStageSha) {
                page.flagNote(err || Tr.t("The login rules were not changed"));
                return;
            }
            writeProc.payload = JSON.stringify({ text: page.sshStageText, sha256: page.sshStageSha });
            writeProc.running = false; writeProc.running = true;
        }
    }
    Process {
        id: writeProc
        stdinEnabled: true
        property string payload: ""
        command: page.adminCmd.concat(["remote-access-set"])
        stdout: StdioCollector { id: writeOut }
        stderr: StdioCollector { id: writeErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            let d = {};
            try { d = JSON.parse(writeOut.text); } catch (e) {}
            const err = d.error || writeErr.text.trim().split("\n").pop() || "";
            if (code === 0 && d.ok !== false && err === "") page.flagNote(page.sshPendingNote, true);
            else page.flagNote(err || Tr.t("The login rules were not saved"));
            state.running = true;
        }
    }

    // ---- network folders (NFS) ---------------------------------------------
    function loadNfs() { nfsReadProc.running = false; nfsReadProc.running = true; }
    Process {
        id: nfsReadProc
        command: ["python3", page.nfsTool, "exports"]
        stdout: StdioCollector { id: nfsOut }
        stderr: StdioCollector { id: nfsErr }
        onExited: code => {
            let d = {};
            try { d = JSON.parse(nfsOut.text); } catch (e) {}
            const err = d.error || nfsErr.text.trim().split("\n").pop() || "";
            if (code !== 0 || err !== "") {
                page.nfsNote = err || Tr.t("Could not read the folder shares"); page.nfsNoteOk = false;
                return;
            }
            page.nfsRows = d.rows || []; page.nfsKept = d.kept || []; page.nfsUnreadable = d.unreadable || [];
        }
    }
    function nfsRowSummary(row) {
        const parts = [];
        for (const c of (row.clients || [])) {
            const o = (c.options || []).join(", ");
            parts.push(String(c.client || "*") + (o ? " (" + o + ")" : ""));
        }
        return parts.join("; ") || Tr.t("no clients listed");
    }
    function nfsWarningList() {
        const out = [];
        for (const r of (page.nfsRows || [])) {
            const codes = [];
            const add = ws => { for (const w of (ws || [])) if (codes.indexOf(w) < 0) codes.push(w); };
            add(r.warnings);
            for (const c of (r.clients || [])) add(c.warnings);
            for (const w of codes) out.push({ path: r.path || "", code: String(w) });
        }
        return out;
    }
    function addNfsRow() {
        const p = nfsFolder.value.trim();
        if (p === "") return;
        const opts = [page.nfsAccess, page.nfsSync];
        if (page.nfsNoSubtreeCheck) opts.push("no_subtree_check");
        opts.push(page.nfsSquash);
        const row = { path: p, clients: [{ client: nfsClient.text.trim() || "*", options: opts }], warnings: [], raw: "", editable: true };
        page.nfsRows = page.nfsRows.concat([row]);
        nfsFolder.value = "";
        page.nfsNote = Tr.t("Added — save to apply"); page.nfsNoteOk = true;
    }
    function removeNfsRow(i) {
        const next = page.nfsRows.slice();
        next.splice(i, 1);
        page.nfsRows = next;
        page.nfsNote = Tr.t("Removed — save to apply"); page.nfsNoteOk = true;
    }
    function saveNfs() {
        const body = { rows: [], other: page.nfsKept.slice() };
        for (const r of page.nfsRows) {
            const clients = [];
            for (const c of (r.clients || [])) clients.push({ client: c.client, options: c.options || [] });
            body.rows.push({ path: r.path, clients: clients });
        }
        if (body.rows.length === 0) body.confirm = "REMOVE ALL";
        page.nfsNote = "";
        nfsStageProc.payload = JSON.stringify(body);
        nfsStageProc.running = false; nfsStageProc.running = true;
    }
    Process {
        id: nfsStageProc
        stdinEnabled: true
        property string payload: ""
        command: ["python3", page.nfsTool, "stage"]
        stdout: StdioCollector { id: nfsStageOut }
        stderr: StdioCollector { id: nfsStageErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            let d = {};
            try { d = JSON.parse(nfsStageOut.text); } catch (e) {}
            const err = d.error || nfsStageErr.text.trim().split("\n").pop() || "";
            if (code !== 0 || err !== "" || !!d.refuse || !d.text || !d.sha256) {
                page.nfsNote = err || (d.refuse ? Tr.t("These folder shares cannot be changed safely here") : Tr.t("Could not prepare the folder shares"));
                page.nfsNoteOk = false;
                return;
            }
            nfsWriteProc.payload = JSON.stringify({ text: d.text, sha256: d.sha256 });
            nfsWriteProc.running = false; nfsWriteProc.running = true;
        }
    }
    Process {
        id: nfsWriteProc
        stdinEnabled: true
        property string payload: ""
        command: page.adminCmd.concat(["nfs-exports-set"])
        stdout: StdioCollector { id: nfsWriteOut }
        stderr: StdioCollector { id: nfsWriteErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            let d = {};
            try { d = JSON.parse(nfsWriteOut.text); } catch (e) {}
            const err = d.error || nfsWriteErr.text.trim().split("\n").pop() || "";
            if (code === 0 && d.ok !== false && err === "") {
                page.flagNote(Tr.t("Folder shares saved: mode %1, owner %2", d.mode || "?", d.owner || "?"), true);
                page.nfsNote = page.note; page.nfsNoteOk = true;
            } else {
                page.flagNote(err || Tr.t("Folder shares were not saved"));
                page.nfsNote = page.note; page.nfsNoteOk = false;
            }
            page.loadNfs();
        }
    }

    // ---- system-wide shares (Samba) ----------------------------------------
    function loadSmb() { smbReadProc.running = false; smbReadProc.running = true; }
    Process {
        id: smbReadProc
        command: ["python3", page.smbTool, "state"]
        stdout: StdioCollector { id: smbOut }
        stderr: StdioCollector { id: smbErr }
        onExited: code => {
            let d = {};
            try { d = JSON.parse(smbOut.text); } catch (e) {}
            const err = d.error || smbErr.text.trim().split("\n").pop() || "";
            if (code !== 0 || err !== "") {
                page.smbNote = err || Tr.t("Could not read the sharing settings"); page.smbNoteOk = false;
                return;
            }
            page.smbState = d;
        }
    }
    function smbTestparm() {
        const t = page.smbState.testparm;
        if (t === true || t === "ok" || t === "valid") return Tr.t("The configuration is valid");
        if (t === false || t === "invalid") return Tr.t("The configuration has errors");
        if (t && typeof t === "object") return t.ok === false || t.valid === false ? Tr.t("The configuration has errors") : Tr.t("The configuration is valid");
        return t ? String(t) : Tr.t("Not checked yet");
    }
    function smbConfigValid() {
        const t = page.smbState.testparm;
        if (t === false || t === "invalid") return false;
        if (t && typeof t === "object") return t.ok !== false && t.valid !== false;
        return true;
    }
    function saveSmb() {
        const users = page.smbUser === "" ? [] : [page.smbUser];
        const share = {
            name: smbName.text.trim(), path: smbFolder.value,
            users: users, guestOk: false, readOnly: page.smbReadOnly
        };
        page.smbNote = "";
        smbStageProc.payload = JSON.stringify({ shares: [share] });
        smbStageProc.running = false; smbStageProc.running = true;
    }
    Process {
        id: smbStageProc
        stdinEnabled: true
        property string payload: ""
        command: ["python3", page.smbTool, "stage"]
        stdout: StdioCollector { id: smbStageOut }
        stderr: StdioCollector { id: smbStageErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            let d = {};
            try { d = JSON.parse(smbStageOut.text); } catch (e) {}
            const err = d.error || smbStageErr.text.trim().split("\n").pop() || "";
            if (code !== 0 || err !== "" || !!d.refuse || !d.text || !d.sha256) {
                page.smbNote = err || (d.refuse ? Tr.t("Guest access is not allowed here") : Tr.t("Could not prepare this share"));
                page.smbNoteOk = false;
                return;
            }
            smbWriteProc.payload = JSON.stringify({ text: d.text, sha256: d.sha256 });
            smbWriteProc.running = false; smbWriteProc.running = true;
        }
    }
    Process {
        id: smbWriteProc
        stdinEnabled: true
        property string payload: ""
        command: page.adminCmd.concat(["smb-share-set"])
        stdout: StdioCollector { id: smbWriteOut }
        stderr: StdioCollector { id: smbWriteErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            let d = {};
            try { d = JSON.parse(smbWriteOut.text); } catch (e) {}
            const err = d.error || smbWriteErr.text.trim().split("\n").pop() || "";
            if (code === 0 && d.ok !== false && err === "") {
                page.flagNote(Tr.t("Share saved: mode %1, owner %2", d.mode || "?", d.owner || "?"), true);
                page.smbNote = page.note; page.smbNoteOk = true;
            } else {
                page.flagNote(err || Tr.t("The share was not saved"));
                page.smbNote = page.note; page.smbNoteOk = false;
            }
            page.loadSmb();
        }
    }

    // Sunshine's /pin page is HTTPS with a self-signed certificate. Read the PIN
    // through the shell so pairing never lands in a browser certificate warning.
    Process {
        id: pinProc
        command: ["sh", "-c", 'curl -sk --max-time 6 https://localhost:47990/pin 2>/dev/null | sed -e "s/<[^>]*>/ /g" | grep -oE "[0-9]{4,8}" | head -1']
        stdout: StdioCollector { onStreamFinished: page.pairPin = text.trim() }
        onExited: code => { page.pairLoading = false; if (code !== 0) page.pairPin = ""; }
    }

    // Nearby Share (LocalSend): found by phones and computers here, for this session only
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Nearby Share")
        SwitchRow {
            Layout.fillWidth: true
            text: Tr.t("Visible to devices nearby")
            hint: Nearby.visible_ ? Tr.t("On until you turn it off or sign out — LocalSend apps on this network can send you files, and you say yes to each")
                                  : Tr.t("Off — nothing can find this computer; you can still send")
            checked: Nearby.visible_
            onToggled: on => Nearby.setVisible(on)
        }
        Text {
            Layout.fillWidth: true
            visible: Nearby.note !== ""
            text: Nearby.note
            color: Theme.danger
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        ListRow {
            Layout.fillWidth: true
            icon: "send-to"
            title: Tr.t("Open Nearby Share")
            subtitle: Tr.t("Devices around you, and files on the way")
            onClicked: { Ui.closeAll(); Ui.nearby = true; }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Share folders on this network")
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
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Button { visible: !page.groupNext; text: Tr.t("Allow"); onClicked: page.run(["pkexec", "gpasswd", "-a", page.user, "sambashare"], Tr.t("Allowed — sign out and in again to share")) }
        }
        // Samba's own password for this account: what someone types when opening your share
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(8)
            TextField {
                id: pw; Layout.fillWidth: true; secret: true; placeholder: Tr.t("Network password for your shares"); label: Tr.t("Network password")
                error: pw.text.length > 0 && pw.text.length < 4 ? Tr.t("At least 4 characters") : ""
            }
            Button {
                text: Tr.t("Set")
                enabled: pw.text.length >= 4
                onClicked: { page.run(["pkexec", "smbpasswd", "-s", "-a", page.user], Tr.t("Network password set"), pw.text + "\n" + pw.text + "\n"); pw.text = ""; }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Remote login")
        SwitchRow {
            Layout.fillWidth: true
            text: Tr.t("Secure Shell (SSH)")
            hint: page.sshOn ? "ssh " + page.user + "@" + page.host + ".local" : Tr.t("Off — turn on to allow remote login over SSH")
            checked: page.sshOn
            onToggled: on => page.run(["pkexec", "systemctl", on ? "enable" : "disable", "--now", "sshd"], on ? Tr.t("Remote login is on") : Tr.t("Remote login is off"))
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.px(12)
            visible: page.sshOn
            spacing: Theme.px(2)
            SwitchRow {
                Layout.fillWidth: true
                text: Tr.t("Allow password login")
                hint: Tr.t("Turn off to allow keys only")
                checked: page.sshPassword
                onToggled: on => page.sshApply({ password: on }, Tr.t("Remote login rules updated"))
            }
            SwitchRow {
                Layout.fillWidth: true
                text: Tr.t("Allow key login")
                hint: Tr.t("Sign in with an SSH key instead of a password")
                checked: page.sshPubkey
                onToggled: on => page.sshApply({ pubkey: on }, Tr.t("Remote login rules updated"))
            }
            SwitchRow {
                Layout.fillWidth: true
                text: Tr.t("Allow root login")
                hint: Tr.t("Off is safer")
                checked: page.sshRoot
                onToggled: on => page.sshApply({ root: on }, Tr.t("Remote login rules updated"))
            }
            SwitchRow { Layout.fillWidth: true; text: Tr.t("Allow TCP forwarding"); hint: Tr.t("Let tools tunnel connections through this computer"); checked: page.sshTcpForwarding; onToggled: on => { page.sshTcpForwarding = on; page.sshApply({ tcpForwarding: on }, Tr.t("Remote login rules updated")); } }
            SwitchRow { Layout.fillWidth: true; text: Tr.t("Allow X11 forwarding"); hint: Tr.t("Let remote apps open windows on this screen"); checked: page.sshX11Forwarding; onToggled: on => { page.sshX11Forwarding = on; page.sshApply({ x11Forwarding: on }, Tr.t("Remote login rules updated")); } }
            RowLayout { Layout.fillWidth: true; spacing: Theme.px(6); Text { text: Tr.t("Max auth tries"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale } TextField { id: sshMaxAuthTriesField; Layout.preferredWidth: Theme.px(80); placeholder: "6"; label: Tr.t("Maximum sign-in tries") } }
            Text { text: Tr.t("Allow users (space separated, empty = all)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: sshAllowUsersField; Layout.fillWidth: true; placeholder: page.user; label: Tr.t("Users allowed to sign in") }
            Text { text: Tr.t("Allow groups (space separated, empty = all)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            TextField { id: sshAllowGroupsField; Layout.fillWidth: true; placeholder: "wheel"; label: Tr.t("Groups allowed to sign in") }
            Button { text: Tr.t("Save allow list"); kind: "primary"; enabled: !page.busy; busy: act.running || stageProc.running || writeProc.running; onClicked: page.sshApply(null, Tr.t("Remote login rules updated")) }
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.sshRefuse || page.sshStageError !== ""
            tone: "error"
            title: Tr.t("Login rules were not changed")
            text: page.sshStageError || Tr.t("This file has settings this page cannot change safely. Open a terminal and edit it by hand.")
        }
        SettingsSection {
            Layout.fillWidth: true
            visible: page.sshKept.length > 0 || page.sshUnreadable.length > 0
            title: Tr.t("Lines kept as they are")
            hint: Tr.t("These lines were left alone. Edit them by hand in a terminal if they need to change.")
            Repeater {
                model: page.sshKept
                ListRow {
                    required property string modelData
                    Layout.fillWidth: true
                    icon: "document"
                    title: modelData
                    interactive: false
                }
            }
            Repeater {
                model: page.sshUnreadable
                ListRow {
                    required property string modelData
                    Layout.fillWidth: true
                    icon: "dialog-warning"
                    title: modelData
                    subtitle: Tr.t("This page could not read it")
                    trailing: Tr.t("not changed")
                    interactive: false
                }
            }
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
        ColumnLayout {
            visible: page.sunUnit !== "" && page.sunOn
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Button {
                text: Tr.t("Get pairing PIN")
                enabled: !page.pairLoading
                onClicked: { page.pairLoading = true; page.pairPin = ""; pinProc.running = false; pinProc.running = true; }
            }
            Text {
                visible: page.pairPin !== ""
                Layout.fillWidth: true
                text: Tr.t("Pairing PIN: %1").arg(page.pairPin)
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(15) * Theme.fontScale
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: (page.pairPin !== "" ? Tr.t("Enter this in Moonlight within 30 seconds; if it expires, get the PIN again. ")
                                           : "") + Tr.t("Pairing page: %1 (self-signed certificate — a browser will warn).").arg(page.pairUrl)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Button {
                text: page.pairPin !== "" ? Tr.t("Copy PIN") : Tr.t("Copy pairing address")
                onClicked: Quickshell.clipboardText = page.pairPin !== "" ? page.pairPin : page.pairUrl
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Network folders (NFS)")
        hint: Tr.t("Folders from this computer that other computers on the network can open.")
        EmptyState {
            visible: page.nfsRows.length === 0
            icon: "folder-remote"
            title: Tr.t("No folders shared here yet")
            subtitle: Tr.t("Add one below, then save.")
        }
        Repeater {
            model: page.nfsRows
            ListRow {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                icon: "folder-remote"
                title: modelData.path || ""
                subtitle: page.nfsRowSummary(modelData)
                interactive: false
                ConfirmButton {
                    visible: modelData.editable !== false
                    Accessible.name: Tr.t("Remove the share for %1", modelData.path)
                    implicitWidth: Math.max(Theme.touchTarget, armedText.length * 8 + 28)
                    implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                    text: Tr.t("Remove…")
                    armedText: Tr.t("Tap again to remove")
                    kind: "danger"
                    onConfirmed: page.removeNfsRow(index)
                }
            }
        }
        Repeater {
            model: page.nfsWarningList()
            InfoBanner {
                required property var modelData
                Layout.fillWidth: true
                tone: "warn"
                title: Tr.t("Check file ownership in %1", modelData.path)
                text: page.warningText(modelData.code)
            }
        }
        SettingsSection {
            Layout.fillWidth: true
            visible: page.nfsKept.length > 0 || page.nfsUnreadable.length > 0
            title: Tr.t("Lines kept as they are")
            hint: Tr.t("These lines stay in the file. Edit them by hand in a terminal if they need to change.")
            Repeater {
                model: page.nfsKept
                ListRow {
                    required property string modelData
                    Layout.fillWidth: true
                    icon: "document"
                    title: modelData
                    interactive: false
                }
            }
            Repeater {
                model: page.nfsUnreadable
                ListRow {
                    required property string modelData
                    Layout.fillWidth: true
                    icon: "dialog-warning"
                    title: modelData
                    subtitle: Tr.t("This page could not read it")
                    trailing: Tr.t("not changed")
                    interactive: false
                }
            }
        }
        SettingsSection {
            Layout.fillWidth: true
            title: Tr.t("Add a folder to share")
            FolderPicker { id: nfsFolder; label: Tr.t("Folder to share") }
            TextField {
                id: nfsClient
                Layout.fillWidth: true
                label: Tr.t("Who can use it: an account, an address, or * for everyone")
                placeholder: "*"
                text: "*"
            }
            Picks {
                label: Tr.t("Can change files")
                options: [{ label: Tr.t("Read only"), value: "ro" }, { label: Tr.t("Can change files"), value: "rw" }]
                current: page.nfsAccess
                onPicked: v => page.nfsAccess = v
            }
            Picks {
                label: Tr.t("How writes are handled")
                options: [{ label: Tr.t("Wait for each write"), value: "sync" }, { label: Tr.t("Queue writes"), value: "async" }]
                current: page.nfsSync
                onPicked: v => page.nfsSync = v
            }
            Choice {
                text: Tr.t("Skip subtree checks")
                accessibleName: Tr.t("No subtree check")
                selected: page.nfsNoSubtreeCheck
                onClicked: page.nfsNoSubtreeCheck = !page.nfsNoSubtreeCheck
            }
            Picks {
                label: Tr.t("Remote file owners")
                options: [
                    { label: Tr.t("Remote root is not root here"), value: "root_squash" },
                    { label: Tr.t("Remote root acts as root here"), value: "no_root_squash" },
                    { label: Tr.t("Everyone is treated as one user"), value: "all_squash" }
                ]
                current: page.nfsSquash
                onPicked: v => page.nfsSquash = v
            }
            InfoBanner {
                Layout.fillWidth: true
                visible: page.nfsSquash !== "root_squash"
                tone: "warn"
                text: page.warningText(page.nfsSquash)
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button {
                    text: Tr.t("Add folder")
                    enabled: nfsFolder.value !== "" && !page.busy
                    onClicked: page.addNfsRow()
                }
                Button {
                    text: Tr.t("Save folder shares")
                    kind: "primary"
                    enabled: !page.busy
                    busy: nfsStageProc.running || nfsWriteProc.running
                    onClicked: page.saveNfs()
                }
            }
            InfoBanner {
                Layout.fillWidth: true
                visible: page.nfsNote !== ""
                tone: page.nfsNoteOk ? "ok" : "error"
                text: page.nfsNote
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Shared folders for this computer (Samba)")
        hint: Tr.t("System-wide shares from this computer. People sign in with an account and a network password.")
        InfoBanner {
            Layout.fillWidth: true
            tone: page.smbConfigValid() ? "ok" : "warn"
            text: page.smbTestparm()
        }
        ListRow {
            Layout.fillWidth: true
            icon: "preferences-system"
            title: Tr.t("File sharing service")
            subtitle: page.textOf(page.smbUnits.smb) || Tr.t("not installed")
            interactive: false
        }
        ListRow {
            Layout.fillWidth: true
            icon: "preferences-system"
            title: Tr.t("Name browsing service")
            subtitle: page.textOf(page.smbUnits.nmb) || Tr.t("not installed")
            interactive: false
        }
        ListRow {
            Layout.fillWidth: true
            icon: "preferences-system"
            title: Tr.t("Account service")
            subtitle: page.textOf(page.smbUnits.winbind) || Tr.t("not installed")
            interactive: false
        }
        ListRow {
            Layout.fillWidth: true
            icon: "system-users"
            title: Tr.t("Accounts on this computer")
            subtitle: page.textOf(page.smbAccounts) || Tr.t("none")
            interactive: false
        }
        ListRow {
            Layout.fillWidth: true
            icon: "network-server"
            title: Tr.t("Open ports")
            subtitle: page.textOf(page.smbState.ports) || Tr.t("none")
            interactive: false
        }
        ListRow {
            Layout.fillWidth: true
            icon: "folder-remote"
            title: Tr.t("Your own shares")
            subtitle: page.textOf(page.smbState.usershares) || Tr.t("none")
            interactive: false
        }
        ListRow {
            Layout.fillWidth: true
            visible: page.textOf(page.smbState.configPath) !== ""
            icon: "document"
            title: Tr.t("Configuration file")
            subtitle: page.textOf(page.smbState.configPath)
            interactive: false
        }
        SettingsSection {
            Layout.fillWidth: true
            title: Tr.t("Add a share")
            TextField {
                id: smbName
                Layout.fillWidth: true
                label: Tr.t("Share name")
                placeholder: Tr.t("Share name")
            }
            FolderPicker { id: smbFolder; label: Tr.t("Folder to share") }
            Picks {
                label: Tr.t("Who can use it")
                options: [{ label: Tr.t("Anyone with an account"), value: "" }].concat((page.smbAccounts || []).map(a => ({ label: String(a), value: String(a) })))
                current: page.smbUser
                onPicked: v => page.smbUser = v
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Choice {
                    text: Tr.t("Read only")
                    selected: page.smbReadOnly
                    onClicked: page.smbReadOnly = true
                }
                Choice {
                    text: Tr.t("Can change files")
                    selected: !page.smbReadOnly
                    onClicked: page.smbReadOnly = false
                }
            }
            InfoBanner {
                Layout.fillWidth: true
                tone: "warn"
                text: Tr.t("Guest access is not offered here. People sign in with an account on this computer and a network password.")
            }
            Button {
                text: Tr.t("Save share")
                kind: "primary"
                enabled: smbName.text.trim() !== "" && smbFolder.value !== "" && !page.busy
                busy: smbStageProc.running || smbWriteProc.running
                onClicked: page.saveSmb()
            }
            InfoBanner {
                Layout.fillWidth: true
                visible: page.smbNote !== ""
                tone: page.smbNoteOk ? "ok" : "error"
                text: page.smbNote
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Cast this screen")
        Text {
            visible: Cast.available
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Cast.active ? Tr.t("Casting — GNOME Network Displays is sharing this screen")
                              : Tr.t("Off — share this screen with a TV or Chromecast")
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        Text {
            visible: !Cast.available
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Tr.t("Casting is not available on this computer.")
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        RowLayout {
            visible: Cast.available
            Layout.fillWidth: true
            spacing: Theme.px(8)
            Button { text: Tr.t("Cast…"); enabled: !Cast.active; onClicked: { Ui.closeAll(); Cast.open(); } }
            Button { visible: Cast.active; text: Tr.t("Stop casting"); onClicked: Cast.stop() }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Shared folders")
        Text {
            visible: page.shares.length === 0
            text: Tr.t("Nothing shared.")
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        Repeater {
            model: page.shares
            SettingRow {
                required property var modelData
                Layout.fillWidth: true
                icon: "folder-remote"
                title: modelData.name + " — " + modelData.path
                subtitle: "smb://" + page.host + ".local/" + modelData.name + " · " + (modelData.write ? Tr.t("others can change files") : Tr.t("read only"))
                IconButton { icon: "edit-delete"; tip: Tr.t("Stop sharing"); Accessible.name: Tr.t("Stop sharing %1", modelData.name); onClicked: page.run(["net", "usershare", "delete", modelData.name], Tr.t("%1 is no longer shared", modelData.name)) }
            }
        }
        ColumnLayout {
            visible: page.inGroup
            Layout.fillWidth: true
            spacing: Theme.px(8)
            FolderPicker {
                id: folderPicker
                label: Tr.t("Folder to share")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Choice { id: writable; text: Tr.t("Others can change files"); selected: false; onClicked: selected = !selected }
                Button {
                    text: Tr.t("Share")
                    enabled: folderPicker.value !== ""
                    onClicked: {
                        const path = folderPicker.value;
                        const name = path.replace(/\/+$/, "").split("/").pop().replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 60) || "share";
                        page.run(["net", "usershare", "add", name, path, "", "Everyone:" + (writable.selected ? "F" : "R"), "guest_ok=n"],
                                 Tr.t("%1 is shared", name));
                        folderPicker.value = "";
                    }
                }
            }
        }
    }

    BusyNote {
        Layout.fillWidth: true
        visible: page.busy
        note: Tr.t("Working…")
    }
    InfoBanner {
        Layout.fillWidth: true
        visible: page.note !== ""
        tone: page.noteOk ? "ok" : "error"
        text: page.note
    }
}
