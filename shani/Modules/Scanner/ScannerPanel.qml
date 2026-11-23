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
            else win.error = Tr.t("The scanner reported a problem");
        }
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
                            onClicked: win.device = modelData.id
                        }
                    }
                }
                RowLayout {
                    anchors.centerIn: parent
                    visible: win.looking
                    spacing: Theme.px(8)
                    Spinner { size: Theme.px(16) }
                    Text {
                        text: Tr.t("Looking…")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
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
                        onClicked: win.resolution = modelData[0]
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
                        onClicked: win.format = modelData[0]
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
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: win.scanning
                    spacing: Theme.px(8)
                    Spinner { Layout.alignment: Qt.AlignHCenter; size: Theme.px(28) }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Tr.t("Scanning…")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
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
                font.pixelSize: Theme.px(12) * Theme.fontScale
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
