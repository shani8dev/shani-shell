// Settings > Default apps > Developer tools: the everyday command-line tools,
// with a one-click install for the ones that are missing. Each row checks for
// its binary itself, so the page is right whatever a machine already has.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Developer tools") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("Quick install of common tools. Installing asks for your password (pkexec) and uses this system's package manager.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
        wrapMode: Text.Wrap
    }

    Repeater {
        model: [
            { name: "git", cmd: "git", pkg: "git" },
            { name: "Node.js", cmd: "node", pkg: "nodejs" },
            { name: "Python", cmd: "python3", pkg: "python" },
            { name: "Docker", cmd: "docker", pkg: "docker" },
            { name: "mise", cmd: "mise", pkg: "mise" },
            { name: "Neovim", cmd: "nvim", pkg: "neovim" },
            { name: "ripgrep", cmd: "rg", pkg: "ripgrep" },
            { name: "fd", cmd: "fd", pkg: "fd" }
        ]
        delegate: ColumnLayout {
            id: tool
            required property var modelData
            Layout.fillWidth: true
            spacing: 4
            property bool installed: false
            property string note: ""

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: tool.modelData.name
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                }
                Button {
                    text: tool.installed ? Tr.t("Installed") : Tr.t("Install")
                    kind: tool.installed ? "plain" : "primary"
                    enabled: !tool.installed
                    onClicked: {
                        tool.note = "";
                        install.command = ["sh", "-c",
                            'p=$(command -v pacman && echo pacman || command -v apt-get && echo apt || command -v dnf && echo dnf); ' +
                            'case "$p" in *pacman*) pkexec pacman -S --needed --noconfirm ' + tool.modelData.pkg + ';; ' +
                            '*apt*) pkexec apt-get install -y ' + tool.modelData.pkg + ';; ' +
                            '*dnf*) pkexec dnf install -y ' + tool.modelData.pkg + ';; ' +
                            '*) echo "No known package manager (pacman, apt, dnf)." ;; esac'];
                        install.running = true;
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: tool.note !== ""
                text: tool.note
                color: Theme.danger
                wrapMode: Text.Wrap
                font.family: Theme.monoFont || Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }

            // is it here? one look, when the row is made
            Process {
                running: true
                command: ["sh", "-c", "command -v " + tool.modelData.cmd + " >/dev/null 2>&1 && echo yes || echo no"]
                stdout: StdioCollector { onStreamFinished: tool.installed = text.trim() === "yes" }
            }
            // and again after an install, so the row settles
            Process {
                id: install
                stdout: StdioCollector { onStreamFinished: { const t = text.trim(); if (t) tool.note = t; } }
                onExited: Qt.callLater(function() { tool.installed = false; checkAgain.running = true; })
            }
            Process {
                id: checkAgain
                command: ["sh", "-c", "command -v " + tool.modelData.cmd + " >/dev/null 2>&1 && echo yes || echo no"]
                stdout: StdioCollector { onStreamFinished: tool.installed = text.trim() === "yes" }
            }
        }
    }
}