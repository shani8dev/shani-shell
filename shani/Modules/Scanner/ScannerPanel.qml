// Scanner: a page from a scanner (SANE's scanimage), kept in Documents/Scans
// and shown - then open, copy the path, or scan again. The scanner, its
// resolution and the file type are picks. Errors are the scanner's own words,
// never written into the file (scanimage's messages go to stderr).
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services as Services

AppWindow {
    id: win
    appName: "Document Scanner"
    tools: [
        IconButton {
            size: Theme.px(30)
            icon: "view-refresh"
            tip: Tr.t("Look again")
            enabled: !win.looking
            onClicked: win.refreshDevices()
        }
    ]
    visible: Ui.scanner
    onGone: Ui.scanner = false
    margins: 0
    implicitWidth: Theme.px(640)
    implicitHeight: Theme.px(620)

    property var devices: []            // [{ id, name }]
    property string device: ""
    property int resolution: 300
    property string format: "png"
    property bool looking: false
    property bool scanning: false
    property bool cancelled: false
    property string lastScan: ""
    property string error: ""
    // scanimage has no --format=pdf (pnm/tiff/png/jpeg only): pdfform.py's
    // topdf wraps the PNG scan into a one-page PDF when PyMuPDF is installed.
    readonly property string pdfTool: Quickshell.env("SHANI_PDFFORM_TOOL") || "/usr/lib/shani-shell/pdfform.py"
    readonly property string folder: (Quickshell.env("XDG_DOCUMENTS_DIR") || (Quickshell.env("HOME") + "/Documents")) + "/Scans"

    function refreshDevices() { looking = true; error = ""; deviceProc.running = true; }
    Process {
        id: deviceProc
        command: ["scanimage", "-f", "%d\t%v %m%n"]
        stdout: StdioCollector {
            onStreamFinished: {
                win.devices = text.split("\n").filter(l => l.indexOf("\t") > 0).map(l => ({ id: l.split("\t")[0], name: l.split("\t")[1].trim() }));
                if (win.devices.length && !win.devices.some(d => d.id === win.device))
                    win.device = win.devices[0].id;
            }
        }
        onExited: win.looking = false
    }
    // killing the process fires onExited; cancelled keeps it from overwriting
    // the note we already gave for a Cancel or a watchdog timeout
    function stopScan(note) {
        watchdog.stop();
        cancelled = true;
        scanProc.running = false;
        scanning = false;
        if (note) error = note;
    }
    function scan() {
        if (device === "" || scanning)
            return;
        scanning = true;
        cancelled = false;
        error = "";
        const ext = format === "jpeg" ? "jpg" : format;
        const out = folder + "/Scan " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HH.mm.ss") + "." + ext;
        scanProc.target = out;
        scanProc.pdf = format === "pdf";
        if (format === "pdf") {
            const png = out.slice(0, -4) + ".png";
            scanProc.command = ["sh", "-c",
                'mkdir -p "${5%/*}" && scanimage --device-name="$1" --resolution="$2" --format=png --output-file="$5.part" && mv -f "$5.part" "$5" && python3 "$4" topdf "$3" "$5" && rm -f "$5"',
                "sh", device, String(resolution), pdfTool, out, png];
        } else {
            scanProc.command = ["sh", "-c", 'mkdir -p "${4%/*}" && scanimage --device-name="$1" --resolution="$2" --format="$3" --output-file="$4.part" && mv -f "$4.part" "$4"',
                                "sh", device, String(resolution), format, out];
        }
        watchdog.restart();
        scanProc.running = true;
    }
    Process {
        id: scanProc
        property string target: ""
        property bool pdf: false
        stderr: StdioCollector { id: scanErr }
        onExited: code => {
            if (win.cancelled) return;
            watchdog.stop();
            win.scanning = false;
            if (code === 0) win.lastScan = scanProc.target;
            else win.error = scanProc.pdf ? Tr.t("Could not make the PDF; the PNG scan was kept (PyMuPDF may be missing)")
                                          : Tr.t("The scanner reported a problem");
        }
    }
    Timer {
        id: watchdog
        interval: 120000
        onTriggered: win.stopScan(Tr.t("The scan took too long and was stopped"))
    }
    Component.onCompleted: refreshDevices()

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.scanner = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            spacing: Theme.px(8)

            SectionTitle { Layout.fillWidth: true; text: Tr.t("Scanner") }

            // ---- the scanners there are to choose from ----
            Flickable {
                id: deviceList
                Layout.fillWidth: true
                // one device is a row; a dozen must scroll rather than eat the window.
                // the content is never shorter than the view, so the states below
                // (looking, none found) centre in what is on screen
                Layout.preferredHeight: Math.max(Theme.px(44), Math.min(Theme.px(200), deviceCol.implicitHeight))
                contentHeight: Math.max(height, deviceCol.implicitHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: deviceCol
                    width: deviceList.width
                    spacing: Theme.px(2)
                    Repeater {
                        model: win.devices
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "scanner"
                            title: modelData.name
                            subtitle: modelData.id
                            selected: win.device === modelData.id
                            trailing: win.device === modelData.id ? Tr.t("Chosen") : ""
                            onClicked: { win.device = modelData.id; win.error = ""; }
                        }
                    }
                }
                BusyNote {
                    anchors.centerIn: parent
                    visible: win.looking
                    note: Tr.t("Looking…")
                    iconSize: Theme.px(16)
                }
                EmptyState {
                    anchors.centerIn: parent
                    width: deviceList.width - Theme.px(32)
                    visible: !win.looking && win.devices.length === 0
                    icon: "scanner"
                    subtitle: Tr.t("No scanner found. Plug one in or turn it on; a network scanner needs to be on the same Wi-Fi.")
                }
            }

            // ---- the resolution and the file type, a chip each ----
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [[150, Tr.t("Text · 150 dpi")], [300, Tr.t("Documents · 300 dpi")], [600, Tr.t("Photos · 600 dpi")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.resolution === modelData[0]
                        onClicked: { win.resolution = modelData[0]; win.error = ""; }
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [["png", "PNG"], ["jpeg", "JPEG"], ["pdf", "PDF"], ["tiff", "TIFF"]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.format === modelData[0]
                        onClicked: { win.format = modelData[0]; win.error = ""; }
                    }
                }
            }

            // the last scan, to look at
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Theme.px(80)
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.stroke
                clip: true
                Image {
                    anchors.fill: parent
                    anchors.margins: Theme.px(8)
                    visible: win.lastScan !== "" && !win.lastScan.endsWith(".pdf")
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize: Qt.size(800, 800)
                    source: visible ? "file://" + win.lastScan.split("/").map(encodeURIComponent).join("/") : ""
                }
                BusyNote {
                    anchors.centerIn: parent
                    visible: win.scanning
                    note: Tr.t("Scanning…")
                    iconSize: Theme.px(28)
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: !win.scanning && (win.lastScan === "" || win.lastScan.endsWith(".pdf"))
                    icon: "scanner"
                    title: win.lastScan === "" ? Tr.t("Nothing scanned yet") : win.lastScan.split("/").pop()
                    subtitle: win.lastScan === "" ? Tr.t("Scans are kept in Documents/Scans") : ""
                }
            }

            Text {
                Layout.fillWidth: true
                visible: win.error !== ""
                text: win.error
                color: Theme.danger
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.type("body")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button {
                    visible: win.lastScan !== ""
                    text: Tr.t("Open")
                    onClicked: Quickshell.execDetached(["gio", "open", win.lastScan])
                }
                Button {
                    visible: win.lastScan !== ""
                    flat: true
                    text: Tr.t("Show in Files")
                    onClicked: Services.Files.show(win.folder)
                }
                Button {
                    visible: win.scanning
                    flat: true
                    text: Tr.t("Cancel")
                    onClicked: win.stopScan(Tr.t("Scan cancelled"))
                }
                Item { Layout.fillWidth: true }
                Button {
                    kind: "primary"
                    text: win.scanning ? Tr.t("Scanning…") : Tr.t("Scan")
                    enabled: win.device !== "" && !win.scanning
                    onClicked: win.scan()
                }
            }
        }
    }
}
