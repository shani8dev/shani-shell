// Scanner (Scanner): native QML surface for scanning documents.
// Replaces org.gnome.SimpleScan. Uses scanimage (SANE) for actual scanning.
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import qs.Common
import qs.Services as Services

PanelWindow {
    id: win
    visible: Ui.scanner && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Services.Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-scanner"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property var devices: []
    property string selectedDevice: ""
    property string resolution: "300"
    property string format: "png"
    property string lastScan: ""
    property bool scanning: false
    property string status: ""

    MouseArea { anchors.fill: parent; onClicked: Ui.scanner = false }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 600)
        height: Math.min(parent.height - 60, 550)
        radius: Theme.radiusLg

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Scanner"; font.bold: true; font.pixelSize: 18 }
                Button {
                    Layout.alignment: Qt.AlignRight
                    text: "✕"
                    flat: true
                    onClicked: Ui.scanner = false
                }
            }

            Label {
                text: win.status
                font.pixelSize: 11
                color: Theme.onSurfaceVariant
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            // Device selection
            Label { text: "Device:"; font.bold: true; font.pixelSize: 13 }
            ComboBox {
                Layout.fillWidth: true
                model: win.devices
                onCurrentIndexChanged: {
                    if (currentIndex >= 0) win.selectedDevice = win.devices[currentIndex];
                }
            }

            // Resolution
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: "Resolution:"; font.pixelSize: 12 }
                ComboBox {
                    Layout.preferredWidth: 120
                    model: ["75", "150", "300", "600", "1200"]
                    currentIndex: 2
                    onCurrentTextChanged: win.resolution = currentText
                }
                Label { text: "Format:"; font.pixelSize: 12 }
                ComboBox {
                    Layout.preferredWidth: 100
                    model: ["png", "jpeg", "tiff", "pdf"]
                    onCurrentTextChanged: win.format = currentText
                }
            }

            // Scan buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    Layout.fillWidth: true
                    text: win.scanning ? "Scanning..." : "Scan"
                    enabled: !win.scanning && win.selectedDevice !== ""
                    onClicked: win.doScan()
                }
                Button {
                    Layout.fillWidth: true
                    text: "Refresh devices"
                    onClicked: win.refreshDevices()
                }
            }

            // Last scan preview
            Label { text: "Last scan:"; font.bold: true; font.pixelSize: 13; visible: win.lastScan !== "" }
            Label {
                text: win.lastScan
                font.pixelSize: 11
                color: Theme.onSurfaceVariant
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                visible: win.lastScan !== ""
            }

            Button {
                Layout.fillWidth: true
                text: "Open last scan"
                visible: win.lastScan !== ""
                onClicked: Quickshell.execDetached(["gio", "open", win.lastScan])
            }

            Button { Layout.fillWidth: true; text: "Close"; onClicked: Ui.scanner = false }
        }
    }

    Process {
        id: deviceProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.trim());
                win.devices = lines.map(l => {
                    const m = l.match(/device `(.+?)' is (.+)/);
                    return m ? m[1] + " — " + m[2] : l;
                });
                win.status = "Found " + win.devices.length + " device(s)";
                if (win.devices.length > 0 && win.selectedDevice === "") {
                    win.selectedDevice = win.devices[0].split(" — ")[0];
                }
            }
        }
    }

    Process {
        id: scanProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    win.lastScan = text.trim();
                    win.status = "Scan complete: " + win.lastScan.split("/").pop();
                }
            }
        }
        onExited: (code, signal) => {
            win.scanning = false;
            if (code !== 0) win.status = "Scan failed (code " + code + ")";
        }
    }

    function refreshDevices() {
        win.status = "Discovering devices...";
        deviceProc.command = ["scanimage", "-L"];
        deviceProc.running = true;
    }

    function doScan() {
        win.scanning = true;
        win.status = "Scanning...";
        const outPath = "/tmp/scan-" + Date.now() + "." + win.format;
        scanProc.command = ["sh", "-c",
            'scanimage --device-name="$1" --resolution="$2" --format="$3" > "$4" 2>&1 && echo "$4"',
            "sh", win.selectedDevice.split(" — ")[0], win.resolution, win.format, outPath];
        scanProc.running = true;
    }

    Component.onCompleted: { win.refreshDevices(); }
    Keys.onEscapePressed: Ui.scanner = false
}