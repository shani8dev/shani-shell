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
        || "/usr/share/backgrounds/shani/shani-shell.png"

    property string prompt: "Password"
    property bool echo: false
    property string info: ""
    property string error: ""
    // The answer typed before greetd asked for it: the first prompt arrives
    // after createSession(), but the user types the password up front.
    property string pending: ""
    readonly property bool busy: Greetd.state !== GreetdState.Inactive

    function submit(user, answer) {
        error = "";
        if (Greetd.state === GreetdState.Inactive) {
            if (user.trim() === "")
                return;
            pending = answer;
            Greetd.createSession(user.trim());
        } else if (Greetd.state === GreetdState.Authenticating) {
            Greetd.respond(answer);
        }
    }

    function reset(message) {
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
            if (root.pending !== "" && !echoResponse) {
                const answer = root.pending;
                root.pending = "";
                Greetd.respond(answer);
                return;
            }
            root.prompt = message.replace(/:\s*$/, "");
            root.echo = echoResponse;
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
                color: Qt.rgba(0.043, 0.051, 0.071, 0.45)
            }

            ColumnLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: parent.height * 0.16
                spacing: 2

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatTime(clock.date, "HH:mm")
                    color: root.textColor
                    font.family: "Noto Sans"
                    font.pixelSize: 84
                    font.weight: Font.Light
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDate(clock.date, "dddd, d MMMM")
                    color: root.dimColor
                    font.family: "Noto Sans"
                    font.pixelSize: 18
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
                color: Qt.rgba(0.043, 0.051, 0.071, 0.82)
                border.color: Qt.rgba(1, 1, 1, 0.08)

                ColumnLayout {
                    id: form
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 12

                    Text {
                        text: "SHANI"
                        color: root.accent
                        font.family: "Noto Sans"
                        font.pixelSize: 15
                        font.letterSpacing: 6
                        font.weight: Font.DemiBold
                    }

                    Field {
                        id: userField
                        Layout.fillWidth: true
                        placeholder: "User"
                        enabled: !root.busy
                        text: Quickshell.env("SHANI_GREETER_USER") || lastUser.text().trim()
                        onAccepted: passField.input.forceActiveFocus()
                    }

                    Field {
                        id: passField
                        Layout.fillWidth: true
                        placeholder: root.prompt
                        secret: !root.echo
                        enabled: Greetd.state !== GreetdState.ReadyToLaunch
                        onAccepted: {
                            root.submit(userField.text, text);
                            text = "";
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.error !== "" ? root.error : root.info
                        color: root.error !== "" ? root.errColor : root.dimColor
                        wrapMode: Text.Wrap
                        font.family: "Noto Sans"
                        font.pixelSize: 13
                    }
                }

                Component.onCompleted: (userField.text === "" ? userField : passField).input.forceActiveFocus()
            }
        }
    }

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
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: input.activeFocus ? root.accent : Qt.rgba(1, 1, 1, 0.10)
        opacity: enabled ? 1 : 0.5

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            verticalAlignment: TextInput.AlignVCenter
            color: root.textColor
            selectionColor: root.accent
            font.family: "Noto Sans"
            font.pixelSize: 15
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
