// The lock screen: ext-session-lock covers every output (if the shell dies,
// niri keeps the session locked rather than revealing it). One PAM
// conversation; the password field lives on each output's surface.
// PAM stack: /etc/pam.d/shani-lock (shipped with the package);
// SHANI_PAM_DIR overrides the directory for tests.
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import Quickshell.Widgets
import QtQuick.Effects
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

            // the wallpaper, blurred and dimmed: the desktop is there, out of reach
            Image {
                id: lockWall
                anchors.fill: parent
                source: "file://" + Theme.wallpaper
                sourceSize: Qt.size(parent.width / 2, parent.height / 2)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            MultiEffect {
                anchors.fill: lockWall
                source: lockWall
                blurEnabled: true
                blur: 1.0
                blurMax: 64
                saturation: 0.15
            }
            Rectangle {
                anchors.fill: parent
                color: Theme.alpha(Theme.bg, 0.45)
            }

            ColumnLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: parent.height * 0.16
                spacing: 2
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatTime(clock.date, Settings.data.use24h ? "HH:mm" : "h:mm AP")
                    font.features: { "tnum": 1 }
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 96 * Theme.fontScale
                    font.weight: Font.Light
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDate(clock.date, "dddd, d MMMM")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 18 * Theme.fontScale
                }
            }

            // what is playing, and the controls (they work while locked, as on a phone)
            Glass {
                id: nowPlaying
                readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
                visible: player !== null && player.trackTitle !== ""
                strong: true
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 80
                width: 380
                height: 76
                radius: Theme.radiusLarge
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    ClippingRectangle {
                        implicitWidth: 52
                        implicitHeight: 52
                        radius: 10
                        color: Theme.hover
                        Image {
                            anchors.fill: parent
                            source: nowPlaying.player ? nowPlaying.player.trackArtUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                    Column {
                        Layout.fillWidth: true
                        Text {
                            width: parent.width
                            text: nowPlaying.player ? nowPlaying.player.trackTitle : ""
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 13 * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: nowPlaying.player ? nowPlaying.player.trackArtist : ""
                            color: Theme.dim
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                        }
                    }
                    IconButton { icon: "media-skip-backward"; size: 30; onClicked: nowPlaying.player.previous() }
                    IconButton { icon: nowPlaying.player && nowPlaying.player.isPlaying ? "media-playback-pause" : "media-playback-start"; size: 34; on: true; onClicked: nowPlaying.player.togglePlaying() }
                    IconButton { icon: "media-skip-forward"; size: 30; onClicked: nowPlaying.player.next() }
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
                    Avatar { Layout.alignment: Qt.AlignHCenter; size: 72 }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Quickshell.env("USER") || ""
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 15 * Theme.fontScale
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
                        font.pixelSize: 12 * Theme.fontScale
                    }
                    // the newest few, by title — only if the person chose that (Privacy)
                    Repeater {
                        model: Settings.data.lockPreviews ? Notifs.list.slice(0, 3) : []
                        Text {
                            required property var modelData
                            Layout.fillWidth: true
                            text: (modelData.appName ? modelData.appName + ": " : "") + modelData.summary
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 12 * Theme.fontScale
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: Notifs.count > 0
                        // how many, not what (unless previews are on): the content stays behind the lock
                        text: Notifs.count + (Notifs.count === 1 ? " notification" : " notifications")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: Power.hasBattery
                        Icon { name: Power.batteryIcon; size: 14; color: Theme.dim }
                        Text {
                            text: Math.round(Power.percent * 100) + "%"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
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
