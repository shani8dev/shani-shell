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

    function go() {
        const t = input.text.trim();
        if (t === "" || working)
            return;
        working = true;
        error = "";
        runner.command = ["sh", "-c", 'printf "%s" "$1" | python3 "$2" text "$3"', "sh", t, win.tool, win.target];
        runner.running = true;
    }
    Process {
        id: runner
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            win.working = false;
            if (code === 0) win.result = out.text.trim();
            else win.error = code === 2 ? Tr.t("The local model is not running — Chronoa starts it") : Tr.t("Could not translate");
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.translate = false

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(10)
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
                                text: Tr.t("Type or paste text — Ctrl+Enter translates")
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
