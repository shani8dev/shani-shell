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
    visible: Ui.scanner
    onGone: Ui.scanner = false
    implicitWidth: 640
    implicitHeight: 620

    property var devices: []            // [{ id, name }]
    property string device: ""
    property int resolution: 300
    property string format: "png"
    property bool looking: false
    property bool scanning: false
    property string lastScan: ""
    property string error: ""
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
    function scan() {
        if (device === "" || scanning)
            return;
        scanning = true;
        error = "";
        const out = folder + "/Scan " + Qt.formatDateTime(new Date(), "yyyy-MM-dd hh.mm.ss") + "." + (format === "jpeg" ? "jpg" : format);
        scanProc.target = out;
        scanProc.command = ["sh", "-c", 'mkdir -p "${4%/*}" && scanimage --device-name="$1" --resolution="$2" --format="$3" --output-file="$4.part" && mv -f "$4.part" "$4"',
                            "sh", device, String(resolution), format, out];
        scanProc.running = true;
    }
    Process {
        id: scanProc
        property string target: ""
        stderr: StdioCollector { id: scanErr }
        onExited: code => {
            win.scanning = false;
            if (code === 0) win.lastScan = scanProc.target;
            else win.error = scanErr.text.trim().split("\n").pop() || Tr.t("The scanner did not answer");
        }
    }
    Component.onCompleted: refreshDevices()

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.scanner = false

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Scanner") }
                Text { visible: win.looking; text: Tr.t("Looking…"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
                IconButton { size: 28; icon: "view-refresh"; tip: Tr.t("Look again"); enabled: !win.looking; onClicked: win.refreshDevices() }
            }
            Repeater {
                model: win.devices
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: "scanner"
                    title: modelData.name
                    subtitle: modelData.id
                    trailing: win.device === modelData.id ? Tr.t("Chosen") : ""
                    onClicked: win.device = modelData.id
                }
            }
            Text {
                Layout.fillWidth: true
                visible: !win.looking && win.devices.length === 0
                text: Tr.t("No scanner found. Plug one in or turn it on; a network scanner needs to be on the same Wi-Fi.")
                color: Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [[150, Tr.t("Text · 150 dpi")], [300, Tr.t("Documents · 300")], [600, Tr.t("Photos · 600")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.resolution === modelData[0]
                        onClicked: win.resolution = modelData[0]
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [["png", "PNG"], ["jpeg", "JPEG"], ["pdf", "PDF"], ["tiff", "TIFF"]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.format === modelData[0]
                        onClicked: win.format = modelData[0]
                    }
                }
            }

            // the last scan, to look at
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: Theme.surface1
                clip: true
                Image {
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: win.lastScan !== "" && !win.lastScan.endsWith(".pdf")
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize: Qt.size(800, 800)
                    source: visible ? "file://" + win.lastScan.split("/").map(encodeURIComponent).join("/") : ""
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: win.lastScan === "" || win.lastScan.endsWith(".pdf")
                    icon: win.scanning ? "content-loading" : "scanner"
                    title: win.scanning ? Tr.t("Scanning…") : win.lastScan !== "" ? win.lastScan.split("/").pop() : Tr.t("Nothing scanned yet")
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
                font.pixelSize: 12 * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button { visible: win.lastScan !== ""; text: Tr.t("Open"); onClicked: Quickshell.execDetached(["gio", "open", win.lastScan]) }
                Button { visible: win.lastScan !== ""; flat: true; text: Tr.t("Show in Files"); onClicked: Services.Files.show(win.folder) }
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
