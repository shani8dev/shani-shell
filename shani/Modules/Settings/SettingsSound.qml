// Settings > Sound: the sound effects (SoundFx) — presets and a 10-band
// equaliser, bass boost, stereo width, headphone crossfeed, a headphone's
// AutoEq correction and an impulse response.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    readonly property var d: Settings.data
    property string fileTarget: ""
    // made on first use: a native dialog is the desktop portal's, and made with
    // the page it held the whole shell while D-Bus waited for the portal
    Loader {
        id: soundFileDialog
        active: false
        function open() { active = true; item.open(); }
        sourceComponent: FileDialog {
            title: Tr.t("Choose a file")
            onAccepted: {
                const p = selectedFile.toString().replace(/^file:\/\//, "");
                if (page.fileTarget === "autoeq") page.autoEqPath = p;
                else if (page.fileTarget === "ir") page.d.fxIr = p;
            }
        }
    }

    // ---- devices: each sound card's profile (HDMI or analog, headset mic modes) ----
    property var cards: []                // [{ name, label, active, profiles: [{ name, label }] }]
    Component.onCompleted: cardList.running = true
    Process {
        id: cardList
        command: ["pactl", "-f", "json", "list", "cards"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.cards = JSON.parse(text).map(c => ({
                        name: c.name,
                        label: (c.properties || {})["device.description"] || c.name,
                        active: c.active_profile,
                        profiles: Object.keys(c.profiles || {}).filter(k => c.profiles[k].available !== false && k !== "off")
                            .map(k => ({ name: k, label: c.profiles[k].description || k }))
                    })).filter(c => c.profiles.length > 1);
                } catch (e) {}
            }
        }
    }
    Process { id: setProfile; onExited: cardList.running = true }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Sound") }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Allow volume above 100 %"); hint: Tr.t("for quiet speakers — loud audio may distort"); checked: page.d.overAmplify; onToggled: on => page.d.overAmplify = on }
    Picks {
        label: Tr.t("Volume keys change it by")
        options: [{ label: "2 %", value: 2 }, { label: "5 %", value: 5 }, { label: "10 %", value: 10 }]
        current: page.d.volumeStep
        onPicked: v => page.d.volumeStep = v
    }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("System sounds"); hint: Tr.t("desktop event sounds"); checked: page.d.systemSounds; onToggled: on => page.d.systemSounds = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Volume change sound"); checked: page.d.soundVolumeChange !== false; onToggled: on => page.d.soundVolumeChange = on; enabled: page.d.systemSounds }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Screenshot shutter"); checked: page.d.soundScreenshot !== false; onToggled: on => page.d.soundScreenshot = on; enabled: page.d.systemSounds }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Notification sounds"); checked: page.d.soundNotification !== false; onToggled: on => page.d.soundNotification = on }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text { text: Tr.t("Balance"); color: Theme.text; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale }
        Text { Layout.fillWidth: true; text: Tr.t("L"); color: Theme.dim; horizontalAlignment: Text.AlignRight }
        Text { text: (Audio.balance || 0) === 0 ? Tr.t("Centre") : ((Audio.balance || 0) > 0 ? ("R+" + (Audio.balance||0)) : ("L+" + Math.abs(Audio.balance||0))); color: Theme.accent; font.family: Theme.font }
        Text { text: Tr.t("R"); color: Theme.dim }
        IconButton { icon: "go-previous"; onClicked: if (Audio.setBalance) Audio.setBalance((Audio.balance||0)-10); }
        IconButton { icon: "go-next"; onClicked: if (Audio.setBalance) Audio.setBalance((Audio.balance||0)+10); }
        IconButton { icon: "dialog-cancel"; tip: Tr.t("Centre"); onClicked: if (Audio.setBalance) Audio.setBalance(0); }
    }
    Repeater {
        model: page.cards
        ColumnLayout {
            id: card
            required property var modelData
            Layout.fillWidth: true
            spacing: 6
            Text { text: card.modelData.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: card.modelData.profiles
                    Choice {
                        required property var modelData
                        text: modelData.label
                        selected: card.modelData.active === modelData.name
                        onClicked: {
                            setProfile.command = ["pactl", "set-card-profile", card.modelData.name, modelData.name];
                            setProfile.running = true;
                        }
                    }
                }
            }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Sound effects") }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Sound effects")
        hint: SoundFx.error ? SoundFx.error : SoundFx.on ? (SoundFx.running ? "playing through them into " + (SoundFx.target || "the output") : "starting…") : "equaliser, bass, width, crossfeed, headphone correction"
        checked: page.d.fxEnabled
        onToggled: on => page.d.fxEnabled = on
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: Object.keys(SoundFx.presets)
            Choice {
                required property string modelData
                text: modelData
                selected: page.d.fxPreset === modelData
                onClicked: SoundFx.applyPreset(modelData)
            }
        }
    }

    // the equaliser: drag a bar up or down, ±12 dB
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 150
        spacing: 4
        Repeater {
            model: SoundFx.bands
            ColumnLayout {
                id: band
                required property int modelData
                required property int index
                readonly property real gain: (page.d.fxEq || [])[index] || 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2
                Text { Layout.alignment: Qt.AlignHCenter; text: (band.gain > 0 ? "+" : "") + band.gain; color: Theme.dim; font.family: Theme.font; font.pixelSize: 9 * Theme.fontScale }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4; height: parent.height; radius: 2; color: Theme.hover }
                    Rectangle {      // 0 dB line
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.height / 2
                        width: 12; height: 1; color: Theme.stroke
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 4
                        radius: 2
                        color: Theme.accent
                        y: band.gain >= 0 ? parent.height / 2 - parent.height / 2 * band.gain / 12 : parent.height / 2
                        height: Math.abs(parent.height / 2 * band.gain / 12)
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 14; height: 14; radius: 7
                        color: Theme.accent
                        y: parent.height / 2 - parent.height / 2 * band.gain / 12 - 7
                    }
                    MouseArea {
                        anchors.fill: parent
                        Accessible.role: Accessible.Slider
                        Accessible.name: (band.modelData >= 1000 ? band.modelData / 1000 + " kHz" : band.modelData + " Hz") + ", " + band.gain + " dB"
                        function set(y) {
                            const g = Math.max(-12, Math.min(12, Math.round((0.5 - y / height) * 24)));
                            const eq = Array.from(page.d.fxEq || []);
                            while (eq.length < 10) eq.push(0);
                            if (eq[band.index] === g)
                                return;
                            eq[band.index] = g;
                            page.d.fxEq = eq;
                            page.d.fxPreset = "";
                        }
                        onPressed: m => set(m.y)
                        onPositionChanged: m => { if (pressed) set(m.y); }
                    }
                    // keyboard and controller: Up / Down move to the next band, Left / Right are -/+1 dB
                    KeyFocus {
                        name: (band.modelData >= 1000 ? band.modelData / 1000 + " kHz" : band.modelData + " Hz") + ", " + band.gain + " dB"
                        slider: true
                        onStep: dir => {
                            const eq = Array.from(page.d.fxEq || []);
                            while (eq.length < 10) eq.push(0);
                            eq[band.index] = Math.max(-12, Math.min(12, eq[band.index] + dir));
                            page.d.fxEq = eq;
                            page.d.fxPreset = "";
                        }
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: band.modelData >= 1000 ? band.modelData / 1000 + "k" : String(band.modelData)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9 * Theme.fontScale
                }
            }
        }
    }

    Picks {
        label: Tr.t("Bass boost")
        options: [{ label: Tr.t("Off"), value: 0 }, { label: Tr.t("+3 dB"), value: 3 }, { label: Tr.t("+6 dB"), value: 6 }, { label: Tr.t("+9 dB"), value: 9 }, { label: Tr.t("+12 dB"), value: 12 }]
        current: page.d.fxBass
        onPicked: v => page.d.fxBass = v
    }
    Picks {
        label: Tr.t("Stereo width")
        options: [{ label: Tr.t("Mono"), value: 0 }, { label: Tr.t("Narrow"), value: 0.6 }, { label: Tr.t("As recorded"), value: 1 }, { label: Tr.t("Wide"), value: 1.5 }, { label: Tr.t("Wider"), value: 2 }]
        current: page.d.fxWidth
        onPicked: v => page.d.fxWidth = v
    }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Headphone crossfeed")
        hint: Tr.t("a little of each side in the other, as speakers would — less tiring on headphones")
        checked: page.d.fxCrossfeed
        onToggled: on => page.d.fxCrossfeed = on
    }

    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Stereo widening")
        hint: Tr.t("a wider image on headphones (matrix spatialiser)")
        visible: SoundFx.canSpatial
        checked: page.d.fxSpatial
        onToggled: on => page.d.fxSpatial = on
    }

    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Even out loudness")
        hint: Tr.t("quiet and loud videos at one level (EBU R128)")
        checked: page.d.fxLoudness
        onToggled: on => page.d.fxLoudness = on
    }
    // compression: quiet parts up and loud parts down (night mode for films)
    Text {
        text: SoundFx.canCompress ? Tr.t("Quiet and loud parts") : Tr.t("Quiet and loud parts — needs swh-plugins")
        color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        enabled: SoundFx.canCompress
        opacity: enabled ? 1 : 0.5
        Repeater {
            model: [{ id: "off", label: Tr.t("As recorded") }, { id: "gentle", label: Tr.t("Gentle") },
                    { id: "night", label: Tr.t("Night mode — dialogue up, bangs down") }]
            Choice { required property var modelData; text: modelData.label; selected: page.d.fxCompress === modelData.id; onClicked: page.d.fxCompress = modelData.id }
        }
    }

    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Lyrics on the media card")
        hint: Tr.t("the line being sung, looked up on lrclib.net while the sidebar is open - the song's title and artist are sent")
        checked: page.d.lyrics
        onToggled: on => page.d.lyrics = on
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Microphone") }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Noise suppression")
        hint: SoundFx.micError ? SoundFx.micError : "keyboard, fan and traffic out of calls and recordings (RNNoise)"
        checked: page.d.micNoise
        onToggled: on => page.d.micNoise = on
    }

    property string autoEqPath: ""
    FileView {
        id: autoEqFile
        path: page.autoEqPath
        printErrors: false
        onLoaded: {
            const t = text();
            if (SoundFx.parseAutoEq(t).length)
                page.d.fxAutoEq = t;
        }
    }
    Advanced {
        Layout.fillWidth: true
        hint: Tr.t("Headphone correction (AutoEq), impulse response")
        SectionTitle { Layout.fillWidth: true; text: Tr.t("Headphone correction") }
        Text {
            Layout.fillWidth: true
            text: page.d.fxAutoEq ? SoundFx.parseAutoEq(page.d.fxAutoEq).length + " correction filters in use." : "AutoEq has a correction for most headphones: download its “ParametricEQ.txt” for yours and pick it below."
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: 12 * Theme.fontScale
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Button { text: Tr.t("Browse for ParametricEQ.txt"); onClicked: { page.fileTarget = "autoeq"; soundFileDialog.open(); } }
            Button { visible: page.d.fxAutoEq !== ""; text: Tr.t("Remove"); onClicked: page.d.fxAutoEq = "" }
        }

        SectionTitle { Layout.fillWidth: true; text: Tr.t("Impulse response") }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                Layout.fillWidth: true
                visible: page.d.fxIr !== ""
                text: page.d.fxIr
                color: Theme.text
                elide: Text.ElideMiddle
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
            }
            Text {
                Layout.fillWidth: true
                visible: page.d.fxIr === ""
                text: Tr.t("A .wav impulse response — room, speaker or headphone")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
            }
            Button { text: Tr.t("Browse"); onClicked: { page.fileTarget = "ir"; soundFileDialog.open(); } }
            Button { visible: page.d.fxIr !== ""; text: Tr.t("Remove"); onClicked: page.d.fxIr = "" }
        }
    }
}
