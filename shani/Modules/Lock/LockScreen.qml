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
    // the camera from the lock screen (Android's, iOS's): a photo can be taken
    // without unlocking, and only the ones taken while locked are shown here
    property var lockPhotos: []
    property bool lockShotPending: false
    function lockPhoto() { lockShotPending = true; Camera.photo(); }
    Connections {
        target: Camera
        function onPhaseChanged() {
            if (Camera.phase === "idle" && root.lockShotPending) {
                root.lockShotPending = false;
                if (Lock.locked && Camera.last.endsWith(".png"))
                    root.lockPhotos = root.lockPhotos.concat([Camera.last]);
            }
        }
    }
    Connections { target: Lock; function onLockedChanged() { if (!Lock.locked) root.lockPhotos = []; } }

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
                // at a glance (a phone's lock screen): the weather, and the next event
                // only when previews are allowed on the lock screen (Privacy)
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    readonly property var next: Settings.data.lockPreviews && Agenda.upcoming.length ? Agenda.upcoming[0] : null
                    text: [Weather.summary, next ? Agenda.when(next) + " · " + next.summary : ""].filter(x => x).join("    ")
                    visible: text !== ""
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 14 * Theme.fontScale
                }
            }

            // the camera, bottom right (only with a camera and the camera switch on)
            Column {
                visible: Camera.available && Privacy.cameraEnabled
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 32
                spacing: 10
                Image {
                    visible: root.lockPhotos.length > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 96
                    height: 72
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(192, 144)
                    source: root.lockPhotos.length ? "file://" + root.lockPhotos[root.lockPhotos.length - 1] : ""
                    Accessible.role: Accessible.Graphic
                    Accessible.name: Tr.t("The photo just taken")
                }
                Glass {
                    anchors.horizontalCenter: parent.horizontalCenter
                    strong: true
                    width: 56
                    height: 56
                    radius: 28
                    Text {
                        visible: Camera.phase === "counting"
                        anchors.centerIn: parent
                        text: Camera.countdown
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 22 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    IconButton {
                        visible: Camera.phase !== "counting"
                        anchors.centerIn: parent
                        icon: "camera-photo"
                        size: 40
                        tip: Tr.t("Take a photo")
                        enabled: Camera.phase === "idle"
                        onClicked: root.lockPhoto()
                    }
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
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
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
                        // the arrow, for a mouse or a touch screen
                        IconButton {
                            icon: "go-next"
                            size: 34
                            on: pass.text !== ""
                            tip: Tr.t("Unlock")
                            onClicked: { root.submit(pass.text); pass.text = ""; }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: LockKeys.caps
                        text: Tr.t("Caps Lock is on")
                        color: Theme.amber
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
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
                    // what is waiting, at a glance: how many, not what (the content
                    // stays behind the lock, unless previews are on), and the battery
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 2
                        spacing: 16
                        Row {
                            visible: Notifs.count > 0
                            spacing: 5
                            Icon { name: "preferences-system-notifications"; size: 14; color: Theme.dim; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: Notifs.count
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 12 * Theme.fontScale
                                Accessible.name: Notifs.count + (Notifs.count === 1 ? " notification" : " notifications")
                            }
                        }
                        Row {
                            visible: Power.hasBattery
                            spacing: 5
                            Icon { name: Power.batteryIcon; size: 14; color: Theme.dim; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: Math.round(Power.percent * 100) + "%"
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 12 * Theme.fontScale
                            }
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
