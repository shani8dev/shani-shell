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
import QtQuick.Effects
import qs.Common
import qs.Services

PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]

    property bool asking: false
    readonly property bool hasApproval: Chronoa.approval !== null
    readonly property bool working: Chronoa.busy || Chronoa.cueText !== "" || Chronoa.step !== ""
    // agent-status expressions for the mascot: pops out when working,
    // blinks faster when thinking, looks up when pondering, waves on connect,
    // and does a happy jump when a task finishes.
    property real mascotScale: 1
    property int blinkInterval: 3800
    property real eyeLookY: 0
    property bool happyJump: false
    property bool wave: false
    property bool _wasBusy: false
    // Live Activities (after iOS): with Chronoa idle, the Island carries the
    // one thing in progress that matters most — and a click acts on it
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || null
    readonly property var activity: !Settings.data.islandActivities ? null : liveActivity
    readonly property var liveActivity: {
        if (Camera.phase === "counting")
            return { icon: "camera-photo", text: "Photo in " + Camera.countdown + "…", color: Theme.accent, run: () => {} };
        if (Camera.phase === "recording")
            return { icon: "camera-video", text: "Recording video · " + Camera.elapsed, color: Theme.red, run: () => Camera.video() };
        if (Modem.call && Modem.call.state === "ringing-in")
            return { icon: "call-start", text: "Call from " + Modem.call.number + " — tap to answer", color: Theme.accent, run: () => Modem.answer() };
        if (Modem.call)
            return { icon: "call-start", text: (Modem.call.state === "active" ? "On a call · " + Modem.callTime : "Calling " + Modem.call.number + "…") + " — tap to hang up",
                     color: Theme.red, run: () => Modem.hangup() };
        if (Notifs.incomingCall)
            return { icon: "call-start", text: Tr.t("%1 — tap to answer", Notifs.incomingCall.summary || Tr.t("A call")), color: Theme.accent, run: () => Notifs.answerCall() };
        if (Printing.jobs > 0)
            return { icon: "printer", text: "Printing " + Printing.jobs + (Printing.jobs === 1 ? " document" : " documents"), color: Theme.accent, run: () => Printing.openQueue() };
        if (CallRecorder.recording)
            return { icon: "call-start", text: "Recording call · " + CallRecorder.elapsed, color: Theme.red, run: () => CallRecorder.stop() };
        if (Smart.suggestion)
            return { icon: Smart.suggestion.icon, text: Smart.suggestion.text, color: Smart.suggestion.color || Theme.accent, run: () => { const s = Smart.suggestion; Smart.suggestion = null; s.run(); } };
        if (Recorder.recording && Recorder.selecting)
            return { icon: "media-record", text: Tr.t("Choose an area to record — Esc cancels"), color: Theme.accent, run: () => Recorder.stop() };
        if (Recorder.recording)
            return { icon: "media-record", text: "Recording · " + Recorder.elapsed, color: Theme.red, run: () => Recorder.stop() };
        if (Dictation.phase === "recording")
            return { icon: "audio-input-microphone", text: Tr.t("Listening — tap to stop"), color: Theme.red, run: () => Dictation.toggle() };
        if (Dictation.phase === "transcribing")
            return { icon: "audio-input-microphone", text: Tr.t("Writing it down…"), color: Theme.accent, run: () => {} };
        if (FocusTimer.running)
            return { icon: "alarm", text: "Focus · " + FocusTimer.label, color: Theme.accent, run: () => Ui.toggleControlCenter("timer") };
        if (Audio.screenShared)
            return { icon: "screen-shared", text: Tr.t("Sharing your screen"), color: Theme.red, run: () => {} };
        if (Backup.running)
            return { icon: "drive-harddisk", text: Tr.t("Backing up…"), color: Theme.accent, run: () => {} };
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
        return Chronoa.title && Chronoa.title !== "Ready when you are" ? Chronoa.title : Tr.t("Ask me anything");
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
        // fade so mode changes feel like a shape, not a jump
        Behavior on opacity { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
        onWidthChanged: reportTimer.restart()
        onHeightChanged: reportTimer.restart()

        // gentle glow when Chronoa is working — a breath behind the card
        Rectangle {
            visible: win.working && Chronoa.state !== "offline"
            anchors.fill: parent
            anchors.margins: -8
            radius: card.radius + 8
            color: Theme.alpha(Chronoa.color, 0.12)
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.alpha(Chronoa.color, 0.35)
                shadowBlur: 14
                shadowVerticalOffset: 0
                shadowHorizontalOffset: 0
                autoPaddingEnabled: true
            }
            SequentialAnimation {
                running: win.working && Chronoa.state !== "offline"
                loops: Animation.Infinite
                NumberAnimation { target: parent; property: "opacity"; from: 0.35; to: 0.85; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { target: parent; property: "opacity"; from: 0.85; to: 0.35; duration: 1100; easing.type: Easing.InOutSine }
            }
        }

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
                scale: win.mascotScale
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                // happy jump: the mascot leaps when a task finishes
                transform: Translate {
                    id: jump
                    y: 0
                }

                // swallow files dropped onto the notch — they become context
                DropArea {
                    anchors.fill: parent
                    onEntered: d => d.accept(d.hasUrls ? Qt.CopyAction : Qt.IgnoreAction)
                    onDropped: d => {
                        const files = d.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, "")))
                        if (files.length)
                            Chronoa.ask("Here are some files for context: " + files.join(", "))
                    }
                }

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
                    // subtle inner glow so the orb reads as lit, not flat
                    Rectangle {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        radius: 7
                        color: "white"
                        opacity: 0.25
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: "white"
                            shadowBlur: 4
                            shadowVerticalOffset: 0
                            shadowHorizontalOffset: 0
                            autoPaddingEnabled: true
                        }
                    }
                    property real lookX: 0
                    property bool blink: false
                    Repeater {
                        model: 2
                        Rectangle {
                            required property int index
                            x: 6 + index * 8 + orb.lookX * 2
                            y: Chronoa.state === "offline" ? 11 + win.eyeLookY : 9 + win.eyeLookY
                            width: 4
                            height: orb.blink || Chronoa.state === "offline" ? 1 : 6
                            radius: 2
                            color: Theme.accentInk
                            Behavior on height { NumberAnimation { duration: 120 } }
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                    }
                    Timer {
                        interval: win.blinkInterval
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
                // a running step reads as words, like everything else on the Island
                font.family: Theme.font
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
                Accessible.role: Accessible.EditableText
                Accessible.name: Tr.t("Ask Chronoa")
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
                    text: Tr.t("Ask Chronoa…  (Enter to send, Esc to close)")
                    color: Theme.faint
                    font: askInput.font
                }
            }

            Text {
                // only while it is doing something: "ready" after a finished step says nothing
                visible: win.mode === "working" && Chronoa.state !== "offline" && Chronoa.label !== "ready"
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
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
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
                        // denying is the safe answer: a plain button, not a red one
                        kind: index === 0 ? "primary" : "plain"
                        onClicked: Chronoa.approve(Chronoa.approval.id, modelData)
                    }
                }
                Button {
                    text: Tr.t("Open conversation")
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

    // agent-status expressions: react to Chronoa's state, step, and busy changes
    Connections {
        target: Chronoa
        function onStateChanged() {
            // pop out when working, settle back at rest
            win.mascotScale = win.working ? 1.18 : 1
            // blink rate by state
            if (Chronoa.state === "thinking") win.blinkInterval = 1400
            else if (Chronoa.state === "speaking") win.blinkInterval = 5500
            else if (Chronoa.state === "listening") win.blinkInterval = 3000
            else if (Chronoa.state === "waiting") win.blinkInterval = 2400
            else if (Chronoa.state === "offline") win.blinkInterval = 6000
            else win.blinkInterval = 3800
            // eye expression by state
            if (Chronoa.state === "thinking") win.eyeLookY = -3
            else if (Chronoa.state === "waiting") win.eyeLookY = 1
            else win.eyeLookY = 0
            // wave when Chronoa first becomes available
            if (Chronoa.state === "idle" && !win._wasBusy) win.wave = true
        }
        function onStepChanged() {
            // react to tool step changes (reading files, editing code, running tests)
            win.mascotScale = win.working ? 1.18 : 1
        }
        function onBusyChanged() {
            // happy jump when a task finishes
            if (win._wasBusy && !Chronoa.busy) {
                win.happyJump = true
                jumpTimer.restart()
            }
            win._wasBusy = Chronoa.busy
            win.mascotScale = win.working ? 1.18 : 1
        }
    }

    // happy-jump animation: mascot bounces when a task finishes
    Timer {
        id: jumpTimer
        interval: 300
        onTriggered: win.happyJump = false
    }
    SequentialAnimation {
        running: win.happyJump
        NumberAnimation { target: mascot.jump; property: "y"; to: -14; duration: 120 }
        NumberAnimation { target: mascot.jump; property: "y"; to: 8; duration: 120 }
        NumberAnimation { target: mascot.jump; property: "y"; to: 0; duration: 180; easing.type: Easing.OutBounce }
        onRunningChanged: if (!running) win.happyJump = false
    }

    // wave animation: mascot bobs side to side when Chronoa greets
    SequentialAnimation {
        running: win.wave
        NumberAnimation { target: mascot; property: "x"; to: 5; duration: 110 }
        NumberAnimation { target: mascot; property: "x"; to: -5; duration: 110 }
        NumberAnimation { target: mascot; property: "x"; to: 5; duration: 110 }
        NumberAnimation { target: mascot; property: "x"; to: 0; duration: 110 }
        onRunningChanged: if (!running) win.wave = false
    }
}
