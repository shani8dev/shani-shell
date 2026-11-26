// FM radio as one source of the Media Player's Radio page. Devices owns the
// tuner; this view only picks a frequency and shows what the tuner reports.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

Flickable {
    id: fm
    Layout.fillWidth: true
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: width
    contentHeight: column.implicitHeight

    readonly property var presets: [91.1, 92.7, 93.5, 94.3, 95.0, 96.7, 98.3, 100.1, 102.9, 104.0, 105.5, 106.4]
    property string custom: ""
    property bool badFrequency: false
    readonly property string state: String(Devices.fmState || "")
    readonly property bool active: fm.state === "on" || fm.state === "running"

    function tune(value) {
        const n = Number(value);
        fm.badFrequency = !isFinite(n) || n < 87.5 || n > 108;
        if (!fm.badFrequency) Devices.fm("tune", n);
    }
    function start() {
        const n = Number(fm.custom);
        if (fm.custom.trim() !== "" && isFinite(n) && n >= 87.5 && n <= 108)
            Devices.fm("start", n);
        else
            Devices.fm("start");
    }
    Component.onCompleted: Devices.fm("state")

    ColumnLayout {
        id: column
        width: fm.width
        spacing: Theme.px(8)

        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.px(10)
            Layout.leftMargin: Theme.px(10)
            Layout.rightMargin: Theme.px(10)
            text: fm.active ? Tr.t("FM radio playing at %1 MHz", Devices.fmFrequency)
                : fm.state !== "" && fm.state !== "off" && fm.state !== "stopped" ? Tr.t("FM radio: %1", fm.state)
                : Tr.t("FM radio is off")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StatusBar
            Accessible.name: text
        }

        EmptyState {
            visible: !fm.active
            icon: "audio-x-generic"
            title: Tr.t("No station playing yet")
            subtitle: Tr.t("Pick a preset or enter a frequency, then press Start.")
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.px(10)
            text: Tr.t("Presets")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
            font.weight: Font.DemiBold
        }
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.px(10)
            Layout.rightMargin: Theme.px(10)
            // a Flow has no height of its own in a ColumnLayout: without this
            // the chips collapse or overlap the field below
            height: Math.max(childrenRect.height, Math.max(Theme.px(28), Theme.touchTarget))
            spacing: Theme.px(6)
            Repeater {
                model: fm.presets
                Choice {
                    required property var modelData
                    text: Number(modelData).toFixed(1) + " MHz"
                    selected: fm.active && Math.abs(Number(Devices.fmFrequency) - modelData) < 0.05
                    onClicked: fm.tune(modelData)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.px(10)
            text: Tr.t("Another frequency")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
            font.weight: Font.DemiBold
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.px(10)
            Layout.rightMargin: Theme.px(10)
            spacing: Theme.px(6)
            TextField {
                id: frequency
                Layout.fillWidth: true
                placeholder: Tr.t("For example 91.1")
                label: Tr.t("Frequency in MHz")
                error: fm.badFrequency ? Tr.t("Enter a frequency between 87.5 and 108") : ""
                text: fm.custom
                onTextChanged: fm.custom = text
                onAccepted: fm.tune(text)
            }
            Button {
                text: Tr.t("Tune")
                flat: true
                onClicked: fm.tune(frequency.text)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.px(10)
            Layout.rightMargin: Theme.px(10)
            Layout.bottomMargin: Theme.px(10)
            spacing: Theme.px(6)
            Button {
                text: Tr.t("Start")
                kind: "primary"
                onClicked: fm.start()
            }
            Button {
                text: Tr.t("Stop")
                flat: true
                onClicked: Devices.fm("stop")
            }
            Item { Layout.fillWidth: true }
            Text {
                text: Tr.t("87.5 to 108 MHz")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.type("caption")
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.px(6)
            Layout.leftMargin: Theme.px(10)
            text: Tr.t("Radio volume")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
            font.weight: Font.DemiBold
        }
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.px(10)
            Layout.rightMargin: Theme.px(10)
            // a Flow has no height of its own in a ColumnLayout: without this
            // the chips collapse or overlap the section below
            height: Math.max(childrenRect.height, Math.max(Theme.px(28), Theme.touchTarget))
            spacing: Theme.px(6)
            Repeater {
                model: [100, 75, 50, 25, 10]
                Choice {
                    required property var modelData
                    text: modelData + "%"
                    selected: Devices.fmVolume === String(modelData)
                    onClicked: Devices.fm("volume", String(modelData))
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.topMargin: Theme.px(6)
            Layout.leftMargin: Theme.px(10)
            Layout.rightMargin: Theme.px(10)
            height: Math.max(childrenRect.height, Math.max(Theme.px(36), Theme.touchTarget))
            spacing: Theme.px(6)
            Button {
                text: Tr.t("Play a recording")
                flat: true
                onClicked: FilePicker.open({
                    mode: "open",
                    title: Tr.t("A recording to play"),
                    filters: ["wav"],
                    onPicked: paths => { if (paths.length) Devices.fm("decode", paths[0]); }
                })
            }
            Button {
                text: Tr.t("Find stations")
                flat: true
                onClicked: FilePicker.open({
                    mode: "open",
                    title: Tr.t("A whole-band recording"),
                    filters: ["wav"],
                    onPicked: paths => { if (paths.length) Devices.fm("scan", paths[0]); }
                })
            }
            Button {
                text: Tr.t("Bands")
                flat: true
                onClicked: Devices.fm("bands")
            }
        }

        InfoBanner {
            visible: Devices.fmReport !== ""
            Layout.fillWidth: true
            Layout.leftMargin: Theme.px(10)
            Layout.rightMargin: Theme.px(10)
            Layout.bottomMargin: Theme.px(10)
            tone: Devices.fmReportError ? "error" : "ok"
            title: Devices.fmReportError ? Tr.t("The radio could not do that") : Tr.t("The radio says")
            text: Devices.fmReport
        }
    }
}
