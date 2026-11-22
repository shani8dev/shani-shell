// Translate: words from one language into another, on this computer - by
// Chronoa's local model (bridge/translate.py); nothing goes to the network.
// The languages are picks; the text is typed or pasted.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Translate"
    visible: Ui.translate
    onGone: Ui.translate = false
    implicitWidth: Theme.px(760)
    implicitHeight: Theme.px(540)

    readonly property string tool: Quickshell.env("SHANI_TRANSLATE_TOOL") || "/usr/lib/shani-shell/translate.py"
    property string target: Settings.data.translateTo || "en"
    readonly property var languages: [["en", "English"], ["hi", "हिन्दी"], ["mr", "मराठी"], ["bn", "বাংলা"], ["ta", "தமிழ்"], ["te", "తెలుగు"],
        ["gu", "ગુજરાતી"], ["kn", "ಕನ್ನಡ"], ["de", "Deutsch"], ["es", "Español"], ["fr", "Français"], ["ja", "Japanese"], ["zh", "Chinese"], ["ar", "Arabic"]]
    property string result: ""
    property string error: ""
    property bool working: false
    // source language, mode and the local model's endpoint
    property string source: "auto"
    property string mode: "text"            // text | batch | file
    property string endpoint: Quickshell.env("SHANI_TRANSLATE_URL") || "http://127.0.0.1:8765/v1/chat/completions"
    property string statusText: ""
    property bool statusOk: false
    property string batchCount: ""
    property string filePath: ""

    function swap() {
        if (source === "auto")
            return;
        const old = source;
        source = target;
        target = old;
        Settings.data.translateTo = target;
        if (input.text.trim() !== "") win.go();
    }
    function checkEndpoint() {
        statusText = Tr.t("Checking…");
        statusProc.command = ["sh", "-c", 'SHANI_TRANSLATE_URL="$1" python3 "$2" status', "sh", win.endpoint, win.tool];
        statusProc.running = true;
    }
    Process {
        id: statusProc
        stdout: StdioCollector {
            onStreamFinished: {
                win.statusOk = text.indexOf("ok") >= 0;
                win.statusText = win.statusOk ? Tr.t("Local model ready") : Tr.t("Local model not running");
            }
        }
    }
    // a file is read as-is; the bridge strips HTML when the file mode asks
    Process {
        id: fileProc
        stdout: StdioCollector {
            onStreamFinished: { input.text = text.trim(); win.go(); }
        }
    }
    function openFile() {
        FilePicker.open({
            mode: "open",
            filters: ["txt", "text", "html", "htm", "md"],
            title: Tr.t("A file to translate"),
            onPicked: paths => {
                if (!paths.length) return;
                win.filePath = paths[0];
                win.mode = /\.(html?|htm)$/i.test(paths[0]) ? "file" : "text";
                fileProc.command = ["cat", paths[0]];
                fileProc.running = true;
            }
        });
    }

    function go() {
        const t = input.text.trim();
        if (t === "" || working)
            return;
        working = true;
        error = "";
        result = "";
        if (win.mode === "batch") {
            const lines = t.split("\n").map(s => s.trim()).filter(s => s !== "");
            runner.command = ["sh", "-c", 'printf "%s" "$1" | python3 "$2" strings "$3"', "sh", JSON.stringify(lines), win.tool, win.target];
        } else {
            const cmd = win.mode === "file" ? "file" : "text";
            runner.command = ["sh", "-c", 'printf "%s" "$1" | python3 "$2" "$3" "$4" "$5" "$6"',
                              "sh", t, win.tool, cmd, win.target, win.source, win.mode === "file" ? "--html" : ""];
        }
        runner.running = true;
    }
    Process {
        id: runner
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            win.working = false;
            if (code === 0) {
                if (win.mode === "batch") {
                    win.batchCount = out.text.trim();
                    win.result = Tr.t("Added %1 translations", win.batchCount);
                } else win.result = out.text.trim();
                win.error = "";
            } else win.error = code === 2 ? Tr.t("The local model is not running — Chronoa starts it") : Tr.t("Could not translate");
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.translate = false

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(10)
            // ---- the local model endpoint and its status -----------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Text { text: Tr.t("Model"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                TextField {
                    id: endpointField
                    Layout.fillWidth: true
                    text: win.endpoint
                    label: Tr.t("Local model endpoint")
                    inputMethodHints: Qt.ImhUrlCharactersOnly
                    onAccepted: win.endpoint = text.trim()
                }
                Button { text: Tr.t("Use"); flat: true; onClicked: win.endpoint = endpointField.text.trim() }
                Button { text: Tr.t("Check"); flat: true; onClicked: win.checkEndpoint() }
                Text {
                    text: win.statusText
                    color: win.statusOk ? Theme.accent : Theme.danger
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
            }

            // ---- what kind of translation -------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Choice { text: Tr.t("Text"); selected: win.mode === "text"; onClicked: win.mode = "text" }
                Choice { text: Tr.t("Batch"); selected: win.mode === "batch"; onClicked: win.mode = "batch" }
                Choice { text: Tr.t("File / HTML"); selected: win.mode === "file"; onClicked: win.mode = "file" }
                Button { text: Tr.t("Open file…"); flat: true; onClicked: win.openFile() }
                Text { Layout.fillWidth: true; text: win.filePath.split("/").pop(); color: Theme.faint; elide: Text.ElideMiddle; font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale }
            }
            Text {
                Layout.fillWidth: true
                visible: win.mode === "batch"
                text: Tr.t("One string per line — cached translations are added to this computer")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }

            // ---- source language and swap --------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Text { text: Tr.t("From"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: [["auto", Tr.t("Auto")]].concat(win.languages)
                        Choice {
                            required property var modelData
                            text: modelData[1]
                            selected: win.source === modelData[0]
                            onClicked: { win.source = modelData[0]; if (input.text.trim() !== "") win.go(); }
                        }
                    }
                }
                IconButton { icon: "exchange-positions"; size: Theme.px(28); tip: Tr.t("Swap languages"); enabled: win.source !== "auto"; onClicked: win.swap() }
            }

            Text { text: Tr.t("Into"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: win.languages
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.target === modelData[0]
                        onClicked: { win.target = modelData[0]; Settings.data.translateTo = modelData[0]; if (input.text.trim() !== "") win.go(); }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.px(10)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    border.width: 1
                    border.color: input.activeFocus ? Theme.accent : Theme.border
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        contentHeight: input.implicitHeight
                        clip: true
                        TextEdit {
                            id: input
                            activeFocusOnTab: true          // the d-pad and Tab reach it (a pad's LB / RB leave it: Ui.navJump)
                            Keys.onDownPressed: e => e.accepted = Ui.leaveAtEdge(input, true)
                            Keys.onUpPressed: e => e.accepted = Ui.leaveAtEdge(input, false)
                            width: parent.width
                            wrapMode: TextEdit.Wrap
                            color: Theme.text
                            selectionColor: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: Theme.px(15) * Theme.fontScale
                            Accessible.role: Accessible.EditableText
                            Accessible.name: Tr.t("Text to translate")
                            Keys.onPressed: e => { if ((e.modifiers & Qt.ControlModifier) && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { win.go(); e.accepted = true; } }
                            onTextChanged: { if (win.result !== "") win.result = ""; }
                            Text {
                                visible: input.text === ""
                                text: win.mode === "batch" ? Tr.t("One string per line — Ctrl+Enter translates") : Tr.t("Type or paste text — Ctrl+Enter translates")
                                color: Theme.faint
                                font: input.font
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.surface2
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        contentHeight: outText.implicitHeight
                        clip: true
                        TextEdit {
                            id: outText
                            width: parent.width
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            text: win.error !== "" ? win.error : win.working ? Tr.t("Translating…") : win.result
                            color: win.error !== "" ? Theme.danger : Theme.text
                            selectionColor: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: Theme.px(15) * Theme.fontScale
                            Accessible.role: Accessible.StaticText
                            Accessible.name: Tr.t("Translation") + ": " + text
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: win.result === "" && win.error === "" && !win.working
                            text: Tr.t("Translation appears here")
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(13) * Theme.fontScale
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button { text: Tr.t("Paste"); flat: true; onClicked: { input.text = Quickshell.clipboardText || ""; win.go(); } }
                Button { text: Tr.t("Clear"); flat: true; onClicked: { input.text = ""; win.result = ""; win.error = ""; } }
                Item { Layout.fillWidth: true }
                Text { text: Tr.t("On this computer — nothing is sent anywhere"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Button { text: Tr.t("Copy"); enabled: win.result !== "" && win.error === ""; onClicked: Quickshell.clipboardText = win.result }
                Button { kind: "primary"; text: Tr.t("Translate"); enabled: input.text.trim() !== "" && !win.working; onClicked: win.go() }
            }
        }
    }
}
