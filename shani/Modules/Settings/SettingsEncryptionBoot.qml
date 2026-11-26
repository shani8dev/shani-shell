// Settings > Encryption and boot: read the disk's state, manage automatic
// unlock, make a recovery key, and take the signing-key step for Secure Boot.
// Passphrases, PINs and the recovery key go to the tool on stdin. They are
// never put in a command, in systemState, in a note or in a log.
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
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SECURITY_BOOT_TOOL"), "system_security_boot.py")

    property bool loaded: false
    property var report: ({})
    property bool noteOk: true
    property string note: ""
    property string error: ""
    property string readError: ""
    property string lastAction: ""
    property string shownKey: ""
    property bool usePin: false

    readonly property bool encrypted: !!report.encrypted
    readonly property bool tpmPresent: !!report.tpm2_present
    readonly property bool tpmEnrolled: !!report.tpm2_enrolled
    readonly property bool tpmPin: !!report.tpm2_pin
    readonly property bool secureBootKnown: page.loaded && typeof report.secure_boot === "boolean"
    readonly property bool secureBoot: page.secureBootKnown && !!report.secure_boot
    readonly property string policyMode: report.policy && report.policy.mode ? String(report.policy.mode) : ""
    readonly property bool canAuto: page.loaded && page.encrypted && page.tpmPresent
    readonly property bool busy: statusProc.running || enrollProc.running || removeProc.running
        || recoveryProc.running || headerProc.running || mokEnrollProc.running
        || mokCleanupProc.running || saveKeyProc.running

    onActiveChanged: {
        if (active) page.read();
        else page.clearKey();
        publish();
    }
    Component.onCompleted: { if (active) page.read(); publish(); }
    onLoadedChanged: publish()
    onBusyChanged: publish()
    onReportChanged: publish()
    onNoteChanged: publish()
    onErrorChanged: publish()
    onLastActionChanged: publish()
    onShownKeyChanged: publish()
    Component.onDestruction: page.clearKey()

    // Only stable state goes out. No key, no passphrase, no PIN.
    function publish() {
        const o = Object.assign({}, Ui.systemState || {});
        o.encryptionBoot = {
            loaded: page.loaded, busy: page.busy, encrypted: page.encrypted,
            tpmPresent: page.tpmPresent, tpmEnrolled: page.tpmEnrolled,
            tpmPin: page.tpmPin, secureBoot: page.secureBoot,
            policyMode: page.policyMode, note: page.note, error: page.error,
            lastAction: page.lastAction, keyShown: page.shownKey !== ""
        };
        Ui.systemState = o;
    }

    function reply(text) {
        try { return JSON.parse(text) || {}; }
        catch (e) { return { ok: false, error: Tr.t("Could not read the reply") }; }
    }
    function start(proc, name) {
        page.note = "";
        page.noteOk = true;
        page.error = "";
        page.lastAction = name || "";
        proc.gotReply = false;
        proc.running = true;
        publish();
    }
    function read() {
        page.clearKey();
        page.readError = "";
        page.error = "";
        statusProc.gotReply = false;
        statusProc.command = ["python3", page.tool, "status"];
        statusProc.running = true;
        publish();
    }
    function clearKey() { page.shownKey = ""; }
    function copyKey() { if (page.shownKey !== "") Quickshell.clipboardText = page.shownKey; }

    function policyWords(mode) {
        if (mode === "pcrlock") return Tr.t("a policy hash — survives an update that keeps the same policy");
        if (mode === "literal") return Tr.t("fixed PCR values — a firmware update stops it unlocking");
        return Tr.t("not determined");
    }

    function facts() {
        const enc = page.loaded ? (page.encrypted ? Tr.t("On") : Tr.t("Off")) : Tr.t("Not read yet");
        const encMean = page.encrypted
            ? Tr.t("Your files stay private if this computer is lost.")
            : Tr.t("Anyone with the disk can read your files.");
        const tpm = !page.tpmPresent ? Tr.t("Off — no TPM chip found")
            : page.tpmEnrolled ? (page.tpmPin ? Tr.t("On, with a PIN") : Tr.t("On, without a PIN"))
            : Tr.t("Off — not set up");
        const tpmMean = !page.tpmPresent
            ? Tr.t("Automatic unlock needs a TPM chip; check firmware settings.")
            : page.tpmEnrolled
                ? Tr.t("The disk opens by itself on this computer. Your passphrase still works.")
                : Tr.t("You type your passphrase at each boot.");
        const sb = page.loaded ? (page.secureBoot ? Tr.t("On") : Tr.t("Off")) : Tr.t("Not read yet");
        const sbMean = page.secureBoot
            ? Tr.t("Boot files are checked before the system starts.")
            : Tr.t("Boot files are not checked; turn it on in firmware settings.");
        return [
            { icon: "drive-harddisk", title: Tr.t("Disk encryption"), value: enc, meaning: encMean },
            { icon: "security-high", title: Tr.t("Automatic unlock"), value: tpm, meaning: tpmMean },
            { icon: "security-high", title: Tr.t("Secure Boot"), value: sb, meaning: sbMean },
            { icon: "dialog-password", title: Tr.t("Bound policy"), value: page.policyWords(page.policyMode),
              meaning: Tr.t("This decides whether a firmware change still lets the disk unlock by itself.") }
        ];
    }

    function act(name, path) {
        page.clearKey();
        const pass = diskPass.text.trim();
        const pin = pin1.text.trim();
        if (name === "enroll-on") {
            if (pass === "") { page.error = Tr.t("Enter your disk passphrase first."); publish(); return; }
            if (page.usePin && (pin === "" || pin !== pin2.text.trim())) {
                page.error = Tr.t("Enter the same PIN in both boxes."); publish(); return;
            }
            enrollProc.payload = page.usePin ? pass + "\n" + pin : pass;
            diskPass.text = ""; pin1.text = ""; pin2.text = "";
            enrollProc.command = ["python3", page.tool, "enroll"];
            start(enrollProc, name);
        } else if (name === "enroll-off") {
            diskPass.text = "";
            removeProc.command = ["python3", page.tool, "remove"];
            start(removeProc, name);
        } else if (name === "recovery-key") {
            const rp = keyPass.text.trim();
            if (rp === "") { page.error = Tr.t("Enter your disk passphrase first."); publish(); return; }
            recoveryProc.payload = rp;
            keyPass.text = "";
            recoveryProc.command = ["python3", page.tool, "recovery-key"];
            start(recoveryProc, name);
        } else if (name === "header-backup") {
            if (!path) { page.openHeaderPicker(); return; }
            headerProc.command = ["python3", page.tool, "header-backup", path];
            start(headerProc, name);
        } else if (name === "enroll-mok" || name === "cleanup-mok") {
            const p = name === "enroll-mok" ? mokEnrollProc : mokCleanupProc;
            p.command = ["python3", page.tool, name];
            start(p, name);
        }
    }

    function openKeyPicker() {
        FilePicker.open({ mode: "save", title: Tr.t("Save the recovery key"),
            defaultName: "shani-recovery-key-" + Qt.formatDate(new Date(), "yyyy-MM-dd") + ".txt",
            startPath: Quickshell.env("HOME") || "",
            onPicked: paths => { if (paths && paths.length) page.saveKey(paths[0]); } });
    }
    function saveKey(path) {
        // mode 0600: a recovery key is as sensitive as a password
        saveKeyProc.command = ["python3", "-c", "import os,sys;f=os.open(sys.argv[1],os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600);os.write(f,(sys.stdin.read().strip()+'\\n').encode());os.close(f);os.chmod(sys.argv[1],0o600)", path];
        saveKeyProc.payload = page.shownKey;
        saveKeyProc.running = true;
        publish();
    }
    function openHeaderPicker() {
        FilePicker.open({ mode: "save", title: Tr.t("Save a copy of the disk header"),
            defaultName: "shani-disk-header.img", startPath: Quickshell.env("HOME") || "",
            onPicked: paths => { if (paths && paths.length) page.act("header-backup", paths[0]); } });
    }

    Process {
        id: statusProc; property bool gotReply: false
        command: ["python3", page.tool, "status"]
        stdout: StdioCollector { onStreamFinished: {
            statusProc.gotReply = true;
            const r = page.reply(text);
            if (r.ok) {
                page.report = r; page.loaded = true; page.error = ""; page.readError = "";
            } else {
                page.report = ({}); page.loaded = false;
                page.readError = String(r.error || Tr.t("Reading the disk needs administrator access"));
                page.error = page.readError;
            }
            publish();
        } }
        stderr: StdioCollector { id: statusErr }
        onExited: code => {
            if (code !== 0 && !gotReply) {
                page.readError = String(statusErr.text.trim().split("\n").pop() || Tr.t("Reading the disk needs administrator access"));
                page.error = page.readError;
                page.loaded = false;
            }
            publish();
        }
    }

    Process {
        id: enrollProc; stdinEnabled: true; property string payload: ""; property bool gotReply: false
        stdout: StdioCollector { onStreamFinished: {
            enrollProc.gotReply = true;
            const r = page.reply(text);
            page.noteOk = !!r.ok;
            page.error = r.ok ? "" : String(r.error || Tr.t("Could not turn on automatic unlock"));
            page.note = r.ok ? Tr.t("Automatic unlock is on. Your passphrase still works.") : page.error;
            if (r.ok) page.read();
            publish();
        } }
        stderr: StdioCollector { id: enrollErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true; payload = "";
            if (code !== 0 && !gotReply) {
                page.noteOk = false;
                page.error = String(enrollErr.text.trim().split("\n").pop() || Tr.t("Could not turn on automatic unlock"));
                page.note = page.error;
            }
            publish();
        }
    }

    Process {
        id: removeProc; stdinEnabled: true; property string payload: ""; property bool gotReply: false
        stdout: StdioCollector { onStreamFinished: {
            removeProc.gotReply = true;
            const r = page.reply(text);
            page.noteOk = !!r.ok;
            page.error = r.ok ? "" : String(r.error || Tr.t("Could not turn off automatic unlock"));
            page.note = r.ok ? Tr.t("Automatic unlock is off. Type your passphrase at each boot.") : page.error;
            if (r.ok) page.read();
            publish();
        } }
        stderr: StdioCollector { id: removeErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            if (code !== 0 && !gotReply) {
                page.noteOk = false;
                page.error = String(removeErr.text.trim().split("\n").pop() || Tr.t("Could not turn off automatic unlock"));
                page.note = page.error;
            }
            publish();
        }
    }

    Process {
        id: recoveryProc; stdinEnabled: true; property string payload: ""; property bool gotReply: false
        stdout: StdioCollector { onStreamFinished: {
            recoveryProc.gotReply = true;
            const r = page.reply(text);
            if (r.ok && r.key) {
                page.shownKey = String(r.key);
                page.error = ""; page.noteOk = true;
                page.note = Tr.t("A new recovery key is ready. Write it down or save it now.");
            } else {
                page.noteOk = false;
                page.error = String(r.error || Tr.t("Could not make a recovery key"));
                page.note = page.error;
            }
            publish();
        } }
        stderr: StdioCollector { id: recoveryErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true; payload = "";
            if (code !== 0 && !gotReply) {
                page.noteOk = false;
                page.error = String(recoveryErr.text.trim().split("\n").pop() || Tr.t("Could not make a recovery key"));
                page.note = page.error;
            }
            publish();
        }
    }

    Process {
        id: headerProc; stdinEnabled: true; property string payload: ""; property bool gotReply: false
        stdout: StdioCollector { onStreamFinished: {
            headerProc.gotReply = true;
            const r = page.reply(text);
            page.noteOk = !!r.ok;
            page.error = r.ok ? "" : String(r.error || Tr.t("Could not save the disk header"));
            page.note = r.ok
                ? Tr.t("Header copy saved as %1", String(r.path || "").split("/").pop())
                : page.error;
            publish();
        } }
        stderr: StdioCollector { id: headerErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            if (code !== 0 && !gotReply) {
                page.noteOk = false;
                page.error = String(headerErr.text.trim().split("\n").pop() || Tr.t("Could not save the disk header"));
                page.note = page.error;
            }
            publish();
        }
    }

    Process {
        id: mokEnrollProc; stdinEnabled: true; property string payload: ""; property bool gotReply: false
        stdout: StdioCollector { onStreamFinished: {
            mokEnrollProc.gotReply = true;
            const r = page.reply(text);
            page.noteOk = !!r.ok;
            page.error = r.ok ? "" : String(r.error || Tr.t("Could not stage the signing key"));
            page.note = r.ok ? Tr.t("New signing key staged. Confirm it at the next boot.") : page.error;
            publish();
        } }
        stderr: StdioCollector { id: mokEnrollErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            if (code !== 0 && !gotReply) {
                page.noteOk = false;
                page.error = String(mokEnrollErr.text.trim().split("\n").pop() || Tr.t("Could not stage the signing key"));
                page.note = page.error;
            }
            publish();
        }
    }

    Process {
        id: mokCleanupProc; stdinEnabled: true; property string payload: ""; property bool gotReply: false
        stdout: StdioCollector { onStreamFinished: {
            mokCleanupProc.gotReply = true;
            const r = page.reply(text);
            page.noteOk = !!r.ok;
            page.error = r.ok ? "" : String(r.error || Tr.t("Could not remove old signing keys"));
            page.note = r.ok ? Tr.t("Old signing keys removed. Confirm it at the next boot.") : page.error;
            publish();
        } }
        stderr: StdioCollector { id: mokCleanupErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            if (code !== 0 && !gotReply) {
                page.noteOk = false;
                page.error = String(mokCleanupErr.text.trim().split("\n").pop() || Tr.t("Could not remove old signing keys"));
                page.note = page.error;
            }
            publish();
        }
    }

    Process {
        id: saveKeyProc; stdinEnabled: true; property string payload: ""
        stderr: StdioCollector { id: saveKeyErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true; payload = "";
            page.noteOk = code === 0;
            page.note = code === 0 ? Tr.t("Recovery key saved") : Tr.t("Could not save the recovery key");
            if (code !== 0) page.error = String(saveKeyErr.text.trim().split("\n").pop() || page.note);
            publish();
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Encryption and boot")
        hint: Tr.t("At a glance — what the disk and the boot setup report right now.")

        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            Button { text: page.loaded ? Tr.t("Read again") : Tr.t("Read state"); enabled: !page.busy; busy: page.busy; onClicked: page.read() }
            Item { Layout.fillWidth: true }
        }
        BusyNote { Layout.fillWidth: true; visible: page.busy; note: Tr.t("Working…"); iconSize: Theme.px(16) }
        ColumnLayout {
            Layout.fillWidth: true; visible: page.loaded && !page.busy; spacing: Theme.px(8)
            Repeater {
                model: page.facts()
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: Theme.px(2)
                    ListRow {
                        Layout.fillWidth: true
                        icon: modelData.icon; title: modelData.title; subtitle: modelData.value; interactive: false
                    }
                    Text {
                        Layout.fillWidth: true; Layout.leftMargin: Theme.px(36)
                        text: modelData.meaning; color: Theme.dim; wrapMode: Text.Wrap
                        font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                        Accessible.name: text
                    }
                }
            }
        }
        EmptyState {
            Layout.fillWidth: true; visible: !page.loaded && !page.busy && page.readError === ""
            icon: "drive-harddisk"; title: Tr.t("Nothing read yet")
            subtitle: Tr.t("Read the disk to see whether it is encrypted and how it unlocks at boot.")
        }
        InfoBanner {
            Layout.fillWidth: true; visible: page.readError !== ""; tone: "error"
            title: Tr.t("Reading the disk needs administrator access")
            text: page.readError + " " + Tr.t("A password may be asked so the disk state can be read.")
            Button { text: Tr.t("Read again"); onClicked: page.read() }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Automatic unlock")
        hint: Tr.t("This computer can unlock the disk itself. It works on this computer only; your passphrase always works too.")

        InfoBanner {
            Layout.fillWidth: true; visible: page.loaded && !page.canAuto; tone: "warn"
            title: Tr.t("Automatic unlock is not available here")
            text: Tr.t("Encryption is chosen when the computer is set up. Automatic unlock needs a TPM chip — check the firmware settings for it.")
        }

        ColumnLayout {
            Layout.fillWidth: true; visible: page.canAuto; spacing: Theme.px(8)
            Picks {
                label: Tr.t("Extra check at boot")
                current: page.usePin
                enabled: page.canAuto && !page.busy
                options: [
                    { label: Tr.t("No PIN"), value: false },
                    { label: Tr.t("Ask for a PIN"), value: true }
                ]
                onPicked: v => { page.usePin = v; pin1.text = ""; pin2.text = ""; publish(); }
            }
            TextField {
                id: diskPass; Layout.fillWidth: true; secret: true
                label: Tr.t("Disk passphrase"); placeholder: Tr.t("Disk passphrase")
                enabled: page.canAuto && !page.busy
                onAccepted: if (turnOnConfirm.enabled) turnOnConfirm.trigger()
            }
            ColumnLayout {
                Layout.fillWidth: true; visible: page.usePin; spacing: Theme.px(6)
                TextField {
                    id: pin1; Layout.fillWidth: true; secret: true
                    label: Tr.t("PIN"); placeholder: Tr.t("PIN")
                    enabled: page.canAuto && !page.busy
                }
                TextField {
                    id: pin2; Layout.fillWidth: true; secret: true
                    label: Tr.t("Repeat PIN"); placeholder: Tr.t("Repeat PIN")
                    error: pin2.text !== "" && pin2.text !== pin1.text ? Tr.t("The PINs do not match") : ""
                    enabled: page.canAuto && !page.busy
                    onAccepted: if (turnOnConfirm.enabled) turnOnConfirm.trigger()
                }
            }
            Text {
                Layout.fillWidth: true; color: Theme.dim; wrapMode: Text.Wrap
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                text: page.tpmEnrolled
                    ? Tr.t("Turning this off means you type your passphrase at each boot. Nothing on the disk is deleted.")
                    : Tr.t("This stores your passphrase so the computer can unlock the disk by itself. It needs administrator access; a password may be asked.")
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.px(6)
                ConfirmButton {
                    id: turnOnConfirm
                    visible: page.canAuto && !page.tpmEnrolled
                    implicitWidth: Theme.px(220); implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                    enabled: !page.busy && diskPass.text.trim() !== ""
                        && (!page.usePin || (pin1.text.trim() !== "" && pin1.text === pin2.text))
                    text: Tr.t("Turn on automatic unlock"); armedText: Tr.t("Tap again to turn on automatic unlock")
                    kind: "primary"; Accessible.name: text
                    onConfirmed: page.act("enroll-on")
                }
                ConfirmButton {
                    id: turnOffConfirm
                    visible: page.canAuto && page.tpmEnrolled
                    implicitWidth: Theme.px(220); implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                    enabled: !page.busy
                    text: Tr.t("Turn off automatic unlock"); armedText: Tr.t("Tap again to turn off automatic unlock")
                    kind: "danger"; Accessible.name: text
                    onConfirmed: page.act("enroll-off")
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("If you lose access")
        hint: Tr.t("Keep a way back if you forget the passphrase. A recovery key opens the disk without it.")

        TextField {
            id: keyPass; Layout.fillWidth: true; secret: true; visible: page.loaded
            label: Tr.t("Disk passphrase"); placeholder: Tr.t("Disk passphrase")
            enabled: page.loaded && !page.busy
        }
        Text {
            Layout.fillWidth: true; color: Theme.dim; wrapMode: Text.Wrap
            font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            text: Tr.t("A new key makes older recovery keys stop working. Write it down or save it to a file you pick — it is shown only now.")
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            ConfirmButton {
                id: keyConfirm
                implicitWidth: Theme.px(200); implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                enabled: page.loaded && !page.busy && keyPass.text.trim() !== ""
                text: Tr.t("Make a recovery key"); armedText: Tr.t("Tap again to make a recovery key")
                Accessible.name: text
                onConfirmed: page.act("recovery-key")
            }
            Item { Layout.fillWidth: true }
        }

        ColumnLayout {
            Layout.fillWidth: true; visible: page.shownKey !== ""; spacing: Theme.px(8)
            InfoBanner {
                Layout.fillWidth: true; tone: "warn"; title: Tr.t("Save this now")
                text: Tr.t("Write this down or save it to a file you pick — it is shown only now.")
            }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: Theme.px(90)
                radius: Theme.radiusSmall; color: Theme.surface1; border.width: 1; border.color: Theme.stroke
                TextEdit {
                    id: keyText; anchors.fill: parent; anchors.margins: Theme.px(10)
                    readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                    text: page.shownKey; color: Theme.text
                    font.family: Theme.mono; font.pixelSize: Theme.px(12) * Theme.fontScale
                    Accessible.name: Tr.t("Recovery key")
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.px(6)
                Button { text: Tr.t("Copy key"); onClicked: page.copyKey() }
                Button { text: Tr.t("Save to a file…"); onClicked: page.openKeyPicker() }
                Button { text: Tr.t("Hide key"); onClicked: page.clearKey() }
                Item { Layout.fillWidth: true }
            }
        }

        Text {
            Layout.fillWidth: true; color: Theme.dim; wrapMode: Text.Wrap
            font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            text: Tr.t("A copy of the disk header lets an expert help if the disk will not open. Keep that copy off this disk.")
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.px(6)
            Button { text: Tr.t("Save a copy of the disk header…"); enabled: page.loaded && !page.busy; onClicked: page.act("header-backup") }
            Item { Layout.fillWidth: true }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Secure Boot")
        hint: Tr.t("Secure Boot checks the boot files before the system starts.")

        InfoBanner {
            Layout.fillWidth: true; visible: !page.loaded; tone: "info"
            title: Tr.t("Secure Boot state is not known")
            text: Tr.t("Read the state first to see whether a signing key step is needed.")
        }
        InfoBanner {
            Layout.fillWidth: true; visible: page.loaded && !page.secureBoot; tone: "warn"
            title: Tr.t("Secure Boot is off")
            text: Tr.t("There is no signing key step to take. Turn it on in firmware settings first.")
        }
        ColumnLayout {
            Layout.fillWidth: true; visible: page.loaded && page.secureBoot; spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true; color: Theme.dim; wrapMode: Text.Wrap
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                text: Tr.t("Stage a new signing key when you start using one. Remove old keys once the new one is confirmed.")
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.px(6)
                ConfirmButton {
                    id: mokEnrollConfirm
                    implicitWidth: Theme.px(220); implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                    enabled: !page.busy
                    text: Tr.t("Stage a new signing key"); armedText: Tr.t("Tap again to stage a new signing key")
                    kind: "primary"; Accessible.name: text
                    onConfirmed: page.act("enroll-mok")
                }
                ConfirmButton {
                    id: mokCleanupConfirm
                    implicitWidth: Theme.px(220); implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                    enabled: !page.busy
                    text: Tr.t("Remove old signing keys"); armedText: Tr.t("Tap again to remove old signing keys")
                    kind: "danger"; Accessible.name: text
                    onConfirmed: page.act("cleanup-mok")
                }
                Item { Layout.fillWidth: true }
            }
            InfoBanner {
                Layout.fillWidth: true; tone: "info"
                text: Tr.t("The next boot must be confirmed in the firmware prompt.")
            }
        }
    }

    InfoBanner {
        Layout.fillWidth: true; visible: page.note !== ""; tone: page.noteOk ? "ok" : "error"
        text: page.note
    }
}
