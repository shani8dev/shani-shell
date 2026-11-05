// Settings > Keyboard & input > Gaming mouse: what libratbag can set on the mouse
// itself - its DPI presets (from the mouse's own list), the polling rate, and what
// each button does. Shown only when ratbagctl lists a device (bridge/ratbag.py);
// asked when the category opens, never in the background. The mouse keeps these
// in its own memory, so they go with it to another computer.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    visible: devices.length > 0
    readonly property string tool: Quickshell.env("SHANI_RATBAG_TOOL") || "/usr/lib/shani-shell/ratbag.py"
    property var devices: []
    property string note: ""

    function refresh() { probe.running = true; }
    onActiveChanged: if (active) refresh()
    Component.onCompleted: if (active) refresh()
    Process {
        id: probe
        command: ["python3", page.tool, "probe"]
        stdout: StdioCollector { onStreamFinished: { try { page.devices = JSON.parse(text).devices || []; } catch (e) { page.devices = []; } } }
    }
    Process {
        id: apply
        stdout: StdioCollector { id: setOut }
        onExited: code => {
            let r = {};
            try { r = JSON.parse(setOut.text); } catch (e) {}
            page.note = code === 0 ? "" : Tr.t("The mouse did not take it (%1).", r.error || code);
            probe.running = true;
        }
    }
    function change(args) {
        if (apply.running)
            return;
        apply.command = ["python3", page.tool].concat(args.map(String));
        apply.running = true;
    }

    // a button's choices, by what people call them; keys too, from a short list
    readonly property var actions: [{ label: Tr.t("Left click"), value: "left" }, { label: Tr.t("Right click"), value: "right" },
        { label: Tr.t("Middle click"), value: "middle" }, { label: Tr.t("Back"), value: "back" },
        { label: Tr.t("Forward"), value: "forward" }, { label: Tr.t("A key…"), value: "key" }, { label: Tr.t("Nothing"), value: "disabled" }]
    readonly property var keys: [{ label: Tr.t("Volume up"), value: "key:KEY_VOLUMEUP" }, { label: Tr.t("Volume down"), value: "key:KEY_VOLUMEDOWN" },
        { label: Tr.t("Mute"), value: "key:KEY_MUTE" }, { label: Tr.t("Play / pause"), value: "key:KEY_PLAYPAUSE" },
        { label: Tr.t("Next track"), value: "key:KEY_NEXTSONG" }, { label: Tr.t("Page up"), value: "key:KEY_PAGEUP" },
        { label: Tr.t("Page down"), value: "key:KEY_PAGEDOWN" }, { label: Tr.t("Escape"), value: "key:KEY_ESC" },
        { label: Tr.t("Enter"), value: "key:KEY_ENTER" }, { label: Tr.t("Super"), value: "key:KEY_LEFTMETA" }]
    function buttonName(i) { return [Tr.t("Left button"), Tr.t("Right button"), Tr.t("Middle button (wheel)"), Tr.t("Back side button"), Tr.t("Forward side button")][i] || Tr.t("Button %1", i + 1); }
    function actionLabel(a) {
        const k = page.keys.find(x => x.value === a);
        if (k) return Tr.t("Key: %1", k.label);
        const o = page.actions.find(x => x.value === a);
        return o ? o.label : a.replace(/^key:KEY_/, Tr.t("Key: "));
    }
    property int openButton: -1           // the button whose choices are shown
    property bool keyPicking: false

    Repeater {
        model: page.devices
        ColumnLayout {
            id: dev
            required property var modelData
            Layout.fillWidth: true
            spacing: 10
            SectionTitle { Layout.fillWidth: true; text: Tr.t("Gaming mouse") }
            ListRow { Layout.fillWidth: true; icon: "input-mouse"; title: dev.modelData.name; subtitle: Tr.t("Settings are kept in the mouse itself") }
            Picks {
                label: Tr.t("Pointer speed (DPI)")
                options: dev.modelData.dpis
                current: dev.modelData.dpi
                onPicked: v => page.change(["dpi", dev.modelData.id, v])
            }
            Picks {
                visible: dev.modelData.rates.length > 1
                label: Tr.t("Polling rate - higher is smoother, lower saves battery")
                options: dev.modelData.rates.map(r => ({ label: r + " Hz", value: r }))
                current: dev.modelData.rate
                onPicked: v => page.change(["rate", dev.modelData.id, v])
            }
            Text { text: Tr.t("Buttons"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
            Repeater {
                model: dev.modelData.buttons
                ColumnLayout {
                    id: btn
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 4
                    ListRow {
                        Layout.fillWidth: true
                        icon: "input-mouse"
                        title: page.buttonName(btn.modelData.index)
                        subtitle: page.actionLabel(btn.modelData.action)
                        selected: page.openButton === btn.modelData.index
                        onClicked: { page.keyPicking = false; page.openButton = page.openButton === btn.modelData.index ? -1 : btn.modelData.index; }
                    }
                    Picks {
                        // made only for the open button: hidden copies would still be there to a screen reader
                        visible: page.openButton === btn.modelData.index
                        options: visible ? page.actions : []
                        current: page.keyPicking || btn.modelData.action.indexOf("key:") === 0 ? "key" : btn.modelData.action
                        onPicked: v => {
                            if (v === "key") { page.keyPicking = true; return; }
                            page.keyPicking = false;
                            page.change(["button", dev.modelData.id, btn.modelData.index, v]);
                        }
                    }
                    Picks {
                        visible: page.openButton === btn.modelData.index && (page.keyPicking || btn.modelData.action.indexOf("key:") === 0)
                        label: Tr.t("The key it presses")
                        options: visible ? page.keys : []
                        current: btn.modelData.action
                        onPicked: v => { page.keyPicking = false; page.change(["button", dev.modelData.id, btn.modelData.index, v]); }
                    }
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.note !== ""
        text: page.note
        color: Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
}
