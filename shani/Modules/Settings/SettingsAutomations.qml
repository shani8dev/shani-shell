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
        { id: "wifi", label: Tr.t("Joining Wi-Fi"), hint: Tr.t("network name"), ask: true },
        { id: "power", label: Tr.t("Power"), choices: ["plugged", "battery"] },
        { id: "output", label: Tr.t("Sound output"), hint: Tr.t("name contains, e.g. headphones"), ask: true },
        { id: "displays", label: Tr.t("Screens"), choices: ["1", "2", "3"] },
        { id: "time", label: Tr.t("Time"), hint: Tr.t("HH:MM"), ask: true }]
    readonly property var thens: [
        { id: "focus", label: Tr.t("Focus mode"), choices: () => page.d.focusModes.map(m => m.name).concat([""]) },
        { id: "dnd", label: Tr.t("Do not disturb"), choices: () => ["on", "off"] },
        { id: "volume", label: Tr.t("Volume"), hint: Tr.t("percent"), ask: true },
        { id: "style", label: Tr.t("Style"), choices: () => ["dark", "light"] },
        { id: "open", label: Tr.t("Open app"), hint: Tr.t("desktop id, e.g. org.gnome.Calendar"), ask: true },
        { id: "run", label: Tr.t("Run command"), hint: Tr.t("shell command"), ask: true }]

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

    SectionTitle { Layout.fillWidth: true; text: Tr.t("When this happens, do that") }
    Text {
        visible: page.d.automations.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: Tr.t("No automations yet. A rule acts once, when its moment comes — joining the office Wi-Fi can turn on Work focus; plugging in headphones can set the volume.")
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
            IconButton { icon: "edit-delete"; tip: Tr.t("Remove"); onClicked: { const l = page.rulesCopy(); l.splice(index, 1); page.setRules(l); } }
        }
    }

    // your own commands on the shell's events (Services/Hooks); a field is kept
    // when Enter is pressed, emptied to remove it
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Run a command when…") }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Run my commands")
        hint: Tr.t("Each runs in a shell; $1 is the wallpaper, or true/false for dark style")
        checked: !!(Settings.data.hooks && Settings.data.hooks.enabled)
        onToggled: on => page.setHook("enabled", on)
    }
    Repeater {
        model: [{ key: "wallpaperChange", label: Tr.t("the wallpaper changes") }, { key: "darkModeChange", label: Tr.t("dark style turns on or off") },
                { key: "screenLock", label: Tr.t("the screen locks") }, { key: "screenUnlock", label: Tr.t("the screen unlocks") },
                { key: "startup", label: Tr.t("the desktop starts") }]
        RowLayout {
            id: hookRow
            required property var modelData
            Layout.fillWidth: true
            visible: !!(Settings.data.hooks && Settings.data.hooks.enabled)
            spacing: 8
            Text { text: hookRow.modelData.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; Layout.preferredWidth: 170 }
            TextField {
                Layout.fillWidth: true
                placeholder: (Settings.data.hooks && Settings.data.hooks[hookRow.modelData.key]) || Tr.t("a command, e.g. notify-send Locked")
                onAccepted: { page.setHook(hookRow.modelData.key, text.trim()); text = ""; }
            }
        }
    }
    function setHook(key, value) {
        const h = Object.assign({}, Settings.data.hooks || {});
        h[key] = value;
        Settings.data.hooks = h;          // a new object: the settings file is written
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Add an automation") }
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
    // Wi-Fi name: pick from saved networks, or type
    ColumnLayout {
        visible: page.when === "wifi"
        Layout.fillWidth: true
        spacing: 6
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: Net.networks.map(n => n.name)
                Choice {
                    required property string modelData
                    text: modelData
                    selected: page.is === modelData
                    onClicked: page.is = modelData
                }
            }
        }
        TextField {
            id: typed1
            Layout.fillWidth: true
            placeholder: Tr.t("Or type a network name")
            text: page.is
            Connections { target: typed1.input; function onTextChanged() { page.is = typed1.text.trim(); } }
        }
    }
    // Power: chips
    Flow {
        visible: page.when === "power"
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: ["plugged", "battery"]
            Choice { required property string modelData; text: modelData === "plugged" ? Tr.t("Plugged in") : Tr.t("On battery"); selected: page.is === modelData; onClicked: page.is = modelData }
        }
    }
    // Sound output: pick from devices, or type
    ColumnLayout {
        visible: page.when === "output"
        Layout.fillWidth: true
        spacing: 6
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: Audio.sinks.map(o => Audio.nodeName(o))
                Choice {
                    required property string modelData
                    text: modelData
                    selected: page.is === modelData
                    onClicked: page.is = modelData
                }
            }
        }
        TextField {
            id: typed2
            Layout.fillWidth: true
            placeholder: Tr.t("Or type part of a device name")
            text: page.is
            Connections { target: typed2.input; function onTextChanged() { page.is = typed2.text.trim(); } }
        }
    }
    // Displays: chips
    Flow {
        visible: page.when === "displays"
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: ["1", "2", "3"]
            Choice { required property string modelData; text: modelData; selected: page.is === modelData; onClicked: page.is = modelData }
        }
    }
    // Time: TimePicker
    TimePicker {
        visible: page.when === "time"
        label: Tr.t("At this time")
        value: page.is || "09:00"
        onPicked: t => page.is = t
    }
    Text { text: Tr.t("then"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: page.thens
            Choice { required property var modelData; text: modelData.label; selected: page.then === modelData.id
                     onClicked: { page.then = modelData.id; page.arg = modelData.choices ? modelData.choices()[0] : ""; } }
        }
    }
    // Focus mode: chips
    Flow {
        visible: page.then === "focus"
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: page.d.focusModes.map(m => m.name).concat([""])
            Choice {
                required property string modelData
                text: modelData || Tr.t("(none)")
                selected: page.arg === modelData
                onClicked: page.arg = modelData
            }
        }
    }
    // DND: chips
    Flow {
        visible: page.then === "dnd"
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: ["on", "off"]
            Choice { required property string modelData; text: modelData === "on" ? Tr.t("On") : Tr.t("Off"); selected: page.arg === modelData; onClicked: page.arg = modelData }
        }
    }
    // Volume: chips
    Flow {
        visible: page.then === "volume"
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [0, 20, 40, 60, 80, 100]
            Choice { required property int modelData; text: modelData + "%"; selected: page.arg === String(modelData); onClicked: page.arg = String(modelData) }
        }
    }
    // Style: chips
    Flow {
        visible: page.then === "style"
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: ["dark", "light"]
            Choice { required property string modelData; text: modelData === "dark" ? Tr.t("Dark") : Tr.t("Light"); selected: page.arg === modelData; onClicked: page.arg = modelData }
        }
    }
    // Open app: AppPicker
    AppPicker {
        visible: page.then === "open"
        label: Tr.t("Open this app")
        value: page.arg
        onPicked: id => page.arg = id
    }
    // Run command: input is needed for commands
    TextField {
        id: typed3
        visible: page.then === "run"
        Layout.fillWidth: true
        placeholder: Tr.t("Shell command, e.g. notify-send hello")
        text: page.arg
        Connections { target: typed3.input; function onTextChanged() { page.arg = typed3.text.trim(); } }
    }
    Button {
        text: Tr.t("Add")
        kind: "primary"
        enabled: page.is !== "" && (page.arg !== "" || page.then === "focus")
        onClicked: {
            page.setRules(page.rulesCopy().concat([{ when: page.when, is: page.is, then: page.then, arg: page.arg, on: true }]));
            page.is = page.w.choices ? page.w.choices[0] : "";
            page.arg = page.t.choices ? page.t.choices()[0] : "";
        }
    }
}
