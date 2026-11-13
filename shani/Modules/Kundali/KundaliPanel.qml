// Kundali (Kundali): Vedic birth chart and Panchang using NASA JPL DE440s.
// Offline, no API keys. Computes sidereal birth charts and daily panchang.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services as Services

AppWindow {
    id: win
    appName: "Kundali"
    visible: Ui.kundali
    onGone: Ui.kundali = false
    margins: 0
    implicitWidth: 700
    implicitHeight: 600

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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Button { text: "Panchang"; checked: win.mode === "panchang"; onClicked: win.mode = "panchang" }
                Button { text: "Kundali"; checked: win.mode === "kundali"; onClicked: win.mode = "kundali" }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                TextField { Layout.fillWidth: true; placeholderText: "Date (YYYY-MM-DD)"; text: win.dateInput; onTextChanged: win.dateInput = text }
                TextField { Layout.preferredWidth: 80; placeholderText: "Time (HH:MM)"; text: win.timeInput; onTextChanged: win.timeInput = text }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                TextField { Layout.fillWidth: true; placeholderText: "Latitude"; text: win.latInput; onTextChanged: win.latInput = text }
                TextField { Layout.fillWidth: true; placeholderText: "Longitude"; text: win.lonInput; onTextChanged: win.lonInput = text }
            }

            Button {
                Layout.fillWidth: true
                text: win.loading ? "Computing..." : "Calculate"
                enabled: !win.loading && win.dateInput !== ""
                onClicked: win.calculate()
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                TextArea {
                    text: win.result
                    readOnly: true
                    font.family: "monospace"
                    font.pixelSize: 12
                    wrapMode: TextEdit.Wrap
                }
            }

        }
    }

    readonly property string scriptPath: Quickshell.env("SHANI_KUNDALI_TOOL") || "/usr/lib/shani-shell/kundali.py"

    Process {
        id: kundaliProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.error) {
                        win.result = "Error: " + data.error;
                    } else if (win.mode === "panchang") {
                        win.result = "Tithi: " + data.tithi + "\n" +
                                    "Vara: " + data.vara + "\n" +
                                    "Nakshatra: " + data.nakshatra + "\n" +
                                    "Yoga: " + data.yoga + "\n" +
                                    "Karana: " + data.karana;
                    } else {
                        let r = "Kundali (Sidereal, Lahiri)\n\nPlanets:\n";
                        for (const p of data.planets) {
                            r += "  " + p.name + ": " + p.sign + " " + p.degree + "°" + String(p.minute).padStart(2, '0') + "'" + (p.retrograde ? " (R)" : "") + "\n";
                        }
                        r += "\nHouses:\n";
                        for (const h of data.houses) {
                            r += "  House " + h.number + ": " + h.sign + " " + h.degree + "°" + String(h.minute).padStart(2, '0') + "'\n";
                        }
                        win.result = r;
                    }
                } catch (e) {
                    win.result = "Parse error: " + e.message + "\nRaw: " + text;
                }
                win.loading = false;
            }
        }
    }

    Keys.onEscapePressed: Ui.kundali = false
}
