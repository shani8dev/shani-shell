// Settings > About: this computer — its name (which an administrator can
// change here, through hostnamed and the polkit agent), the system, the
// hardware — and Cassini for everything an administrator does beyond it.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    property var info: ({})
    property string renameError: ""
    property bool hasCassini: false
    onActiveChanged: if (active) facts.running = true

    // one line each: key=value
    Process {
        id: facts
        command: ["sh", "-c", '. /etc/os-release 2>/dev/null
            echo "os=${PRETTY_NAME:-Linux}"
            echo "host=$(hostnamectl hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || uname -n)"
            echo "kernel=$(uname -r)"
            echo "cpu=$(sed -n "s/^model name\\s*: //p" /proc/cpuinfo | head -1) × $(nproc)"
            echo "memory=$(awk "/MemTotal/{printf \\"%.1f GiB\\", \\$2/1048576}" /proc/meminfo)"
            echo "disk=$(df -h --output=avail,size / | tail -1 | awk "{print \\$1 \\" free of \\" \\$2}")"
            echo "uptime=$(uptime -p 2>/dev/null | sed "s/^up //")"
            echo "session=niri $(niri --version 2>/dev/null | cut -d" " -f2) · Quickshell $(qs --version 2>/dev/null | head -1 | grep -o "[0-9][0-9.]*" | head -1)"
            command -v shani-cassini >/dev/null && echo "cassini=yes"']
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {};
                text.trim().split("\n").forEach(l => { const i = l.indexOf("="); if (i > 0) kv[l.slice(0, i)] = l.slice(i + 1); });
                page.info = kv;
                page.hasCassini = kv.cassini === "yes";
            }
        }
    }
    Process {
        id: rename
        stderr: StdioCollector { id: renameErr }
        onExited: code => {
            page.renameError = code === 0 ? "" : (renameErr.text.trim().split("\n").pop() || "not changed");
            facts.running = true;
        }
    }

    SectionTitle { Layout.fillWidth: true; text: "This computer" }
    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        Image {
            source: "file:///usr/share/backgrounds/shani/shani-shell.png"
            Layout.preferredWidth: 96
            Layout.preferredHeight: 60
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(192, 120)
            visible: status === Image.Ready
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { text: page.info.host || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 18 * Theme.fontScale; font.weight: Font.DemiBold }
            Text { text: page.info.os || ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
        }
    }
    TextField {
        Layout.fillWidth: true
        placeholder: "Rename this computer (as others see it on the network)"
        onAccepted: {
            const n = text.trim();
            if (!/^[A-Za-z0-9][A-Za-z0-9-]{0,62}$/.test(n)) {
                page.renameError = "letters, digits and '-' only, up to 63";
                return;
            }
            rename.command = ["hostnamectl", "hostname", n];
            rename.running = true;
            text = "";
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.renameError !== ""
        text: page.renameError
        color: Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 12
        rowSpacing: 6
        Repeater {
            model: [["Processor", "cpu"], ["Memory", "memory"], ["Disk", "disk"], ["Kernel", "kernel"], ["Desktop", "session"], ["Up for", "uptime"]]
            Text {
                required property var modelData
                required property int index
                Layout.row: index
                Layout.column: 0
                text: modelData[0]
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
            }
        }
        Repeater {
            model: [["Processor", "cpu"], ["Memory", "memory"], ["Disk", "disk"], ["Kernel", "kernel"], ["Desktop", "session"], ["Up for", "uptime"]]
            Text {
                required property var modelData
                required property int index
                Layout.row: index
                Layout.column: 1
                Layout.fillWidth: true
                text: page.info[modelData[1]] || "—"
                color: Theme.text
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
            }
        }
    }
    RowLayout {
        spacing: 8
        Button {
            text: "Copy details"
            onClicked: Quickshell.clipboardText = [page.info.host, page.info.os, page.info.cpu, page.info.memory, page.info.disk, page.info.kernel, page.info.session].filter(x => x).join("\n")
        }
        Button {
            visible: page.hasCassini
            text: "Open Cassini"
            onClicked: { Ui.closeAll(); Quickshell.execDetached(["shani-cassini"]); }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.hasCassini
        text: "Cassini manages the rest: storage, boot and security, updates, services, backup."
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
