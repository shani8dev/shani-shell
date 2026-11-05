// ShaniOS greeter — Quickshell + greetd, same palette as the shell.
// Runs as the `greeter` user inside a bare niri that greetd starts
// (shani-desktop-niri: /etc/greetd/shani-niri-greeter.kdl), and talks to greetd
// through Quickshell's built-in client, which reads $GREETD_SOCK.
//
// The PAM conversation is not assumed to be one password prompt: every
// authMessage that wants an answer becomes the next prompt, so OTP or
// fingerprint-then-password stacks work without code here knowing about them.
//@ pragma IconTheme Adwaita
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd
import QtQuick
import QtQuick.Layouts
import qs.Common

ShellRoot {
    id: root

    // the shell's own tokens (Common/ is shared with shani/), so the login
    // screen and the desktop behind it are one design
    readonly property color bg: Theme.bg
    readonly property color accent: Theme.accent
    readonly property color textColor: Theme.text
    readonly property color dimColor: Theme.dim
    readonly property color errColor: Theme.danger

    // What a successful login starts; SHANI_GREETER_SESSION overrides it
    // (space-separated) so another session can be tried without a rebuild.
    readonly property var sessionCmd: (Quickshell.env("SHANI_GREETER_SESSION") || "niri-session").split(" ")
    readonly property string wallpaper: Quickshell.env("SHANI_GREETER_WALLPAPER")
        || "/usr/share/backgrounds/shani/shani-dark.jpg"

    property string prompt: "Password"
    property bool echo: false
    property string info: ""
    property string error: ""
    // The answer typed before greetd asked for it: the first prompt arrives
    // after createSession(), but the user types the password up front.
    property string pending: ""
    readonly property bool busy: Greetd.state !== GreetdState.Inactive

    // ---- typing without a keyboard, and typing the right thing ----------------------
    // the screen keyboard: open by itself on a computer with a touchscreen (a tablet
    // at the sign-in screen has no other way in), a tap away everywhere else
    property bool kb: Quickshell.env("SHANI_GREETER_KEYBOARD") === "1"
    Process {
        running: Quickshell.env("SHANI_GREETER_KEYBOARD") === ""
        command: ["sh", "-c", "udevadm info --export-db 2>/dev/null | grep -q ID_INPUT_TOUCHSCREEN=1"]
        onExited: code => { if (code === 0) root.kb = true; }
    }
    property bool showPass: false
    // Caps Lock on while a password is typed: said, since nothing else shows it here
    property bool caps: false
    Process {
        id: capsProbe
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null | grep -qv '^0$'"]
        onExited: code => root.caps = code === 0
    }

    // Fingerprint (fprintd): greetd runs one PAM conversation at a time, and
    // fprintd blocks it until a finger or its timeout, so it can't wait beside
    // the password field the way GDM's second conversation does. It is asked for
    // instead - Enter on an empty password, or "Use fingerprint" - by leaving a
    // flag that /etc/pam.d/shani-greetd's first line looks for (pam_exec): the
    // greeter can only choose the fingerprint path, never skip the check.
    property bool fingerprint: Quickshell.env("SHANI_GREETER_FINGERPRINT") === "1"
    readonly property string runDir: Quickshell.env("SHANI_GREETER_RUN") || "/run/shani-greeter"
    Process {
        running: Quickshell.env("SHANI_GREETER_FINGERPRINT") === ""
        command: ["sh", "-c", "test -e /usr/lib/security/pam_fprintd.so && command -v fprintd-verify >/dev/null"]
        onExited: code => root.fingerprint = code === 0
    }
    // Face (linux-hello, Windows Hello's way, IR camera): quick enough - a few
    // seconds, then the password - to go first in the one conversation, so the
    // session starts as soon as the user is known and a look is all it takes.
    // Its PAM module skips straight to the password when its daemon is not up.
    property bool face: Quickshell.env("SHANI_GREETER_FACE") === "1"
    Process {
        running: Quickshell.env("SHANI_GREETER_FACE") === ""
        command: ["sh", "-c", "test -e /usr/lib/security/pam_linux_hello.so && test -S /run/linux-hello.sock"]
        onExited: code => { root.face = code === 0; root.lookForFace(); }
    }
    property string knownUser: Quickshell.env("SHANI_GREETER_USER") || lastUser.text().trim()
    Component.onCompleted: if (face) Qt.callLater(lookForFace)   // forced on (tests): no probe to wait for
    property bool faceTried: false         // once per user picked: not again after it fell to the password
    function lookForFace() {
        if (face && !faceTried && !busy && knownUser.trim() !== "") {
            faceTried = true;
            info = "Looking for your face…";
            Greetd.createSession(knownUser.trim());
        }
    }
    // a prompt is waiting for an answer: before one is, what is typed is kept
    property bool asked: false
    property string fingerUser: ""
    Process {
        id: askFinger
        command: ["sh", "-c", 'touch "$1/fingerprint"', "sh", root.runDir]
        onExited: code => {
            if (code !== 0) {
                root.reset("Fingerprint sign-in is not available here");
                return;
            }
            root.info = "Touch the fingerprint reader";
            Greetd.createSession(root.fingerUser);
        }
    }
    function useFingerprint(user) {
        if (!fingerprint || busy || user.trim() === "")
            return;
        error = "";
        pending = "";
        fingerUser = user.trim();
        askFinger.running = true;
    }

    function submit(user, answer) {
        error = "";
        if (Greetd.state === GreetdState.Inactive) {
            if (user.trim() === "")
                return;
            if (answer === "" && fingerprint) {
                useFingerprint(user);
                return;
            }
            pending = answer;
            Greetd.createSession(user.trim());
        } else if (Greetd.state === GreetdState.Authenticating) {
            if (asked) {
                asked = false;
                Greetd.respond(answer);
            } else {
                pending = answer;          // still looking for a face: the password waits its turn
            }
        }
    }

    function reset(message) {
        asked = false;
        error = message;
        info = "";
        prompt = "Password";
        echo = false;
        pending = "";
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, isError, responseRequired, echoResponse) {
            if (!responseRequired) {
                if (isError)
                    root.error = message;
                else
                    root.info = message;
                return;
            }
            root.info = "";
            if (root.pending !== "" && !echoResponse) {
                const answer = root.pending;
                root.pending = "";
                Greetd.respond(answer);
                return;
            }
            root.prompt = message.replace(/:\s*$/, "");
            root.echo = echoResponse;
            root.asked = true;
        }

        function onAuthFailure(message) {
            root.reset(message || "Login failed");
        }

        function onError(message) {
            Greetd.cancelSession();
            root.reset(message);
        }

        function onReadyToLaunch() {
            root.info = "Starting session…";
            lastUser.setText(Greetd.user);
            // quit=true: Quickshell exits once greetd accepts the session, and
            // the greeter niri's spawn line then ends the compositor.
            Greetd.launch(root.sessionCmd, [], true);
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property bool primary: modelData === Quickshell.screens[0]

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: root.bg
            WlrLayershell.namespace: "shani-greeter"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Image {
                anchors.fill: parent
                source: root.wallpaper === "" ? "" : "file://" + root.wallpaper
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.alpha(Theme.bg, 0.45)
            }

            // the screen keyboard: into whichever field has focus
            ScreenKeyboard {
                visible: root.kb && win.primary
                z: 10
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 72
                width: Math.min(900, parent.width - 40)
                target: userField.input.activeFocus ? userField.input : passField.input
                onEntered: (userField.input.activeFocus ? userField : passField).accepted()
            }

            // accessibility, before anything is typed
            Row {
                visible: win.primary
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 20
                spacing: 6
                Icon { name: "preferences-desktop-accessibility"; size: 20; color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
                Choice { text: "Larger text"; selected: Settings.data.largeText; onClicked: Settings.data.largeText = !Settings.data.largeText }
                Choice { text: "High contrast"; selected: Settings.data.highContrast; onClicked: Settings.data.highContrast = !Settings.data.highContrast }
                Choice { text: "Screen reader"; selected: root.screenReader; onClicked: root.screenReader = !root.screenReader }
            }
            // the machine itself: sleep, restart, power off (logind; an active local session may)
            Row {
                visible: win.primary
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: 20
                spacing: 8
                Choice {
                    visible: root.layout !== ""
                    text: root.layout
                    Accessible.name: "Keyboard layout " + root.layout + ", click for the next"
                    onClicked: { Quickshell.execDetached(["niri", "msg", "action", "switch-layout", "next"]); layoutDelay.restart(); }
                }
                IconButton { icon: "input-keyboard"; on: root.kb; Accessible.name: root.kb ? "Hide the screen keyboard" : "Screen keyboard"; onClicked: root.kb = !root.kb }
                IconButton { icon: "weather-clear-night"; Accessible.name: "Sleep"; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
                // restart and power off: a second tap, so a brushed button turns nothing off
                Repeater {
                    model: [{ icon: "system-reboot", name: "Restart", cmd: "reboot" }, { icon: "system-shutdown", name: "Power off", cmd: "poweroff" }]
                    Row {
                        id: powerKey
                        required property var modelData
                        property bool armed: false
                        spacing: 4
                        Timer { running: powerKey.armed; interval: 4000; onTriggered: powerKey.armed = false }
                        Text {
                            visible: powerKey.armed
                            anchors.verticalCenter: parent.verticalCenter
                            text: powerKey.modelData.name + "?"
                            color: Theme.danger
                            font.family: Theme.font
                            font.pixelSize: 13 * Theme.fontScale
                        }
                        IconButton {
                            icon: powerKey.modelData.icon
                            on: powerKey.armed
                            Accessible.name: powerKey.armed ? powerKey.modelData.name + ", press again to confirm" : powerKey.modelData.name
                            onClicked: powerKey.armed ? Quickshell.execDetached(["systemctl", powerKey.modelData.cmd]) : (powerKey.armed = true)
                        }
                    }
                }
            }
            Timer { id: layoutDelay; interval: 300; onTriggered: root.readLayout() }

            ColumnLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: parent.height * 0.16
                spacing: 2

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatTime(clock.date, "HH:mm")
                    font.features: { "tnum": 1 }
                    color: root.textColor
                    font.family: Theme.font
                    font.pixelSize: 84 * Theme.fontScale
                    font.weight: Font.Light
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDate(clock.date, "dddd, d MMMM")
                    color: root.dimColor
                    font.family: Theme.font
                    font.pixelSize: 18 * Theme.fontScale
                }
            }

            Rectangle {
                id: card
                visible: win.primary
                anchors.centerIn: parent
                anchors.verticalCenterOffset: parent.height * 0.08
                width: 380
                height: form.implicitHeight + 48
                radius: 22
                color: Theme.glassStrong
                border.color: Theme.alpha(Theme.text, 0.08)

                ColumnLayout {
                    id: form
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 12

                    Avatar {
                        Layout.alignment: Qt.AlignHCenter
                        size: 64
                        user: userField.text.trim()
                        home: ""            // the greeter cannot read homes; AccountsService it can
                        visible: userField.text.trim() !== ""
                    }
                    // one click picks who signs in: their picture (AccountsService) and name
                    Flow {
                        Layout.fillWidth: true
                        visible: root.users.length > 1
                        spacing: 8
                        Repeater {
                            model: root.users
                            Rectangle {
                                id: who
                                required property var modelData
                                readonly property bool chosen: userField.text.trim() === modelData.name
                                width: 76
                                height: 84
                                radius: 12
                                color: chosen ? Theme.accentSoft : (pick.containsMouse ? Theme.hover : "transparent")
                                border.color: chosen ? Theme.accent : "transparent"
                                Accessible.role: Accessible.Button
                                Accessible.name: "Sign in as " + (modelData.fullname || modelData.name)
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Avatar { anchors.horizontalCenter: parent.horizontalCenter; size: 44; user: who.modelData.name; home: "" }
                                    Text {
                                        width: 70
                                        horizontalAlignment: Text.AlignHCenter
                                        text: (who.modelData.fullname || who.modelData.name).split(" ")[0]
                                        color: Theme.text
                                        elide: Text.ElideRight
                                        font.family: Theme.font
                                        font.pixelSize: 11 * Theme.fontScale
                                    }
                                }
                                MouseArea {
                                    id: pick
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.otherUser = false; userField.text = who.modelData.name; passField.input.forceActiveFocus(); root.faceTried = false; root.lookForFace(); }
                                }
                                KeyFocus { onActivated: { root.otherUser = false; userField.text = who.modelData.name; passField.input.forceActiveFocus(); root.faceTried = false; root.lookForFace(); } }
                            }
                        }
                    }
                    // who is signing in, by name - the field only for someone not listed
                    readonly property bool picked: !root.otherUser && root.users.some(u => u.name === userField.text.trim())
                    onPickedChanged: if (picked && win.primary) passField.input.forceActiveFocus()
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        visible: form.picked
                        text: root.fullnameOf(userField.text.trim())
                        color: root.textColor
                        font.family: Theme.font
                        font.pixelSize: 18 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }

                    Field {
                        id: userField
                        Layout.fillWidth: true
                        visible: !form.picked
                        placeholder: "User name"
                        enabled: !root.busy
                        text: Quickshell.env("SHANI_GREETER_USER") || lastUser.text().trim() || (root.users.length === 1 ? root.users[0].name : "")
                        onTextChanged: if (win.primary) root.knownUser = text
                        onAccepted: { passField.input.forceActiveFocus(); root.faceTried = false; root.lookForFace(); }
                    }

                    Field {
                        id: passField
                        Layout.fillWidth: true
                        placeholder: root.prompt
                        secret: !root.echo && !root.showPass
                        input.onTextChanged: capsProbe.running = true
                        enabled: Greetd.state !== GreetdState.ReadyToLaunch
                        onAccepted: {
                            root.submit(userField.text, text);
                            text = "";
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            visible: root.caps
                            text: "Caps Lock is on"
                            color: Theme.amber
                            font.family: Theme.font
                            font.pixelSize: 12 * Theme.fontScale
                        }
                        Item { Layout.fillWidth: true; visible: !root.caps }
                        Choice {
                            visible: form.picked && !root.busy
                            text: "Someone else"
                            onClicked: { root.otherUser = true; userField.text = ""; userField.input.forceActiveFocus(); }
                        }
                        Choice {
                            visible: !root.echo
                            text: root.showPass ? "Hide password" : "Show password"
                            selected: root.showPass
                            onClicked: root.showPass = !root.showPass
                        }
                    }

                    Button {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.fingerprint && !root.busy
                        text: "Use fingerprint"
                        onClicked: root.useFingerprint(userField.text)
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.error !== "" ? root.error : root.info
                        color: root.error !== "" ? root.errColor : root.dimColor
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: 13 * Theme.fontScale
                    }
                }

                Component.onCompleted: (userField.text === "" ? userField : passField).input.forceActiveFocus()
            }
        }
    }

    // everyone who can sign in here (UID 1000–59999 with a login shell), with a picture
    property var users: []                // [{ name, fullname }]
    // the person picked, not typed: one account is chosen already; several are a
    // click each; "Someone else" opens the name field for an account not listed
    property bool otherUser: false
    function fullnameOf(n) { const u = users.find(x => x.name === n); return u ? (u.fullname || u.name) : n; }
    Process {
        running: true
        command: ["sh", "-c", 'getent passwd | awk -F: "\\$3 >= 1000 && \\$3 < 60000 && \\$7 !~ /(nologin|false)\\$/ {print \\$1 \\":\\" \\$5}"']
        stdout: StdioCollector {
            onStreamFinished: root.users = text.trim().split("\n").filter(x => x).map(x => {
                const i = x.indexOf(":");
                return { name: x.slice(0, i), fullname: x.slice(i + 1).split(",")[0] };
            })
        }
    }
    // the keyboard layout a password will be typed in (the greeter niri's, from localed)
    property string layout: ""
    function readLayout() { layoutProc.running = true; }
    Process {
        id: layoutProc
        running: true
        command: ["sh", "-c", 'niri msg -j keyboard-layouts 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: { try { const k = JSON.parse(text); root.layout = k.names.length > 1 ? k.names[k.current_idx] : ""; } catch (e) {} }
        }
    }
    property bool screenReader: false
    Process { running: root.screenReader; command: ["orca", "--replace"] }

    // the last user who logged in here, so the next login is one field
    FileView {
        id: lastUser
        path: Quickshell.statePath("last-user")
        blockLoading: true
        blockWrites: true       // written just before launch(quit=true) exits the greeter
        printErrors: false
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    component Field: Rectangle {
        id: field
        property alias text: input.text
        property alias input: input
        property string placeholder: ""
        property bool secret: false
        signal accepted()

        implicitHeight: 42
        radius: 12
        color: Theme.alpha(Theme.text, 0.06)
        border.color: input.activeFocus ? root.accent : Theme.alpha(Theme.text, 0.10)
        opacity: enabled ? 1 : 0.5

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            verticalAlignment: TextInput.AlignVCenter
            color: root.textColor
            selectionColor: root.accent
            font.family: Theme.font
            font.pixelSize: 15 * Theme.fontScale
            echoMode: field.secret ? TextInput.Password : TextInput.Normal
            enabled: field.enabled
            clip: true
            onAccepted: field.accepted()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === ""
                text: field.placeholder
                color: root.dimColor
                font: input.font
            }
        }
    }
}
