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
    property string section: "chart"  // a chart's section: chart, dasha, ashtakavarga, ...
    readonly property var sections: [
        ["chart", Tr.t("Chart")],
        ["dasha", Tr.t("Dasha periods")],
        ["ashtakavarga", Tr.t("Ashtakavarga")],
        ["dignity", Tr.t("Planetary dignity")],
        ["aspects", Tr.t("Aspects")],
        ["nakshatra", Tr.t("Nakshatra details")],
        ["eclipse", Tr.t("Eclipses")]
    ]
    property string dateInput: ""
    property string timeInput: "12:00"
    property string latInput: "28.6139"
    property string lonInput: "77.2090"
    property string result: ""
    property bool loading: false
    property bool error: false
    property bool copied: false

    // The chart belongs to the inputs that made it. Editing any of them makes
    // it stale at once, so it is never left looking like the new answer.
    function clearResult() {
        win.result = "";
        win.error = false;
        win.copied = false;
    }

    // A section is data with stable keys; every word here belongs to the UI.
    function renderSection(data) {
        if (win.section === "dasha") {
            let r = Tr.t("Dasha periods") + "\n";
            for (const d of (data.periods || []))
                r += "  " + d.lord + ": " + Tr.t("%1 years", d.years) +
                     " · " + Tr.t("from year %1", d.start_offset) + "\n";
            return r;
        }
        if (win.section === "ashtakavarga") {
            let r = Tr.t("Ashtakavarga") + "\n";
            for (const row of (data.rows || []))
                r += "  " + row.sign + ": " + Tr.t("%1 points", row.points) + "\n";
            return r;
        }
        if (win.section === "dignity") {
            let r = Tr.t("Planetary dignity") + "\n";
            for (const p of (data.planets || []))
                r += "  " + Tr.t("%1 in %2: %3", p.name, p.sign, p.dignity) + "\n";
            return r;
        }
        if (win.section === "aspects") {
            let r = Tr.t("Aspects") + "\n";
            for (const a of (data.aspects || []))
                r += "  " + Tr.t("%1 %2 %3 (orb %4°)", a.planet1, a.aspect, a.planet2, a.orb) + "\n";
            return r;
        }
        if (win.section === "nakshatra") {
            const m = data.moon || {};
            return Tr.t("Nakshatra details") + "\n" +
                "  " + Tr.t("%1, pada %2, lord %3", data.nakshatra, data.pada, data.lord) + "\n" +
                "  " + Tr.t("Moon in %1 %2°%3'", m.sign, m.degree, String(m.minute).padStart(2, '0')) + "\n";
        }
        let r = Tr.t("Eclipses") + "\n" +
            "  " + Tr.t("Solar eclipse: %1", data.solar_eclipse ? Tr.t("Yes") : Tr.t("No")) + "\n" +
            "  " + Tr.t("Lunar eclipse: %1", data.lunar_eclipse ? Tr.t("Yes") : Tr.t("No")) + "\n" +
            "  " + Tr.t("Separation: %1°", data.angular_separation) + "\n";
        if (data.type)
            r += "  " + Tr.t("Type: %1", data.type) + " · " + Tr.t("Magnitude: %1", data.magnitude) + "\n";
        return r;
    }

    // The calendar opens this with a day in mind: use it, and do the panchang
    // once, so the person sees the tithi rather than an empty form.
    onVisibleChanged: if (visible && Ui.kundaliDate) {
        win.mode = "panchang";
        win.dateInput = Ui.kundaliDate;
        win.calculate();
    }

    function calculate() {
        win.loading = true;
        win.clearResult();
        if (win.mode === "panchang")
            kundaliProc.command = ["python3", win.scriptPath, "panchang", win.dateInput, win.latInput, win.lonInput];
        else if (win.section !== "chart")
            kundaliProc.command = ["python3", win.scriptPath, "details", win.section,
                                   win.dateInput + "T" + win.timeInput + ":00Z",
                                   win.latInput, win.lonInput];
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
                    onClicked: { win.mode = "panchang"; win.clearResult() }
                }
                Choice {
                    text: Tr.t("Kundali")
                    selected: win.mode === "kundali"
                    onClicked: { win.mode = "kundali"; win.clearResult() }
                }
                Item { Layout.fillWidth: true }
            }

            // ---- sections of the chart that is open ----
            Flow {
                visible: win.mode === "kundali"
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: win.sections
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.section === modelData[0]
                        onClicked: {
                            win.section = modelData[0];
                            if (win.dateInput !== "") win.calculate();
                            else win.clearResult();
                        }
                    }
                }
            }

            // ---- when ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                TextField {
                    Layout.fillWidth: true
                    placeholderText: Tr.t("Date, e.g. 1990-01-01")
                    text: win.dateInput
                    onTextChanged: { win.dateInput = text; win.clearResult() }
                    onAccepted: win.calculate()
                }
                TextField {
                    Layout.preferredWidth: Theme.px(80)
                    visible: win.mode === "kundali"
                    placeholderText: Tr.t("Time")
                    text: win.timeInput
                    onTextChanged: { win.timeInput = text; win.clearResult() }
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
                        onTextChanged: { win.latInput = text; win.clearResult() }
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
                        onTextChanged: { win.lonInput = text; win.clearResult() }
                        onAccepted: win.calculate()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Button {
                    Layout.fillWidth: true
                    kind: "primary"
                    text: win.loading ? Tr.t("Computing…") : Tr.t("Calculate")
                    enabled: !win.loading && win.dateInput !== ""
                    onClicked: win.calculate()
                }
                Button {
                    Layout.preferredWidth: Theme.px(130)
                    enabled: win.result !== "" && !win.error
                    text: win.copied ? Tr.t("Copied") : Tr.t("Copy result")
                    Accessible.name: win.copied ? Tr.t("Copied") : Tr.t("Copy result")
                    onClicked: {
                        Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", win.result]);
                        win.copied = true;
                    }
                }
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
                        color: win.error ? Theme.danger : Theme.text
                        selectionColor: Theme.accent
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        Accessible.role: Accessible.StaticText
                        Accessible.name: win.error ? Tr.t("Calculation error") : Tr.t("Kundali")
                    }
                }
                BusyNote {
                    anchors.centerIn: parent
                    visible: win.loading
                    note: Tr.t("Loading…")
                    iconSize: Theme.px(24)
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
                win.error = true;
                win.result = Tr.t("The calculation failed — is the Kundali helper installed?");
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    win.error = false;
                    if (data.error) {
                        win.error = true;
                        win.result = Tr.t("Could not compute: %1").arg(data.error);
                    } else if (win.mode === "panchang") {
                        win.result = Tr.t("Tithi: %1").arg(data.tithi) + "\n" +
                                    Tr.t("Vara: %1").arg(data.vara) + "\n" +
                                    Tr.t("Nakshatra: %1").arg(data.nakshatra) + "\n" +
                                    Tr.t("Yoga: %1").arg(data.yoga) + "\n" +
                                    Tr.t("Karana: %1").arg(data.karana);
                    } else if (win.section !== "chart") {
                        win.result = win.renderSection(data);
                    } else {
                        let r = Tr.t("Kundali (Sidereal, Lahiri)") + "\n\n" + Tr.t("Planets:") + "\n";
                        for (const p of data.planets) {
                            r += "  " + p.name + ": " + p.sign + " " + p.degree + "°" + String(p.minute).padStart(2, '0') + "'" + (p.retrograde ? " " + Tr.t("(R)") : "") + "\n";
                        }
                        r += "\n" + Tr.t("Houses:") + "\n";
                        for (const h of data.houses) {
                            r += "  " + Tr.t("House %1", h.house_number || h.number) + ": " + h.sign + " " + h.degree + "°" + String(h.minute).padStart(2, '0') + "'\n";
                        }
                        win.result = r;
                    }
                } catch (e) {
                    win.error = true;
                    win.result = Tr.t("The result could not be read");
                }
                win.loading = false;
            }
        }
    }
}
