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
    spacing: Theme.px(12)
    property bool active: false
    property var info: ({})
    property string renameError: ""
    property bool hasCassini: false
    property var checks: []
    property string reportName: ""
    readonly property int passedChecks: page.checks.filter(c => c.ok).length
    readonly property real healthScore: page.checks.length ? page.passedChecks / page.checks.length : 0
    onActiveChanged: if (active) { facts.running = true; healthProc.running = true; }
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) { facts.running = true; healthProc.running = true; }

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
            echo "gpu=$(glxinfo -B 2>/dev/null | sed -n "s/^ *OpenGL renderer string: //p" | sed "s/ (.*)$//" | head -1)"
            echo "driver=$(lspci -nnk 2>/dev/null | grep -A3 "VGA compatible controller" | grep -m1 "Kernel driver in use:" | sed -n "s/.*Kernel driver in use: //p")"
            # what the card wants, so the driver is a name rather than a search
            echo "driverpkg=$(d=$(lspci -nnk 2>/dev/null | grep -A3 "VGA compatible controller" | grep -m1 "Kernel driver in use:" | sed -n "s/.*Kernel driver in use: //p"); case "$d" in nvidia) echo nvidia-open;; amdgpu|i915|xe) echo mesa;; *) echo "$d";; esac)"
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
    // Ananta Maintenance's health check, read-only and only while About is open.
    Process {
        id: healthProc
        command: ["python3", Quickshell.env("SHANI_HEALTH_TOOL") || "/usr/lib/shani-shell/health-check.py"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.checks = JSON.parse(text); } catch (e) { page.checks = []; } }
        }
    }
    // Ananta's problem report, made on demand and opened in our own editor so it
    // can be read and edited before anyone saves or copies it. Nothing is sent.
    Process {
        id: reportProc
        command: ["python3", Quickshell.env("SHANI_REPORT_TOOL") || "/usr/lib/shani-shell/system-report.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                const now = new Date();
                const p = n => ("0" + n).slice(-2);
                page.reportName = "shani-report-" + now.getFullYear() + p(now.getMonth() + 1) + p(now.getDate()) + "-" + p(now.getHours()) + p(now.getMinutes()) + ".txt";
                TextDocs.newDoc();
                TextDocs.setText(text);
                // a dated title rather than "Untitled": the buffer is memory-only
                if (TextDocs.current) { TextDocs.current.name = page.reportName; TextDocs.touch(); }
                TextDocs.revision++;
                Ui.closeAll();
                Ui.textEditor = true;
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

    SectionTitle { Layout.fillWidth: true; text: Tr.t("This computer") }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(14)
        Image {
            source: Theme.wallpaper ? "file://" + Theme.wallpaper : ""
            Layout.preferredWidth: Theme.px(96)
            Layout.preferredHeight: Theme.px(60)
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(192, 120)
            visible: status === Image.Ready
        }
        Image {
            source: "file:///usr/share/pixmaps/shani-logo.svg"
            Layout.preferredWidth: Theme.px(28)
            Layout.preferredHeight: Theme.px(28)
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(56, 56)
            visible: status === Image.Ready
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { text: page.info.host || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(18) * Theme.fontScale; font.weight: Font.DemiBold }
            Text { text: page.info.os || ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
            Text {
                text: [page.info.gpu, page.info.driver].filter(x => x).join(" · ")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                visible: text !== ""
            }
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Repeater {
            // from who uses it and what it is: "asha-laptop", "asha-pc"
            readonly property string who: (Quickshell.env("USER") || "my").toLowerCase().replace(/[^a-z0-9-]/g, "")
            model: [who + (Power.hasBattery ? "-laptop" : "-pc"), who + "-shani", "shani-" + (Power.hasBattery ? "laptop" : "desktop")]
            Choice {
                required property string modelData
                text: modelData
                onClicked: { rename.command = ["hostnamectl", "hostname", modelData]; rename.running = true; }
            }
        }
    }
    TextField {
        Layout.fillWidth: true
        id: hostnameField
        placeholder: Tr.t("Or another name - letters, digits and '-'")
        error: page.renameError
        onAccepted: {
            page.renameError = "";
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
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Theme.px(12)
        rowSpacing: Theme.px(6)
        Repeater {
            model: [["Processor", "cpu"], ["Graphics", "gpu"], ["Memory", "memory"], ["Disk", "disk"], ["Kernel", "kernel"], ["Desktop", "session"], ["Up for", "uptime"]]
            Text {
                required property var modelData
                required property int index
                Layout.row: index
                Layout.column: 0
                text: modelData[0]
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
        }
        Repeater {
            model: [["Processor", "cpu"], ["Graphics", "gpu"], ["Memory", "memory"], ["Disk", "disk"], ["Kernel", "kernel"], ["Desktop", "session"], ["Up for", "uptime"]]
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
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
        }
    }
    RowLayout {
        spacing: Theme.px(8)
        Button {
            text: Tr.t("Copy details")
            onClicked: Quickshell.clipboardText = [page.info.host, page.info.os, page.info.cpu, page.info.gpu, page.info.driver, page.info.driverpkg, page.info.memory, page.info.disk, page.info.kernel, page.info.session].filter(x => x).join("\n")
        }
        Button {
            text: Tr.t("Problem report…")
            enabled: !reportProc.running
            onClicked: reportProc.running = true
        }
        Button {
            text: Tr.t("Save report…")
            enabled: page.reportName !== ""
            onClicked: FilePicker.open({
                mode: "save", title: Tr.t("Save report…"), defaultName: page.reportName, filters: ["txt", "md"],
                onPicked: paths => { if (paths.length) TextDocs.saveAs(paths[0]); }
            })
        }
        Button {
            visible: page.hasCassini
            text: Tr.t("Open Cassini")
            onClicked: { Ui.closeAll(); Quickshell.execDetached(["shani-cassini"]); }
        }
    }
    // System health: one score, one line per check — Ananta Maintenance's checks
    // reduced to what a shell can read without touching anything.
    SectionTitle { Layout.fillWidth: true; text: Tr.t("System health") }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(16)
        StatusRing {
            value: page.healthScore
            color: !page.checks.length ? Theme.dim
                 : page.passedChecks === page.checks.length ? Theme.accent
                 : page.healthScore >= 0.5 ? Theme.amber : Theme.danger
            size: Theme.px(72)
            thickness: Theme.px(7)
            label: Tr.t("System health: %1 of %2 checks passed", page.passedChecks, page.checks.length)
            Text {
                anchors.centerIn: parent
                text: page.checks.length ? Math.round(page.healthScore * 100) + "%" : "–"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(18) * Theme.fontScale
                font.weight: Font.DemiBold
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.px(4)
            Repeater {
                model: page.checks
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    StatusGlyph { tone: modelData.ok ? "ok" : "error"; size: Theme.px(14) }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.title
                        color: Theme.text
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
                    Text {
                        text: modelData.detail
                        color: Theme.dim
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
            }
            Button {
                flat: true
                text: Tr.t("Run check again")
                busy: healthProc.running
                enabled: !healthProc.running
                onClicked: healthProc.running = true
            }
        }
    }
    // What these Settings leave to Cassini - each opens on its own page there,
    // so nothing is in both places
    SectionTitle { Layout.fillWidth: true; visible: page.hasCassini; text: Tr.t("More in Cassini") }
    Flow {
        Layout.fillWidth: true
        visible: page.hasCassini
        spacing: Theme.px(6)
        Repeater {
            model: [
                { label: Tr.t("Updates & going back"), id: "updates" },
                { label: Tr.t("Update channel: %1", Updates.channel === "latest" ? Tr.t("Latest") : Tr.t("Stable")), id: "update-channel" },
                { label: Tr.t("Firmware"), id: "firmware" },
                { label: Tr.t("Disk space & clean-up"), id: "maintenance" },
                { label: Tr.t("Disk health"), id: "smart" },
                { label: Tr.t("Encryption"), id: "encryption" },
                { label: Tr.t("Secure Boot"), id: "secureboot" },
                { label: Tr.t("Firewall"), id: "firewall" },
                { label: Tr.t("Services"), id: "services" },
                { label: Tr.t("Boot & recovery"), id: "boot" }]
            Choice {
                required property var modelData
                text: modelData.label
                onClicked: {
                    if (modelData.id === "update-channel") {
                        Updates.setChannel(Updates.channel === "latest" ? "stable" : "latest");
                    } else {
                        Ui.closeAll();
                        Quickshell.execDetached(["shani-cassini", "--section=" + modelData.id]);
                    }
                }
            }
        }
    }
}
