// Kundali (Kundali): Vedic birth chart and Panchang using NASA JPL DE440s.
// Offline, no API keys. Computes sidereal birth charts and daily panchang.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services as Services

AppWindow {
    id: win
    appName: "Kundali"
    visible: Ui.kundali
    onGone: Ui.kundali = false
    margins: 0
    implicitWidth: Theme.px(700)
    implicitHeight: Theme.px(600)

    property string mode: "panchang"  // panchang or kundali
    property string dateInput: ""
    property string timeInput: "12:00"
    property string latInput: "28.6139"
    property string lonInput: "77.2090"
    property string result: ""
    property bool loading: false

    // The calendar opens this with a day in mind: use it, and do the panchang
    // once, so the person sees the tithi rather than an empty form.
    onVisibleChanged: if (visible && Ui.kundaliDate) {
        win.mode = "panchang";
        win.dateInput = Ui.kundaliDate;
        win.calculate();
    }

    function calculate() {
        win.loading = true;
        win.result = "";
        if (win.mode === "panchang")
            kundaliProc.command = ["python3", win.scriptPath, "panchang", win.dateInput, win.latInput, win.lonInput];
        else
            kundaliProc.command = ["python3", win.scriptPath, "kundali",
                                   win.dateInput + "T" + win.timeInput + ":00Z",
                                   win.latInput, win.lonInput];
        kundaliProc.running = true;
    }


    Item {
        id: card
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Ui.kundali = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            spacing: Theme.px(8)

            // ---- a birth chart, or the day's panchang ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Choice {
                    text: Tr.t("Panchang")
                    selected: win.mode === "panchang"
                    onClicked: win.mode = "panchang"
                }
                Choice {
                    text: Tr.t("Kundali")
                    selected: win.mode === "kundali"
                    onClicked: win.mode = "kundali"
                }
                Item { Layout.fillWidth: true }
            }

            // ---- when ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                TextField {
                    Layout.fillWidth: true
                    placeholderText: Tr.t("Date, e.g. 1990-01-01")
                    text: win.dateInput
                    onTextChanged: win.dateInput = text
                    onAccepted: win.calculate()
                }
                TextField {
                    Layout.preferredWidth: Theme.px(80)
                    visible: win.mode === "kundali"
                    placeholderText: Tr.t("Time")
                    text: win.timeInput
                    onTextChanged: win.timeInput = text
                    onAccepted: win.calculate()
                }
            }

            // ---- where ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(2)
                    Text { text: Tr.t("Latitude"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    TextField {
                        Layout.fillWidth: true
                        placeholderText: "28.6139"
                        label: Tr.t("Latitude")
                        text: win.latInput
                        onTextChanged: win.latInput = text
                        onAccepted: win.calculate()
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(2)
                    Text { text: Tr.t("Longitude"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    TextField {
                        Layout.fillWidth: true
                        placeholderText: "77.2090"
                        label: Tr.t("Longitude")
                        text: win.lonInput
                        onTextChanged: win.lonInput = text
                        onAccepted: win.calculate()
                    }
                }
            }

            Button {
                Layout.fillWidth: true
                kind: "primary"
                text: win.loading ? Tr.t("Computing…") : Tr.t("Calculate")
                enabled: !win.loading && win.dateInput !== ""
                onClicked: win.calculate()
            }

            // ---- what came back: a card to read, and to copy out of ----
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Theme.px(120)
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.stroke
                clip: true
                Flickable {
                    anchors.fill: parent
                    anchors.margins: Theme.px(12)
                    contentWidth: width
                    contentHeight: outText.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    TextEdit {
                        id: outText
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        text: win.result
                        color: Theme.text
                        selectionColor: Theme.accent
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        Accessible.role: Accessible.StaticText
                        Accessible.name: Tr.t("Kundali")
                    }
                }
                Spinner {
                    anchors.centerIn: parent
                    visible: win.loading
                    size: Theme.px(24)
                }
                Text {
                    anchors.centerIn: parent
                    width: parent.width - Theme.px(32)
                    visible: !win.loading && win.result === ""
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: Tr.t("Enter a date, then Calculate — tithi or the birth chart appears here")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
            }
        }
    }

    readonly property string scriptPath: Quickshell.env("SHANI_KUNDALI_TOOL") || "/usr/lib/shani-shell/kundali.py"

    Process {
        id: kundaliProc
        running: false
        onExited: code => {
            if (code !== 0) {
                win.loading = false;
                win.result = Tr.t("The calculation failed — is the Kundali helper installed?");
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.error) {
                        win.result = Tr.t("Could not compute: %1").arg(data.error);
                    } else if (win.mode === "panchang") {
                        win.result = Tr.t("Tithi: %1").arg(data.tithi) + "\n" +
                                    Tr.t("Vara: %1").arg(data.vara) + "\n" +
                                    Tr.t("Nakshatra: %1").arg(data.nakshatra) + "\n" +
                                    Tr.t("Yoga: %1").arg(data.yoga) + "\n" +
                                    Tr.t("Karana: %1").arg(data.karana);
                    } else {
                        let r = Tr.t("Kundali (Sidereal, Lahiri)") + "\n\n" + Tr.t("Planets:") + "\n";
                        for (const p of data.planets) {
                            r += "  " + p.name + ": " + p.sign + " " + p.degree + "°" + String(p.minute).padStart(2, '0') + "'" + (p.retrograde ? " " + Tr.t("(R)") : "") + "\n";
                        }
                        r += "\n" + Tr.t("Houses:") + "\n";
                        for (const h of data.houses) {
                            r += "  " + Tr.t("House %1", h.number) + ": " + h.sign + " " + h.degree + "°" + String(h.minute).padStart(2, '0') + "'\n";
                        }
                        win.result = r;
                    }
                } catch (e) {
                    win.result = Tr.t("The result could not be read");
                }
                win.loading = false;
            }
        }
    }
}
