// Settings > Your account: the picture (~/.face — the lock screen's — and
// AccountsService's, which the login screen reads, when it is installed), the
// name others see, and the password. Names and pictures go through
// AccountsService (no password asked for your own account); without it, and
// for the password always, `chfn` / `passwd` run in a terminal, where they ask.
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
    readonly property string home: Quickshell.env("HOME") || ""
    property string realName: ""
    property bool accounts: false         // AccountsService on the system bus
    property string accountPath: ""
    property var pictures: []
    property string note: ""
    property bool sshAddOpen: false

    function refresh() {
        who.running = true;
        pics.running = true;
        fingers.running = true;
        u2fProbe.running = true;
        cfgRead.running = true;
        SshKeys.refresh();
    }

    // ---- a security key (pam-u2f): registered in ~/.config/Yubico/u2f_keys, as the person ----
    // Shown when a key is plugged in or one is already registered (bridge/u2f.py).
    readonly property string u2fTool: ToolPath.of(Quickshell.env("SHANI_U2F_TOOL"), "u2f.py")
    property var u2f: ({ key: false, keys: [], registered: 0 })
    readonly property bool u2fShown: u2f.key || u2f.registered > 0
    property string u2fState: ""            // "", "touch", "done", "failed: …"
    Process {
        id: u2fProbe
        command: ["python3", page.u2fTool, "probe"]
        stdout: StdioCollector { onStreamFinished: { try { page.u2f = JSON.parse(text); Ui.u2fRegistered = page.u2f.registered; } catch (e) {} } }
    }
    Process {
        id: u2fRun
        stdout: SplitParser { onRead: line => page.u2fState = line }
        onExited: u2fProbe.running = true
    }
    function u2fDo(cmd) { u2fState = ""; u2fRun.command = ["python3", page.u2fTool, cmd]; u2fRun.running = true; }
    // a key plugged in or out while the page is open
    Connections { target: Plugged; function onKeyRevChanged() { if (page.active) u2fProbe.running = true; } }

    // ---- FIDO2 and one-time-password settings: read and change them here ----
    // config returns stable keys and codes; all words are chosen in this page.
    // The bridge runs the administrator step itself, so this page only sends
    // JSON on stdin and never puts a setting or a confirmation in argv.
    property var u2fConfig: ({ fido2: ({}), yubico: ({}), registered: 0, ykman: ({}) })
    property bool cfgLoaded: false
    property string cfgReadError: ""
    property string cfgNote: ""
    property bool cfgNoteOk: true
    property string cfgNeedsConfirm: ""
    property string cfgConfirmTarget: ""     // "fido2" | "yubico"
    property string cfgConfirmFlag: ""       // "alwaysok" | "nouserok", while asking
    property string cfgConfirmText: ""
    property bool fidoCustomAuthfile: false
    property bool yubicoCustomAuthfile: false
    property bool yubicoCustomPath: false
    readonly property string ownAuthfile: page.home + "/.config/Yubico/u2f_keys"
    readonly property var onOffOptions: [
        { label: Tr.t("Off"), value: false },
        { label: Tr.t("On"), value: true }
    ]
    readonly property var chalrespOptions: [
        { label: Tr.t("YubiKey device"), value: "/dev/yubikey" },
        { label: Tr.t("USB device one"), value: "/dev/hidraw0" },
        { label: Tr.t("USB device two"), value: "/dev/hidraw1" },
        { label: Tr.t("Another path…"), value: "__custom" }
    ]
    readonly property bool cfgBusy: cfgRead.running || cfgWrite.running

    function cfgValue(target, key) {
        const t = page.u2fConfig[target];
        const v = t && t.values ? t.values[key] : undefined;
        return v === undefined || v === null ? "" : String(v);
    }
    function cfgFlag(target, flag) {
        const t = page.u2fConfig[target];
        return !!(t && Array.isArray(t.flags) && t.flags.indexOf(flag) >= 0);
    }
    function flagWord(flag) {
        return flag === "alwaysok" ? Tr.t("always allow")
             : flag === "nouserok" ? Tr.t("allow without a key")
             : flag === "debug" ? Tr.t("extra logging")
             : flag;
    }
    function fidoFacts() {
        const f = page.u2fConfig.fido2 || {};
        const v = f.values || {};
        const flags = f.flags || [];
        return [
            { icon: "auth-smartcard", title: Tr.t("Keys registered"), value: String(page.u2fConfig.registered || 0) },
            { icon: "dialog-ok", title: Tr.t("FIDO2 sign-in"), value: f.available ? Tr.t("Available") : Tr.t("Not set up") },
            { icon: "dialog-password", title: Tr.t("Key file"), value: v.authfile || Tr.t("Not set") },
            { icon: "folder", title: Tr.t("Key file entries"), value: String(f.authfileCount || 0) },
            { icon: "web-browser", title: Tr.t("Origin"), value: v.origin || Tr.t("Not set") },
            { icon: "application-x-executable", title: Tr.t("Application ID"), value: v.appid || Tr.t("Not set") },
            { icon: "preferences-system", title: Tr.t("Options on"), value: flags.length ? flags.map(x => page.flagWord(x)).join(", ") : Tr.t("None") },
            { icon: "folder", title: Tr.t("Settings file"), value: f.path || "" }
        ].filter(row => row.value !== "");
    }
    function yubicoFacts() {
        const y = page.u2fConfig.yubico || {};
        const v = y.values || {};
        const flags = y.flags || [];
        const yk = page.u2fConfig.ykman || {};
        return [
            { icon: "dialog-ok", title: Tr.t("One-time-password sign-in"), value: y.available ? Tr.t("Available") : Tr.t("Not set up") },
            { icon: "preferences-system", title: Tr.t("Mode"), value: y.mode || v.mode || Tr.t("Not set") },
            { icon: "dialog-password", title: Tr.t("Identity"), value: v.id || Tr.t("Not set") },
            { icon: "drive-harddisk", title: Tr.t("Challenge-response file"), value: v.chalresp_path || Tr.t("Not set") },
            { icon: "preferences-system", title: Tr.t("Options on"), value: flags.length ? flags.map(x => page.flagWord(x)).join(", ") : Tr.t("None") },
            { icon: "application-x-executable", title: Tr.t("Key manager"), value: yk.available ? (yk.version || Tr.t("Available")) : Tr.t("Not installed") },
            { icon: "folder", title: Tr.t("Settings file"), value: y.path || "" }
        ].filter(row => row.value !== "");
    }
    function syncCfgFields() {
        const fa = page.cfgValue("fido2", "authfile");
        const ya = page.cfgValue("yubico", "authfile");
        const cp = page.cfgValue("yubico", "chalresp_path");
        page.fidoCustomAuthfile = fa !== "" && fa !== page.ownAuthfile;
        page.yubicoCustomAuthfile = ya !== "" && ya !== page.ownAuthfile;
        page.yubicoCustomPath = cp !== "" && ["/dev/yubikey", "/dev/hidraw0", "/dev/hidraw1"].indexOf(cp) < 0;
        fidoOrigin.text = page.cfgValue("fido2", "origin");
        fidoAppid.text = page.cfgValue("fido2", "appid");
        fidoAuthfileCustom.text = fa;
        yubicoId.text = page.cfgValue("yubico", "id");
        yubicoAuthfileCustom.text = ya;
        yubicoPathCustom.text = cp;
    }
    function writeConfig(target, settings, confirm) {
        page.cfgNote = "";
        page.cfgNoteOk = true;
        page.cfgNeedsConfirm = "";
        cfgWrite.reply = ({});
        cfgWrite.target = target;
        cfgWrite.payload = JSON.stringify({ target: target, settings: settings, confirm: confirm || "" });
        cfgWrite.command = ["python3", page.u2fTool, "config-set"];
        cfgWrite.running = true;
    }
    function flagObject(flag, on) {
        const o = {};
        o[flag] = on;
        return o;
    }
    function setFlag(target, flag, on) {
        if (page.cfgFlag(target, flag) === on) return;
        if (on) {
            page.cfgConfirmTarget = target;
            page.cfgConfirmFlag = flag;
            page.cfgConfirmText = "";
            page.cfgNeedsConfirm = "";
            cfgConfirmInput.text = "";
        } else {
            page.writeConfig(target, page.flagObject(flag, false), "");
        }
    }
    function cfgCanConfirm() {
        return page.cfgConfirmFlag !== "" && page.cfgConfirmText === page.cfgConfirmFlag;
    }
    function cfgApplyConfirm() {
        if (!page.cfgCanConfirm()) return;
        const target = page.cfgConfirmTarget;
        const flag = page.cfgConfirmFlag;
        const typed = page.cfgConfirmText;
        page.cfgConfirmTarget = "";
        page.cfgConfirmFlag = "";
        page.cfgConfirmText = "";
        cfgConfirmInput.text = "";
        page.writeConfig(target, page.flagObject(flag, true), typed);
    }
    function cfgCancelConfirm() {
        page.cfgConfirmTarget = "";
        page.cfgConfirmFlag = "";
        page.cfgConfirmText = "";
        cfgConfirmInput.text = "";
    }
    Process {
        id: cfgRead
        command: ["python3", page.u2fTool, "config"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) {}
                if (r.fido2 && r.yubico) {
                    page.u2fConfig = r;
                    page.cfgLoaded = true;
                    page.cfgReadError = "";
                    page.syncCfgFields();
                } else {
                    page.cfgLoaded = false;
                    page.cfgReadError = Tr.t("Could not read sign-in key settings.");
                }
            }
        }
    }
    Process {
        id: cfgWrite
        stdinEnabled: true
        property string payload: ""
        property string target: ""
        property var reply: ({})
        stdout: StdioCollector {
            onStreamFinished: {
                try { cfgWrite.reply = JSON.parse(text); } catch (e) { cfgWrite.reply = ({}); }
            }
        }
        stderr: StdioCollector { id: cfgWriteErr }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            const r = cfgWrite.reply || {};
            const label = cfgWrite.target === "fido2" ? Tr.t("FIDO2") : Tr.t("One-time-password");
            if (code === 0 && r.ok === true) {
                page.cfgNoteOk = true;
                page.cfgNote = Tr.t("%1 settings saved.", label);
                page.cfgNeedsConfirm = "";
                page.cfgCancelConfirm();
                if (r.config && r.config.fido2) page.u2fConfig = r.config;
                cfgRead.running = true;   // a new read after the privileged write
            } else {
                page.cfgNoteOk = false;
                page.cfgNote = String(r.error || cfgWriteErr.text.trim().split("\n").pop() || Tr.t("Could not save sign-in key settings."));
                page.cfgNeedsConfirm = r.needsConfirm ? String(r.needsConfirm) : "";
            }
        }
    }

    // ---- fingerprints (fprintd): what is enrolled, enrolling one, removing them ----
    property bool hasReader: false
    property var enrolled: []
    property string enrollState: ""        // "", "touch", "again", "done", "failed: …"
    property int stages: 0
    Process {
        id: fingers
        command: ["sh", "-c", 'command -v fprintd-list >/dev/null && fprintd-list "$1" 2>&1', "sh", page.user]
        stdout: StdioCollector {
            onStreamFinished: {
                page.hasReader = text.indexOf("Device at") >= 0;
                page.enrolled = (text.match(/#\d+:\s*(\S+)/g) || []).map(x => x.replace(/#\d+:\s*/, ""));
            }
        }
    }
    Process {
        id: enroll
        command: ["fprintd-enroll", "-f", page.finger]
        stdout: SplitParser {
            onRead: line => {
                if (/enroll-stage-passed/.test(line)) { page.stages++; page.enrollState = "again"; }
                else if (/enroll-retry|enroll-swipe-too-short|enroll-finger-not-centered|enroll-remove-and-retry/.test(line)) page.enrollState = "again";
                else if (/enroll-completed/.test(line)) page.enrollState = "done";
                else if (/enroll-(failed|data-full|disconnected|unknown-error)/.test(line)) page.enrollState = "failed: " + line.replace(/.*enroll-/, "");
            }
        }
        onExited: fingers.running = true
    }
    function startEnroll() { stages = 0; enrollState = "touch"; enroll.running = true; }
    // one finger (fprintd-delete -f), or all of them
    function forgetFinger(f) { forget.command = f ? ["fprintd-delete", "-f", f, page.user] : ["fprintd-delete", page.user]; forget.running = true; }
    Process { id: forget; onExited: fingers.running = true }
    // fprintd's ten names (EnrollStart refuses anything else); the picker offers those not saved yet
    readonly property var fingerNames: ["right-index-finger", "left-index-finger", "right-thumb", "left-thumb",
        "right-middle-finger", "left-middle-finger", "right-ring-finger", "left-ring-finger", "right-little-finger", "left-little-finger"]
    property string finger: "right-index-finger"
    readonly property var unsaved: fingerNames.filter(f => enrolled.indexOf(f) < 0)
    onUnsavedChanged: if (unsaved.indexOf(finger) < 0 && unsaved.length) finger = unsaved[0]
    function fingerLabel(f) { return Tr.t(f.replace(/-finger$/, "").replace(/-/g, " ").replace(/^./, c => c.toUpperCase())); }
    // fprintd's usual stage count; the bar is a guide, "done" comes from fprintd
    readonly property int stagesNeeded: 5

    // ---- face (linux-hello, an infrared camera): on, set up, improved, removed ----
    // Shown only on a computer with the camera. Turning it on or off and removing a
    // saved face need an administrator (pkexec); setting it up is the person's own.
    readonly property string faceTool: Quickshell.env("SHANI_FACE_TOOL") || "/usr/lib/shani-shell/face.py"
    property var face: ({ installed: false, camera: false, on: false, saved: false })
    property int faceStep: -1              // the look being taken, -1 when not setting up
    property int faceCount: 0              // seconds before the camera looks
    property string faceNote: ""
    readonly property var faceLooks: [
        { label: "center", tip: Tr.t("Look straight at the camera") },
        { label: "look_left", tip: Tr.t("Turn your head a little to the left") },
        { label: "look_right", tip: Tr.t("Now a little to the right") },
        { label: "look_up", tip: Tr.t("Tilt your chin up a little") },
        { label: "look_down", tip: Tr.t("And a little down") }]
    Process {
        id: faceProbe
        command: ["python3", page.faceTool, "probe"]
        stdout: StdioCollector { onStreamFinished: { try { page.face = JSON.parse(text); } catch (e) {} } }
    }
    function faceStart(steps) { faceNote = ""; faceSteps = steps; faceStep = 0; faceCount = 3; faceTick.restart(); }
    property var faceSteps: []
    Timer {
        id: faceTick
        interval: 1000
        repeat: true
        onTriggered: {
            if (--page.faceCount > 0)
                return;
            stop();
            faceShot.command = ["python3", page.faceTool, "enroll", page.faceSteps[page.faceStep].label];
            faceShot.running = true;
        }
    }
    Process {
        id: faceShot
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) {}
                if (!r.ok) {
                    page.faceNote = r.message ? Tr.t("The camera could not see you clearly (%1). Try again in good light.").arg(r.message)
                                              : Tr.t("The camera could not see you clearly. Try again in good light.");
                    page.faceStep = -1;
                    faceProbe.running = true;
                    return;
                }
                if (page.faceStep + 1 < page.faceSteps.length) {
                    page.faceStep++;
                    page.faceCount = 2;
                    faceTick.restart();
                } else {
                    page.faceStep = -1;
                    page.faceNote = Tr.t("Done. Look at the camera on the lock screen or the sign-in screen.");
                    faceProbe.running = true;
                }
            }
        }
    }
    Process { id: faceAdmin; onExited: faceProbe.running = true }
    function faceService(on) { faceAdmin.command = ["pkexec", "systemctl", on ? "enable" : "disable", "--now", "linux-hello.service"]; faceAdmin.running = true; }
    function faceForget() { faceAdmin.command = ["pkexec", "/usr/bin/linux-hello", "remove", page.user]; faceAdmin.running = true; }
    onActiveChanged: if (active) { refresh(); faceProbe.running = true; }
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) { refresh(); faceProbe.running = true; }

    Process {
        id: who
        command: ["sh", "-c", 'getent passwd "$1" | cut -d: -f5 | cut -d, -f1
            busctl call org.freedesktop.Accounts /org/freedesktop/Accounts org.freedesktop.Accounts FindUserByName s "$1" 2>/dev/null | cut -d" " -f2 | tr -d \\"', "sh", page.user]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                page.realName = (l[0] || "").trim();
                page.accountPath = (l[1] || "").trim();
                page.accounts = page.accountPath.startsWith("/");
            }
        }
    }
    // pictures to choose from: the system's faces, then the person's own
    Process {
        id: pics
        command: ["sh", "-c", 'find /usr/share/pixmaps/faces "$HOME/Pictures" -maxdepth 2 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \\) 2>/dev/null | grep -v "/Screenshots/" | head -24']
        stdout: StdioCollector { onStreamFinished: page.pictures = text.trim().split("\n").filter(x => x) }
    }
    Process {
        id: act
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            page.note = code === 0 ? "" : (actErr.text.trim().split("\n").pop() || "not changed");
            Ui.faceRev++;
            who.running = true;
        }
    }
    function setPicture(path) {
        // a square copy: the lock screen reads ~/.face; AccountsService keeps its own copy
        act.command = ["sh", "-c", 'cp -f "$1" "$HOME/.face" && chmod 644 "$HOME/.face" && { [ -z "$2" ] || busctl call org.freedesktop.Accounts "$2" org.freedesktop.Accounts.User SetIconFile s "$HOME/.face"; }',
                       "sh", path, page.accounts ? page.accountPath : ""];
        act.running = true;
    }
    function setName(name) {
        if (page.accounts) {
            act.command = ["busctl", "call", "org.freedesktop.Accounts", page.accountPath, "org.freedesktop.Accounts.User", "SetRealName", "s", name];
            act.running = true;
        } else {
            Ui.closeAll();
            Quickshell.execDetached([Settings.data.terminal, "-e", "sh", "-c", 'chfn -f "$1"; echo; read -p "Done — press Enter to close." x', "sh", name]);
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Your account")

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(14)
            Avatar { size: Theme.px(64) }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: page.realName || page.user; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(17) * Theme.fontScale; font.weight: Font.DemiBold }
                Text { text: page.user; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale }
            }
        }

        Text { text: Tr.t("Picture"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(8)
            Repeater {
                model: page.pictures
                Image {
                    required property string modelData
                    width: Theme.px(48)
                    height: Theme.px(48)
                    source: "file://" + modelData
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Use " + modelData.split("/").pop()
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.setPicture(parent.modelData) }
                    KeyFocus { onActivated: page.setPicture(parent.modelData) }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: page.pictures.length === 0
            text: Tr.t("Put a picture in Pictures to choose it here.")
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }

        TextField {
            Layout.fillWidth: true
            placeholder: "Your name, as others see it — " + (page.realName || page.user)
            onAccepted: {
                const n = text.trim();
                if (n !== "" && n.indexOf(":") < 0 && n.indexOf(",") < 0)
                    page.setName(n);
                text = "";
            }
        }
    }
    // ---- sign in faster: a finger or a look instead of the password -------------------
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Sign in faster")
        visible: page.hasReader || page.face.camera || page.u2fShown

        Text {
            Layout.fillWidth: true
            visible: page.hasReader || page.face.camera || page.u2fShown
            text: Tr.t("Unlock with your fingerprint or your face instead of typing your password - on the lock screen and the sign-in screen. Your password always works too, and is still asked for changes to the system.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
    // face
    RowLayout {
        visible: page.face.camera
        Layout.fillWidth: true
        Layout.topMargin: Theme.px(4)
        spacing: Theme.px(10)
        Icon { name: "camera-web"; size: Theme.px(22); color: page.face.saved ? Theme.accent : Theme.dim }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text { text: Tr.t("Face"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.Medium }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: page.faceStep >= 0 ? (page.faceCount > 0 ? page.faceSteps[page.faceStep].tip + " - " + page.faceCount : Tr.t("Hold still…"))
                    : !page.face.on ? Tr.t("Off. Turning it on asks for an administrator's password once.")
                    : page.face.saved ? Tr.t("On. Just look at the camera when the screen is locked.")
                    : Tr.t("On, but your face is not set up yet - it takes five quick looks.")
                color: page.faceStep >= 0 ? Theme.accent : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
        }
    }
    Rectangle {      // the looks so far
        visible: page.faceStep >= 0
        Layout.fillWidth: true
        implicitHeight: Theme.px(6)
        radius: Theme.px(3)
        color: Theme.hover
        Rectangle { width: parent.width * page.faceStep / Math.max(1, page.faceSteps.length); height: parent.height; radius: Theme.px(3); color: Theme.accent }
    }
    Flow {
        visible: page.face.camera && page.faceStep < 0
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Button { visible: !page.face.on; kind: "primary"; text: Tr.t("Turn on face sign-in"); onClicked: page.faceService(true) }
        Button { visible: page.face.on && !page.face.saved; kind: "primary"; text: Tr.t("Set up my face"); onClicked: page.faceStart(page.faceLooks) }
        Button { visible: page.face.on && page.face.saved; text: Tr.t("Add another look"); onClicked: page.faceStart([{ label: "extra_" + Date.now(), tip: Tr.t("With glasses, or in other light: look at the camera") }]) }
        Button { visible: page.face.on && page.face.saved; kind: "danger"; text: Tr.t("Remove my face"); onClicked: page.faceForget() }
        Button { visible: page.face.on; text: Tr.t("Turn off"); onClicked: page.faceService(false) }
    }
    Button { visible: page.faceStep >= 0; text: Tr.t("Cancel"); onClicked: { faceTick.stop(); page.faceStep = -1; } }
    Text {
        Layout.fillWidth: true
        visible: page.faceNote !== ""
        text: page.faceNote
        color: page.faceNote.indexOf("Done") === 0 ? Theme.dim : Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
    }
    // fingerprint
    RowLayout {
        visible: page.hasReader
        Layout.fillWidth: true
        Layout.topMargin: Theme.px(6)
        spacing: Theme.px(10)
        Icon { name: "auth-fingerprint"; size: Theme.px(22); color: page.enrolled.length ? Theme.accent : Theme.dim }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text { text: Tr.t("Fingerprint"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.Medium }
            Text {
                visible: page.enrolled.length > 0 && page.enrollState === ""
                text: Tr.t("On the sign-in screen, press Enter with the password empty, then touch the reader.")
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.hasReader
        text: page.enrollState === "touch" ? Tr.t("Touch the reader with your %1.", page.fingerLabel(page.finger).toLowerCase())
            : page.enrollState === "again" ? Tr.t("Lift it and touch again — %1 done.", page.stages)
            : page.enrollState === "done" ? Tr.t("Saved. Touch the reader on the lock screen to unlock.")
            : page.enrollState.startsWith("failed") ? Tr.t("That did not work (%1). Try again.", page.enrollState.slice(8))
            : page.enrolled.length ? "" : Tr.t("No fingerprint saved.")
        color: page.enrollState.startsWith("failed") ? Theme.danger : Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
    }
    Rectangle {      // the scans so far
        visible: enroll.running
        Layout.fillWidth: true
        implicitHeight: Theme.px(6)
        radius: Theme.px(3)
        color: Theme.hover
        Rectangle { width: parent.width * Math.min(1, page.stages / page.stagesNeeded); height: parent.height; radius: Theme.px(3); color: Theme.accent }
    }
    // saved fingers, each removable
    Repeater {
        model: page.hasReader ? page.enrolled : []
        RowLayout {
            required property string modelData
            Layout.fillWidth: true
            Icon { name: "auth-fingerprint"; size: Theme.px(18); color: Theme.accent }
            Text { Layout.fillWidth: true; text: page.fingerLabel(modelData); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
            IconButton { icon: "edit-delete"; tip: Tr.t("Remove"); Accessible.name: Tr.t("Remove %1", page.fingerLabel(modelData)); onClicked: page.forgetFinger(modelData) }
        }
    }
    Flow {
        visible: page.hasReader && !enroll.running && page.unsaved.length > 0
        Layout.fillWidth: true
        spacing: Theme.px(4)
        Repeater {
            model: page.unsaved
            Choice { required property string modelData; text: page.fingerLabel(modelData); selected: page.finger === modelData; onClicked: page.finger = modelData }
        }
    }
    RowLayout {
        visible: page.hasReader
        spacing: Theme.px(6)
        Button { text: enroll.running ? Tr.t("Enrolling…") : Tr.t("Add %1", page.fingerLabel(page.finger).toLowerCase()); enabled: !enroll.running && page.unsaved.length > 0; onClicked: page.startEnroll() }
        Button { visible: enroll.running; text: Tr.t("Cancel"); onClicked: enroll.running = false }
        Button { visible: page.enrolled.length > 1 && !enroll.running; kind: "danger"; text: Tr.t("Remove all"); onClicked: page.forgetFinger("") }
    }

    // security key
    RowLayout {
        visible: page.u2fShown
        Layout.fillWidth: true
        Layout.topMargin: Theme.px(6)
        spacing: Theme.px(10)
        Icon { name: "auth-smartcard"; size: Theme.px(22); color: page.u2f.registered > 0 ? Theme.accent : Theme.dim }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text { text: Tr.t("Security key"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.Medium }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: page.u2fState === "touch" ? Tr.t("Touch your key now - its light is blinking.")
                    : page.u2fState === "done" ? Tr.t("Saved. Touch the key on the lock screen or the sign-in screen.")
                    : page.u2fState.indexOf("failed") === 0 ? Tr.t("That did not work (%1). Try again.", page.u2fState.slice(8))
                    : page.u2f.registered > 1 ? Tr.t("%1 keys can sign you in. Plug one in and touch it on the lock screen.", page.u2f.registered)
                    : page.u2f.registered === 1 ? Tr.t("Your key can sign you in. Plug it in and touch it on the lock screen.")
                    : Tr.t("%1 is plugged in. Register it, then touch it to sign in.", page.u2f.keys[0] || Tr.t("A key"))
                color: page.u2fState.indexOf("failed") === 0 ? Theme.danger : page.u2fState === "touch" ? Theme.accent : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
        }
    }
    Flow {
        visible: page.u2fShown && !u2fRun.running
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Button { visible: page.u2f.key; kind: "primary"; text: page.u2f.registered > 0 ? Tr.t("Register another key") : Tr.t("Register this key"); onClicked: page.u2fDo("register") }
        Button { visible: page.u2f.registered > 0; kind: "danger"; text: Tr.t("Remove my keys"); onClicked: page.u2fDo("remove") }
    }
    }

    // ---- the sign-in modules themselves: how each key is checked -----------
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Sign-in with a key")
        hint: Tr.t("How this system checks a security key when you sign in. Saving a change may ask for an administrator's password.")

        BusyNote {
            Layout.fillWidth: true
            visible: page.cfgBusy
            note: Tr.t("Working with key settings…")
            iconSize: Theme.px(16)
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.cfgReadError !== ""
            tone: "warn"
            text: page.cfgReadError
            Button { flat: true; text: Tr.t("Try again"); onClicked: cfgRead.running = true }
        }

        // FIDO2: current state, then each value and flag the person may change
        Text {
            Layout.fillWidth: true
            text: Tr.t("FIDO2")
            color: Theme.text
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(13) * Theme.fontScale
            font.weight: Font.Medium
            Accessible.name: text
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: page.cfgLoaded && !page.cfgBusy
            spacing: Theme.px(2)
            Repeater {
                model: page.fidoFacts()
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: modelData.icon
                    title: modelData.title
                    subtitle: modelData.value
                    interactive: false
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: page.cfgLoaded && !page.cfgBusy
            spacing: Theme.px(8)
            Picks {
                label: Tr.t("Key file")
                options: [
                    { label: Tr.t("This account's key file"), value: page.ownAuthfile },
                    { label: Tr.t("Another file…"), value: "__custom" }
                ]
                current: page.cfgValue("fido2", "authfile")
                onPicked: v => {
                    if (v === "__custom") page.fidoCustomAuthfile = true;
                    else { page.fidoCustomAuthfile = false; page.writeConfig("fido2", { authfile: v }, ""); }
                }
            }
            TextField {
                id: fidoAuthfileCustom
                visible: page.fidoCustomAuthfile
                Layout.fillWidth: true
                label: Tr.t("Key file path")
                placeholder: Tr.t("Path to a key file")
                onAccepted: if (text.trim()) page.writeConfig("fido2", { authfile: text.trim() }, "")
                Accessible.name: Tr.t("Key file path")
            }
            TextField {
                id: fidoOrigin
                Layout.fillWidth: true
                label: Tr.t("Origin")
                placeholder: Tr.t("Address the key is bound to")
                onAccepted: if (text.trim()) page.writeConfig("fido2", { origin: text.trim() }, "")
                Accessible.name: Tr.t("Origin")
            }
            TextField {
                id: fidoAppid
                Layout.fillWidth: true
                label: Tr.t("Application ID")
                placeholder: Tr.t("Application ID the key is bound to")
                onAccepted: if (text.trim()) page.writeConfig("fido2", { appid: text.trim() }, "")
                Accessible.name: Tr.t("Application ID")
            }
            Picks {
                label: Tr.t("Always allow")
                options: page.onOffOptions
                current: page.cfgFlag("fido2", "alwaysok")
                onPicked: v => page.setFlag("fido2", "alwaysok", v)
            }
            Picks {
                label: Tr.t("Allow without a key")
                options: page.onOffOptions
                current: page.cfgFlag("fido2", "nouserok")
                onPicked: v => page.setFlag("fido2", "nouserok", v)
            }
            Picks {
                label: Tr.t("Extra logging")
                options: page.onOffOptions
                current: page.cfgFlag("fido2", "debug")
                onPicked: v => {
                    if (page.cfgFlag("fido2", "debug") !== v) page.writeConfig("fido2", { debug: v }, "");
                }
            }
        }

        // Yubico OTP: the same shape, with a mode and a two-step path
        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.px(8)
            text: Tr.t("One-time-password key")
            color: Theme.text
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(13) * Theme.fontScale
            font.weight: Font.Medium
            Accessible.name: text
        }
        Text {
            Layout.fillWidth: true
            text: Tr.t("The one-time password value itself is never shown.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
            Accessible.name: text
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: page.cfgLoaded && !page.cfgBusy
            spacing: Theme.px(2)
            Repeater {
                model: page.yubicoFacts()
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: modelData.icon
                    title: modelData.title
                    subtitle: modelData.value
                    interactive: false
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: page.cfgLoaded && !page.cfgBusy
            spacing: Theme.px(8)
            Picks {
                label: Tr.t("Mode")
                options: [
                    { label: Tr.t("Client"), value: "client" },
                    { label: Tr.t("Challenge-response"), value: "challenge-response" }
                ]
                current: page.cfgValue("yubico", "mode")
                onPicked: v => page.writeConfig("yubico", { mode: v }, "")
            }
            TextField {
                id: yubicoId
                Layout.fillWidth: true
                label: Tr.t("Identity")
                placeholder: Tr.t("Identity used to match the key")
                onAccepted: if (text.trim()) page.writeConfig("yubico", { id: text.trim() }, "")
                Accessible.name: Tr.t("Identity")
            }
            Picks {
                label: Tr.t("Challenge-response file")
                options: page.chalrespOptions
                current: page.cfgValue("yubico", "chalresp_path")
                onPicked: v => {
                    if (v === "__custom") page.yubicoCustomPath = true;
                    else { page.yubicoCustomPath = false; page.writeConfig("yubico", { chalresp_path: v }, ""); }
                }
            }
            TextField {
                id: yubicoPathCustom
                visible: page.yubicoCustomPath
                Layout.fillWidth: true
                label: Tr.t("Challenge-response path")
                placeholder: Tr.t("Path used for challenge-response")
                onAccepted: if (text.trim()) page.writeConfig("yubico", { chalresp_path: text.trim() }, "")
                Accessible.name: Tr.t("Challenge-response path")
            }
            Picks {
                label: Tr.t("Key file")
                options: [
                    { label: Tr.t("This account's key file"), value: page.ownAuthfile },
                    { label: Tr.t("Another file…"), value: "__custom" }
                ]
                current: page.cfgValue("yubico", "authfile")
                onPicked: v => {
                    if (v === "__custom") page.yubicoCustomAuthfile = true;
                    else { page.yubicoCustomAuthfile = false; page.writeConfig("yubico", { authfile: v }, ""); }
                }
            }
            TextField {
                id: yubicoAuthfileCustom
                visible: page.yubicoCustomAuthfile
                Layout.fillWidth: true
                label: Tr.t("Key file path")
                placeholder: Tr.t("Path to a key file")
                onAccepted: if (text.trim()) page.writeConfig("yubico", { authfile: text.trim() }, "")
                Accessible.name: Tr.t("Key file path")
            }
            Picks {
                label: Tr.t("Always allow")
                options: page.onOffOptions
                current: page.cfgFlag("yubico", "alwaysok")
                onPicked: v => page.setFlag("yubico", "alwaysok", v)
            }
        }

        // one shared confirmation row for every guarded flag
        ColumnLayout {
            Layout.fillWidth: true
            visible: page.cfgConfirmFlag !== ""
            spacing: Theme.px(6)
            Text {
                Layout.fillWidth: true
                text: Tr.t("Turning this on changes how sign-in checks your key. Type %1 to confirm.", page.cfgConfirmFlag)
                color: Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.name: text
            }
            TextField {
                id: cfgConfirmInput
                Layout.fillWidth: true
                label: Tr.t("Type %1 to confirm", page.cfgConfirmFlag)
                placeholder: Tr.t("Type %1 to confirm", page.cfgConfirmFlag)
                onTextChanged: page.cfgConfirmText = text
                onAccepted: if (page.cfgCanConfirm()) page.cfgApplyConfirm()
                Accessible.name: Tr.t("Type %1 to confirm", page.cfgConfirmFlag)
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Item { Layout.fillWidth: true }
                Button { flat: true; text: Tr.t("Cancel"); onClicked: page.cfgCancelConfirm() }
                Button {
                    kind: "primary"
                    text: Tr.t("Turn on")
                    enabled: page.cfgCanConfirm() && !page.cfgBusy
                    onClicked: page.cfgApplyConfirm()
                    Accessible.name: Tr.t("Confirm turning on %1", page.cfgConfirmFlag)
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: page.cfgNeedsConfirm !== ""
            text: Tr.t("Type %1 to confirm this change.", page.cfgNeedsConfirm)
            color: Theme.amber
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
            Accessible.name: text
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: page.cfgNote !== ""
            tone: page.cfgNoteOk ? "ok" : "error"
            text: page.cfgNote
        }
    }

    // ---- SSH keys: what can sign in to this machine over SSH ----------------
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("SSH keys")

        Text {
            Layout.fillWidth: true
            text: Tr.t("Keys that can sign in to this account over SSH. A public key is not a secret; a private key never belongs here.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        Text {
            Layout.fillWidth: true
            visible: SshKeys.note !== ""
            text: SshKeys.note
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        Text {
            Layout.fillWidth: true
            visible: SshKeys.error !== ""
            text: SshKeys.error
            color: Theme.danger
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.px(2)
            Repeater {
                model: SshKeys.keys
                SettingRow {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    interactive: false
                    icon: "dialog-password"
                    title: modelData.comment || modelData.type || Tr.t("SSH key")
                    subtitle: [modelData.fingerprint, modelData.type].filter(x => x).join("  ·  ")
                    control: Button {
                        text: Tr.t("Remove")
                        kind: "danger"
                        flat: true
                        enabled: SshKeys.editable && !SshKeys.busy
                        onClicked: SshKeys.remove(index)
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: SshKeys.keys.length === 0
            text: Tr.t("No SSH keys yet.")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        RowLayout {
            Layout.fillWidth: true
            visible: !page.sshAddOpen
            spacing: Theme.px(6)
            Button { text: Tr.t("Add a key…"); enabled: SshKeys.editable && !SshKeys.busy; onClicked: { page.sshAddOpen = true; } }
            Item { Layout.fillWidth: true }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: page.sshAddOpen
            spacing: Theme.px(6)
            TextField {
                id: sshInput
                Layout.fillWidth: true
                placeholder: Tr.t("ssh-ed25519 AAAA… comment")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Item { Layout.fillWidth: true }
                Button { flat: true; text: Tr.t("Cancel"); onClicked: { page.sshAddOpen = false; sshInput.text = ""; } }
                Button { kind: "primary"; text: Tr.t("Add"); enabled: sshInput.text.trim() !== "" && !SshKeys.busy; onClicked: { SshKeys.add(sshInput.text.trim()); page.sshAddOpen = false; sshInput.text = ""; } }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: Tr.t("Your sign-in password may also unlock the keyring that keeps saved passwords. Changing it here does not change the keyring: if apps stop remembering secrets, open Passwords and Keys and change the keyring password to match.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    Button {
        text: Tr.t("Change password…")
        onClicked: {
            Ui.closeAll();
            Quickshell.execDetached([Settings.data.terminal, "-e", "sh", "-c", 'passwd; echo; read -p "Press Enter to close." x']);
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.note !== ""
        text: page.note
        color: Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
}
