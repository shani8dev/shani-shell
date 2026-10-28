// Settings > Sound: the sound effects (SoundFx) — presets and a 10-band
// equaliser, bass boost, stereo width, headphone crossfeed, a headphone's
// AutoEq correction and an impulse response.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    readonly property var d: Settings.data

    component Picks: ColumnLayout {
        id: picks
        property string label
        property var options: []
        property var current
        signal picked(var value)
        Layout.fillWidth: true
        spacing: 6
        Text { text: picks.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: picks.options
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: picks.current === modelData.value
                    onClicked: picks.picked(modelData.value)
                }
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

    SectionTitle { Layout.fillWidth: true; text: "Sound" }
    SwitchRow { Layout.fillWidth: true; text: "System sounds"; hint: "a click when the volume changes, a shutter for screenshots"; checked: page.d.systemSounds; onToggled: on => page.d.systemSounds = on }
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

    SectionTitle { Layout.fillWidth: true; text: "Sound effects" }
    SwitchRow {
        Layout.fillWidth: true
        text: "Sound effects"
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
        label: "Bass boost"
        options: [{ label: "Off", value: 0 }, { label: "+3 dB", value: 3 }, { label: "+6 dB", value: 6 }, { label: "+9 dB", value: 9 }, { label: "+12 dB", value: 12 }]
        current: page.d.fxBass
        onPicked: v => page.d.fxBass = v
    }
    Picks {
        label: "Stereo width"
        options: [{ label: "Mono", value: 0 }, { label: "Narrow", value: 0.6 }, { label: "As recorded", value: 1 }, { label: "Wide", value: 1.5 }, { label: "Wider", value: 2 }]
        current: page.d.fxWidth
        onPicked: v => page.d.fxWidth = v
    }
    SwitchRow {
        Layout.fillWidth: true
        text: "Headphone crossfeed"
        hint: "a little of each side in the other, as speakers would — less tiring on headphones"
        checked: page.d.fxCrossfeed
        onToggled: on => page.d.fxCrossfeed = on
    }

    SwitchRow {
        Layout.fillWidth: true
        text: "Even out loudness"
        hint: "quiet and loud videos at one level (EBU R128)"
        checked: page.d.fxLoudness
        onToggled: on => page.d.fxLoudness = on
    }

    SectionTitle { Layout.fillWidth: true; text: "Microphone" }
    SwitchRow {
        Layout.fillWidth: true
        text: "Noise suppression"
        hint: SoundFx.micError ? SoundFx.micError : "keyboard, fan and traffic out of calls and recordings (RNNoise)"
        checked: page.d.micNoise
        onToggled: on => page.d.micNoise = on
    }

    SectionTitle { Layout.fillWidth: true; text: "Headphone correction" }
    Text {
        Layout.fillWidth: true
        text: page.d.fxAutoEq ? SoundFx.parseAutoEq(page.d.fxAutoEq).length + " correction filters in use." : "AutoEq has a correction for most headphones: download its “ParametricEQ.txt” for yours and give its path here."
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
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
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        TextField {
            Layout.fillWidth: true
            placeholder: "~/Downloads/… ParametricEQ.txt"
            onAccepted: page.autoEqPath = text.trim().replace(/^~/, Quickshell.env("HOME"))
        }
        Button { visible: page.d.fxAutoEq !== ""; text: "Remove"; onClicked: page.d.fxAutoEq = "" }
    }

    SectionTitle { Layout.fillWidth: true; text: "Impulse response" }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        TextField {
            Layout.fillWidth: true
            placeholder: page.d.fxIr || "A .wav impulse response — room, speaker or headphone (JamesDSP/ViPER IRs work)"
            onAccepted: page.d.fxIr = text.trim().replace(/^~/, Quickshell.env("HOME"))
        }
        Button { visible: page.d.fxIr !== ""; text: "Remove"; onClicked: page.d.fxIr = "" }
    }
}
