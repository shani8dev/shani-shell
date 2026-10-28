// The lock screen: ext-session-lock covers every output (if the shell dies,
// niri keeps the session locked rather than revealing it). One PAM
// conversation; the password field lives on each output's surface.
// PAM stack: /etc/pam.d/shani-lock (shipped with the package);
// SHANI_PAM_DIR overrides the directory for tests.
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

Scope {
    id: root
    property string message: ""
    property bool error: false
    property bool busy: false
    property string pending: ""
    property string queued: ""      // typed while PAM was still answering the last try

    function submit(text) {
        if (text === "")
            return;
        if (busy) {
            // PAM's failure delay keeps it busy for a couple of seconds after a
            // wrong password; what is typed then is kept, not dropped
            queued = text;
            return;
        }
        error = false;
        message = "";
        pending = text;
        busy = true;
        if (!pam.start()) {
            busy = false;
            error = true;
            message = "Could not start authentication";
        }
    }

    PamContext {
        id: pam
        config: "shani-lock"
        configDirectory: Quickshell.env("SHANI_PAM_DIR") || "/etc/pam.d"
        user: Quickshell.env("USER") || ""
        onPamMessage: {
            if (responseRequired) {
                respond(root.pending);
                root.pending = "";
            } else if (messageIsError) {
                root.message = message;
                root.error = true;
            } else {
                root.message = message;
            }
        }
        onCompleted: result => {
            root.busy = false;
            root.pending = "";
            if (result === PamResult.Success) {
                root.message = "";
                // through the service only: assigning lock.locked here would
                // break its binding, and the next Lock.lock() would do nothing
                Lock.unlocked();
            } else {
                root.error = true;
                root.message = result === PamResult.MaxTries ? "Too many attempts — wait a moment" : "Wrong password";
                if (root.queued !== "") {
                    const next = root.queued;
                    root.queued = "";
                    root.submit(next);
                }
            }
        }
        onError: e => {
            root.busy = false;
            root.error = true;
            root.message = "Authentication error";
        }
    }

    // If the session lock is lost (the compositor refused it, or dropped it),
    // Quickshell sets `locked` false itself — which also breaks the binding
    // below, so the screen would stay open while Lock.locked says otherwise.
    // Re-binding asks again, until the lock is really up. (Lock retry after
    // DankMaterialShell / Dux Shell's lockRetryPending, MIT.)
    Timer {
        interval: 500
        repeat: true
        running: Lock.locked && !lock.locked
        onTriggered: lock.locked = Qt.binding(() => Lock.locked)
    }

    WlSessionLock {
        id: lock
        locked: Lock.locked
        onSecureChanged: Lock.secure = secure

        WlSessionLockSurface {
            id: surface
            color: Theme.bg

            Image {
                anchors.fill: parent
                source: "file://" + Settings.data.wallpaper
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Rectangle {
                anchors.fill: parent
                color: Theme.alpha(Theme.bg, 0.55)
            }

            ColumnLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: parent.height * 0.16
                spacing: 2
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatTime(clock.date, Settings.data.use24h ? "HH:mm" : "h:mm AP")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 96
                    font.weight: Font.Light
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDate(clock.date, "dddd, d MMMM")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 18
                }
            }

            Glass {
                strong: true
                anchors.centerIn: parent
                anchors.verticalCenterOffset: parent.height * 0.1
                width: 380
                height: form.implicitHeight + 40
                radius: Theme.radiusLarge

                ColumnLayout {
                    id: form
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12
                    Text {
                        text: Quickshell.env("USER") || ""
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }
                    TextField {
                        id: pass
                        Layout.fillWidth: true
                        placeholder: root.busy ? "Checking…" : "Password"
                        secret: true
                        onAccepted: {
                            root.submit(text);
                            text = "";
                        }
                        Component.onCompleted: pass.input.forceActiveFocus()
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.message
                        color: root.error ? Theme.danger : Theme.dim
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: Power.hasBattery
                        Icon { name: Power.batteryIcon; size: 14; color: Theme.dim }
                        Text {
                            text: Math.round(Power.percent * 100) + "%"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
