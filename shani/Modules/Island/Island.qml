// The Island: Chronoa's companion living in the middle of the bar.
//
//   rest      the mascot and one line — what Chronoa is (title, or "Ask me")
//   working   grows to show the tool step in progress, live
//   approval  opens into a card: the request and one button per option,
//             answered here without opening anything
//   ask       click it and it becomes a question field; Enter asks
//
// The mascot frame is Chronoa's own art (org.shani.Chronoa.Mascot.Art, relayed
// by the bridge); until one arrives a built-in orb stands in so the desktop is
// never missing its companion. Its geometry is reported back so Chronoa can
// aim the mascot's gaze at the pointer.
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    screen: Quickshell.screens[0]

    property bool asking: false
    readonly property bool hasApproval: Chronoa.approval !== null
    readonly property bool working: Chronoa.busy || Chronoa.cueText !== "" || Chronoa.step !== ""
    // Live Activities (after iOS): with Chronoa idle, the Island carries the
    // one thing in progress that matters most — and a click acts on it
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || null
    readonly property var activity: !Settings.data.islandActivities ? null : liveActivity
    readonly property var liveActivity: {
        if (Camera.phase === "counting")
            return { icon: "camera-photo", text: "Photo in " + Camera.countdown + "…", color: Theme.accent, run: () => {} };
        if (Camera.phase === "recording")
            return { icon: "camera-video", text: "Recording video · " + Camera.elapsed, color: Theme.red, run: () => Camera.video() };
        if (CallRecorder.recording)
            return { icon: "call-start", text: "Recording call · " + CallRecorder.elapsed, color: Theme.red, run: () => CallRecorder.stop() };
        if (Smart.suggestion)
            return { icon: Smart.suggestion.icon, text: Smart.suggestion.text, color: Smart.suggestion.color || Theme.accent, run: () => { const s = Smart.suggestion; Smart.suggestion = null; s.run(); } };
        if (Recorder.recording && Recorder.selecting)
            return { icon: "media-record", text: "Choose an area to record — Esc cancels", color: Theme.accent, run: () => Recorder.stop() };
        if (Recorder.recording)
            return { icon: "media-record", text: "Recording · " + Recorder.elapsed, color: Theme.red, run: () => Recorder.stop() };
        if (Dictation.phase === "recording")
            return { icon: "audio-input-microphone", text: "Listening — tap to stop", color: Theme.red, run: () => Dictation.toggle() };
        if (Dictation.phase === "transcribing")
            return { icon: "audio-input-microphone", text: "Writing it down…", color: Theme.accent, run: () => {} };
        if (FocusTimer.running)
            return { icon: "alarm", text: "Focus · " + FocusTimer.label, color: Theme.accent, run: () => Ui.toggleControlCenter("timer") };
        if (Audio.screenShared)
            return { icon: "screen-shared", text: "Sharing your screen", color: Theme.red, run: () => {} };
        if (Backup.running)
            return { icon: "drive-harddisk", text: "Backing up…", color: Theme.accent, run: () => {} };
        if (player)
            return { icon: "media-playback-pause", text: player.trackTitle + (player.trackArtist ? " · " + player.trackArtist : ""), color: Theme.text, run: () => player.togglePlaying() };
        return null;
    }
    onActivityChanged: Ui.islandActivity = activity ? activity.text : ""
    readonly property string mode: hasApproval ? "approval" : asking ? "ask" : working ? "working" : "rest"
    readonly property string line: {
        if (Chronoa.state === "offline")
            return "Chronoa is offline";
        if (Chronoa.cueText !== "")
            return Chronoa.cueText;
        if (Chronoa.step !== "")
            return Chronoa.step;
        if (Chronoa.busy)
            return Chronoa.title || (Chronoa.state === "speaking" ? "Speaking" : "Working on it");
        if (win.activity)
            return win.activity.text;
        return Chronoa.title && Chronoa.title !== "Ready when you are" ? Chronoa.title : "Ask me anything";
    }

    visible: Chronoa.visible
    anchors.top: true
    margins.top: 8
    implicitWidth: card.width
    implicitHeight: card.height
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-island"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: asking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.data.blur ? islandRegion : null
    Region { id: islandRegion; item: card; radius: card.radius }

    // the voice, live: Chronoa's own (the speakers) while it speaks, yours
    // (the microphone) while it listens — the halo swells with the level
    PwNodePeakMonitor {
        id: voice
        node: Chronoa.state === "speaking" ? Audio.sink : Chronoa.state === "listening" ? Audio.source : null
        enabled: node !== null
    }
    readonly property real level: voice.enabled ? Math.min(1, voice.peak * 1.6) : 0

    function report() {
        if (!Bridge.connected)
            return;
        const sx = Math.round((win.screen.width - card.width) / 2);
        const m = mascot.mapToItem(card, 0, 0);
        Bridge.send({
            op: "geometry",
            mascot: [sx + Math.round(m.x), 8 + Math.round(m.y), Math.round(mascot.width), Math.round(mascot.height)],
            island: [sx, 8, Math.round(card.width), Math.round(card.height)],
            panel: Theme.barHeight + 8
        });
    }

    Rectangle {
        id: card
        width: win.mode === "approval" ? 460 : win.mode === "ask" ? 520 : win.mode === "working" ? Math.min(400, Math.max(240, row.implicitWidth + 24)) : row.implicitWidth + 22
        height: win.mode === "approval" ? approvalCol.implicitHeight + Theme.barHeight + 18 : Theme.barHeight
        radius: win.mode === "approval" ? Theme.radiusLarge : Theme.barHeight / 2
        color: Theme.glassStrong
        border.width: 1
        border.color: win.mode === "approval" ? Theme.alpha(Theme.red, 0.45) : win.working ? Theme.alpha(Chronoa.color, 0.45) : Theme.stroke
        clip: true
        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        onWidthChanged: reportTimer.restart()
        onHeightChanged: reportTimer.restart()

        RowLayout {
            id: row
            x: 8
            height: Theme.barHeight
            width: card.width - 16
            spacing: 10

            // ---- the companion ----------------------------------------------
            Item {
                id: mascot
                implicitWidth: 30
                implicitHeight: 30

                // halo: state colour, breathing while busy
                Rectangle {
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    radius: 15
                    color: "transparent"
                    border.width: 2
                    border.color: Chronoa.color
                    opacity: win.working ? 0.9 : 0.35
                    // with a voice, the level drives it; otherwise it breathes
                    scale: win.level > 0 ? 1 + win.level * 0.35 : 1
                    Behavior on scale { enabled: win.level > 0; NumberAnimation { duration: 60 } }
                    SequentialAnimation on scale {
                        running: win.working && win.level === 0
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 1.12; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.12; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    }
                }

                Image {
                    id: art
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    visible: Chronoa.art !== "" && status === Image.Ready
                    // a new rev forces a reload of the same path; Chronoa
                    // rewrites the file atomically, so no half frame is read
                    source: Chronoa.art === "" ? "" : "file://" + Chronoa.art + "#" + Chronoa.artRev
                    cache: false
                    asynchronous: false
                    smooth: true
                    fillMode: Image.PreserveAspectFit
                }

                // built-in companion until Chronoa's art arrives
                Rectangle {
                    id: orb
                    visible: !art.visible
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    radius: 12
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.alpha(Chronoa.color, 0.95) }
                        GradientStop { position: 1.0; color: Theme.alpha(Chronoa.color, 0.45) }
                    }
                    property real lookX: 0
                    property bool blink: false
                    Repeater {
                        model: 2
                        Rectangle {
                            required property int index
                            x: 6 + index * 8 + orb.lookX * 2
                            y: Chronoa.state === "offline" ? 11 : 9
                            width: 4
                            height: orb.blink || Chronoa.state === "offline" ? 1 : 6
                            radius: 2
                            color: Theme.accentInk
                        }
                    }
                    Timer {
                        interval: 3800
                        running: orb.visible
                        repeat: true
                        onTriggered: {
                            orb.blink = true;
                            unblink.restart();
                        }
                    }
                    Timer { id: unblink; interval: 130; onTriggered: orb.blink = false }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPositionChanged: m => orb.lookX = (m.x - width / 2) / (width / 2)
                    onExited: orb.lookX = 0
                    // left: the conversation; right: Lens — point at something and ask
                    onClicked: e => e.button === Qt.RightButton ? Lens.capture() : (Chronoa.open = !Chronoa.open)
                }
            }

            // ---- the line / the question field ----------------------------
            Icon {
                visible: win.mode === "rest" && win.activity !== null
                name: win.activity ? win.activity.icon : ""
                size: 14
                color: win.activity ? win.activity.color : Theme.dim
            }
            Text {
                visible: win.mode !== "ask"
                Layout.fillWidth: win.mode !== "rest"
                Layout.maximumWidth: 340
                Layout.preferredWidth: win.mode === "rest" && win.activity ? Math.min(260, implicitWidth) : implicitWidth
                text: win.line
                color: win.working ? Theme.text : Theme.dim
                elide: Text.ElideRight
                font.family: Chronoa.step !== "" || Chronoa.cueText !== "" ? Theme.mono : Theme.font
                font.pixelSize: 12 * Theme.fontScale
                MouseArea {
                    anchors.fill: parent
                    cursorShape: win.mode === "rest" && win.activity ? Qt.PointingHandCursor : Qt.IBeamCursor
                    onClicked: {
                        if (win.mode === "rest" && win.activity) {
                            win.activity.run();
                            return;
                        }
                        win.asking = true;
                        askInput.forceActiveFocus();
                    }
                }
            }

            TextInput {
                id: askInput
                visible: win.mode === "ask"
                Layout.fillWidth: true
                color: Theme.text
                selectionColor: Theme.accent
                font.family: Theme.font
                font.pixelSize: 13 * Theme.fontScale
                clip: true
                Keys.onEscapePressed: {
                    text = "";
                    win.asking = false;
                }
                onAccepted: {
                    if (text.trim() !== "")
                        Chronoa.ask(text.trim());
                    text = "";
                    win.asking = false;
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: askInput.text === ""
                    text: "Ask Chronoa…  (Enter to send, Esc to close)"
                    color: Theme.faint
                    font: askInput.font
                }
            }

            Text {
                visible: win.mode === "working" && Chronoa.state !== "offline"
                text: Chronoa.label
                color: Chronoa.color
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
        }

        // ---- approval, answered in place ---------------------------------
        ColumnLayout {
            id: approvalCol
            visible: win.mode === "approval"
            x: 18
            y: Theme.barHeight + 2
            width: card.width - 36
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: Chronoa.approval ? Chronoa.approval.text : ""
                color: Theme.text
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: 13 * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: Chronoa.approval ? Chronoa.approval.detail : ""
                color: Theme.dim
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                font.family: Theme.mono
                font.pixelSize: 11 * Theme.fontScale
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: Chronoa.approval ? Chronoa.approval.options : []
                    Button {
                        required property string modelData
                        required property int index
                        text: modelData
                        kind: /deny|no|cancel|reject/i.test(modelData) ? "danger" : index === 0 ? "primary" : "plain"
                        onClicked: Chronoa.approve(Chronoa.approval.id, modelData)
                    }
                }
                Button {
                    text: "Open conversation"
                    onClicked: Chronoa.open = true
                }
            }
            Item { implicitHeight: 4 }
        }
    }

    Connections {
        target: Ui
        function onAskRequested() {
            win.asking = true;
            askInput.forceActiveFocus();
        }
    }

    Timer {
        id: reportTimer
        interval: 250
        onTriggered: win.report()
    }
    Connections {
        target: Bridge
        function onConnectedChanged() {
            reportTimer.restart();
        }
    }
    Component.onCompleted: reportTimer.restart()
}
