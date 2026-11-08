// LocalSend (LocalSend): native QML surface for network file transfers between nearby devices.
// Replaces org.localsend.localsend_app. Uses HTTP + simple UDP discovery (no external deps).
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
    visible: Ui.localSend && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Services.Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-localsend"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property var peers: []
    property string currentFile: ""
    property string status: ""
    property bool receiving: false
    property int httpPort: 53317
    property string localIP: ""

    MouseArea {
        anchors.fill: parent;
        onClicked: Ui.localSend = false
    }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 500)
        height: Math.min(parent.height - 60, 450)
        radius: Theme.radiusLg

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Label { text: "LocalSend"; font.bold: true; font.pixelSize: 18 }
                Button {
                    Layout.alignment: Qt.AlignRight
                    text: "✕"
                    flat: true
                    onClicked: Ui.localSend = false
                }
            }

            // Status
            Label {
                text: win.status
                font.pixelSize: 11
                color: Theme.onSurfaceVariant
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            // Send section
            Label { text: "Send a file"; font.bold: true; font.pixelSize: 14 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    Layout.fillWidth: true
                    placeholderText: "No file selected"
                    text: win.currentFile ? win.currentFile.split("/").pop() : ""
                    readOnly: true
                }
                Button { text: "Choose…"; onClicked: fileDialog.open() }
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                clip: true
                model: win.peers
                delegate: ItemDelegate {
                    width: parent.width
                    text: modelData.name + " (" + modelData.ip + ")"
                    onClicked: sendFile(modelData.ip, modelData.port)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    Layout.fillWidth: true
                    text: "Refresh peers"
                    onClicked: discoverPeers()
                }
                Button {
                    Layout.fillWidth: true
                    text: win.currentFile ? "Send to selected" : "Select file first"
                    enabled: win.currentFile !== "" && win.peers.length > 0
                    onClicked: sendFile(win.peers[0].ip, win.peers[0].port)
                }
            }

            // Receive section
            Label { text: "Receive files"; font.bold: true; font.pixelSize: 14 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    Layout.fillWidth: true
                    text: win.receiving ? "Stop receiving" : "Start receiving"
                    onClicked: toggleReceiving()
                }
                Label {
                    text: win.receiving ? "Listening on " + win.localIP + ":" + win.httpPort : ""
                    font.pixelSize: 11
                    color: Theme.onSurfaceVariant
                }
            }

            Button { Layout.fillWidth: true; text: "Close"; onClicked: Ui.localSend = false }
        }
    }

    FileDialog {
        id: fileDialog
        title: "Choose file to send"
        onAccepted: {
            win.currentFile = fileDialog.selectedFile.toString().replace("file://", "");
            win.status = "Selected: " + win.currentFile.split("/").pop();
        }
    }

    // Process to run Python discovery/transfer script
    Process {
        id: localSendProc
        running: false
        onExited: (code, signal) => {
            if (code === 0 && localSendProc.stdout) {
                const out = localSendProc.stdout.trim();
                if (out) {
                    try {
                        win.peers = JSON.parse(out);
                        win.status = "Found " + win.peers.length + " device(s)";
                    } catch (e) {
                        win.status = "Discovery error: " + e.message;
                    }
                }
            }
        }
    }

    Process {
        id: sendProc
        property string targetIP: ""
        property string targetPort: ""
        property string filePath: ""
        running: false
        onExited: (code, signal) => {
            win.status = code === 0 ? "File sent successfully!" : "Send failed (code " + code + ")";
        }
    }

    Process {
        id: receiveProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (text && text.startsWith("RECEIVED:")) {
                    const parts = text.split(":");
                    win.status = "Received: " + parts[1] + " saved to " + parts[2];
                }
            }
        }
    }

    function discoverPeers() {
        win.status = "Discovering peers...";
        // Use Python UDP broadcast for peer discovery
        localSendProc.command = [
            "python3", "-c",
            `import socket, json, time, subprocess, os
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sock.settimeout(2.0)

# Send discovery broadcast
msg = json.dumps({"type": "localsend-discover", "version": "1"}).encode()
for _ in range(3):
    sock.sendto(msg, ("<broadcast>", 53317))

peers = []
start = time.time()
while time.time() - start < 3:
    try:
        data, addr = sock.recvfrom(1024)
        info = json.loads(data.decode())
        if info.get("type") == "localsend-announce":
            peers.append({"name": info.get("name", addr[0]), "ip": addr[0], "port": info.get("port", 53317)})
    except socket.timeout:
        break
    except:
        pass

print(json.dumps(peers))`
        ];
        localSendProc.running = true;
    }

    function sendFile(ip, port) {
        if (win.currentFile === "") return;
        win.status = "Sending to " + ip + "...";
        sendProc.targetIP = ip;
        sendProc.targetPort = port;
        sendProc.filePath = win.currentFile;
        sendProc.command = [
            "python3", "-c",
            `import sys, requests, os, json
ip = sys.argv[1]
port = int(sys.argv[2])
filepath = sys.argv[3]
filename = os.path.basename(filepath)

# Try HTTPS first, fallback to HTTP
for proto in ["https", "http"]:
    try:
        url = f"{proto}://{ip}:{port}/api/localsend/v2/send"
        with open(filepath, "rb") as f:
            files = {"file": (filename, f)}
            data = {"filename": filename, "size": os.path.getsize(filepath)}
            r = requests.post(url, files=files, data=data, verify=False, timeout=30)
            if r.status_code == 200:
                print("OK")
                sys.exit(0)
    except:
        pass
sys.exit(1)`, "sh", ip, port, win.currentFile
        ];
        sendProc.running = true;
    }

    function toggleReceiving() {
        if (win.receiving) {
            // Stop receiving
            win.receiving = false;
            receiveProc.command = ["pkill", "-f", "localsend-receive"];
            receiveProc.running = true;
            win.status = "Stopped receiving";
        } else {
            // Start receiving - need to get local IP
            const ipProc = Quickshell.runCommand(["sh", "-c", "ip route get 1.1.1.1 | grep -oP 'src \\K\\S+'"]);
            ipProc.finished.connect(() => {
                win.localIP = ipProc.stdout.trim();
                if (win.localIP) {
                    startReceiveServer();
                }
            });
        }
    }

    function startReceiveServer() {
        win.receiving = true;
        // Python HTTP server for receiving files
        receiveProc.command = [
            "python3", "-c",
            `import sys, os, json, http.server, ssl, socketserver, threading, urllib.parse, tempfile, shutil
port = int(sys.argv[1])
save_dir = os.path.expanduser("~/Downloads/LocalSend")

os.makedirs(save_dir, exist_ok=True)

class LocalSendHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/api/localsend/v2/send":
            length = int(self.headers.get("Content-Length", 0))
            ctype = self.headers.get("Content-Type", "")
            
            if "multipart/form-data" in ctype:
                boundary = ctype.split("boundary=")[1].encode()
                data = self.rfile.read(length)
                
                parts = data.split(b"--" + boundary)
                for part in parts:
                    if b"filename=" in part:
                        # Extract filename
                        header_end = part.find(b"\\r\\n\\r\\n")
                        if header_end >= 0:
                            headers = part[:header_end].decode()
                            filedata = part[header_end+4:-2]  # remove \\r\\n and trailing \\r\\n
                            filename = None
                            for line in headers.split("\\r\\n"):
                                if "filename=" in line:
                                    filename = line.split('filename="')[1].split('"')[0]
                                    break
                            if filename:
                                filepath = os.path.join(save_dir, filename)
                                with open(filepath, "wb") as f:
                                    f.write(filedata)
                                print(f"RECEIVED:{filename}:{filepath}")
                                self.send_response(200)
                                self.send_header("Content-Type", "application/json")
                                self.end_headers()
                                self.wfile.write(b'{"success": true}')
                                return
            self.send_response(400)
            self.end_headers()

    def log_message(self, format, *args):
        pass

# Use ThreadingHTTPServer for concurrent handling
with socketserver.ThreadingTCPServer(("", port), LocalSendHandler) as httpd:
    # Allow address reuse
    httpd.allow_reuse_address = True
    print(f"SERVER_STARTED:{port}")
    httpd.serve_forever()
`, str(win.httpPort)
        ];
        receiveProc.running = true;
    }

    Component.onCompleted: {
        discoverPeers();
    }

    Keys.onEscapePressed: Ui.localSend = false
}