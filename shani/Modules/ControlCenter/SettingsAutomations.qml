// Settings > Automations: "when this happens, do that" (Services/Automations).
// Each rule reads as a sentence and can be paused or removed; the form below
// adds one.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    readonly property var d: Settings.data
    readonly property var whens: [
        { id: "wifi", label: "Joining Wi-Fi", hint: "network name", ask: true },
        { id: "power", label: "Power", choices: ["plugged", "battery"] },
        { id: "output", label: "Sound output", hint: "name contains, e.g. headphones", ask: true },
        { id: "displays", label: "Screens", choices: ["1", "2", "3"] },
        { id: "time", label: "Time", hint: "HH:MM", ask: true }]
    readonly property var thens: [
        { id: "focus", label: "Focus mode", choices: () => page.d.focusModes.map(m => m.name).concat([""]) },
        { id: "dnd", label: "Do not disturb", choices: () => ["on", "off"] },
        { id: "volume", label: "Volume", hint: "percent", ask: true },
        { id: "style", label: "Style", choices: () => ["dark", "light"] },
        { id: "open", label: "Open app", hint: "desktop id, e.g. org.gnome.Calendar", ask: true },
        { id: "run", label: "Run command", hint: "shell command", ask: true }]

    function sentence(r) {
        const w = { wifi: "On joining " + r.is, power: r.is === "battery" ? "On battery" : "When plugged in",
                    output: "When sound goes to " + r.is, displays: "With " + r.is + " screen" + (r.is === "1" ? "" : "s"),
                    time: "At " + r.is }[r.when] || r.when;
        const t = { focus: r.arg ? "turn on " + r.arg : "end the focus mode", dnd: "turn Do not disturb " + r.arg,
                    volume: "set the volume to " + r.arg + "%", style: "use the " + r.arg + " style",
                    open: "open " + r.arg, run: "run " + r.arg }[r.then] || r.then;
        return w + ", " + t;
    }
    function setRules(list) { d.automations = list; }
    function rulesCopy() { return JSON.parse(JSON.stringify(Array.from(d.automations))); }

    SectionTitle { Layout.fillWidth: true; text: "When this happens, do that" }
    Text {
        visible: page.d.automations.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "No automations yet. A rule acts once, when its moment comes — joining the office Wi-Fi can turn on Work focus; plugging in headphones can set the volume."
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Repeater {
        model: page.d.automations
        RowLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            SwitchRow {
                Layout.fillWidth: true
                text: page.sentence(modelData)
                checked: modelData.on !== false
                onToggled: on => { const l = page.rulesCopy(); l[index].on = on; page.setRules(l); }
            }
            IconButton { icon: "edit-delete"; tip: "Remove"; onClicked: { const l = page.rulesCopy(); l.splice(index, 1); page.setRules(l); } }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: "Add an automation" }
    property string when: "wifi"
    property string is: ""
    property string then: "focus"
    property string arg: ""
    readonly property var w: whens.find(x => x.id === when)
    readonly property var t: thens.find(x => x.id === then)
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: page.whens
            Choice { required property var modelData; text: modelData.label; selected: page.when === modelData.id
                     onClicked: { page.when = modelData.id; page.is = modelData.choices ? modelData.choices[0] : ""; } }
        }
    }
    TextField {
        visible: !!page.w.ask
        Layout.fillWidth: true
        placeholder: page.w.hint || ""
        text: page.is
        id: isField
        Connections { target: isField.input; function onTextChanged() { page.is = isField.text.trim(); } }
    }
    Flow {
        visible: !page.w.ask
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: page.w.choices || []
            Choice { required property string modelData; text: modelData; selected: page.is === modelData; onClicked: page.is = modelData }
        }
    }
    Text { text: "then"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: page.thens
            Choice { required property var modelData; text: modelData.label; selected: page.then === modelData.id
                     onClicked: { page.then = modelData.id; page.arg = modelData.choices ? modelData.choices()[0] : ""; } }
        }
    }
    TextField {
        visible: !!page.t.ask
        Layout.fillWidth: true
        placeholder: page.t.hint || ""
        id: argField
        text: page.arg
        Connections { target: argField.input; function onTextChanged() { page.arg = argField.text.trim(); } }
    }
    Flow {
        visible: !page.t.ask
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: page.t.choices ? page.t.choices() : []
            Choice { required property string modelData; text: modelData || "(none)"; selected: page.arg === modelData; onClicked: page.arg = modelData }
        }
    }
    Button {
        text: "Add"
        kind: "primary"
        enabled: page.is !== "" && (page.arg !== "" || page.then === "focus")
        onClicked: {
            page.setRules(page.rulesCopy().concat([{ when: page.when, is: page.is, then: page.then, arg: page.arg, on: true }]));
            page.is = page.w.choices ? page.w.choices[0] : "";
            page.arg = page.t.choices ? page.t.choices()[0] : "";
        }
    }
}
