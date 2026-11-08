// Kundali (Kundali): Vedic birth chart and Panchang using NASA JPL DE440s.
// Offline, no API keys. Computes sidereal birth charts and daily panchang.
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services as Services

PanelWindow {
    id: win
    visible: Ui.kundali && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Services.Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-kundali"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property string mode: "panchang"  // panchang or kundali
    property string dateInput: ""
    property string timeInput: "12:00"
    property string latInput: "28.6139"
    property string lonInput: "77.2090"
    property string result: ""
    property bool loading: false

    MouseArea { anchors.fill: parent; onClicked: Ui.kundali = false }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 700)
        height: Math.min(parent.height - 60, 600)
        radius: Theme.radiusLg

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            Label { text: "Kundali & Panchang"; font.bold: true; font.pixelSize: 18 }

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
                onClicked: {
                    win.loading = true;
                    win.result = "";
                    if (win.mode === "panchang") {
                        kundaliProc.command = ["python3", win.scriptPath, "panchang", win.dateInput, win.latInput, win.lonInput];
                    } else {
                        const dt = win.dateInput + "T" + win.timeInput + ":00Z";
                        kundaliProc.command = ["python3", win.scriptPath, "kundali", dt, win.latInput, win.lonInput];
                    }
                    kundaliProc.running = true;
                }
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

            Button { Layout.fillWidth: true; text: "Close"; onClicked: Ui.kundali = false }
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
