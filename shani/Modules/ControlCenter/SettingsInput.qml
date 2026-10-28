// Settings > Keyboard & input: the touchpad, the mouse and key repeat (niri,
// through InputConfig). The screen keyboard section sits above this one.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    readonly property var d: Settings.data

    component Picks: ColumnLayout {
        id: picks
        property string label
        property var options: []          // [{ label, value }]
        property var current
        signal picked(var value)
        Layout.fillWidth: true
        spacing: 6
        Text { text: picks.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: picks.options
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: typeof modelData.value === "number" ? Math.abs(picks.current - modelData.value) < 0.001 : picks.current === modelData.value
                    onClicked: picks.picked(modelData.value)
                }
            }
        }
    }

    // ---- keyboard layouts --------------------------------------------------
    property var catalogue: []
    property string loginError: ""
    Process {
        running: page.visible && page.catalogue.length === 0
        command: ["python3", Osk.script, "--list"]
        stdout: StdioCollector { onStreamFinished: { try { page.catalogue = JSON.parse(text); } catch (e) {} } }
    }
    function nameOf(id) {
        const c = catalogue.find(x => x.id === id);
        return c ? c.name : id;
    }
    Process {
        id: loginKeymap
        stderr: StdioCollector { id: loginErr }
        onExited: code => page.loginError = code === 0 ? "Set for the login screen and the console." : (loginErr.text.trim().split("\n").pop() || "not changed")
    }

    SectionTitle { Layout.fillWidth: true; text: "Keyboard layouts" }
    Text {
        Layout.fillWidth: true
        visible: page.d.kbLayouts.length === 0
        text: "Using the system's keyboard. Add a layout to choose your own."
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Repeater {
        model: page.d.kbLayouts
        ListRow {
            id: kbRow
            required property string modelData
            required property int index
            Layout.fillWidth: true
            icon: "input-keyboard"
            title: page.nameOf(modelData)
            subtitle: index === 0 ? "First" : ""
            IconButton {
                visible: kbRow.index > 0
                icon: "go-up"
                size: 24
                Accessible.name: "Make " + kbRow.title + " first"
                onClicked: {
                    const l = Array.from(page.d.kbLayouts);
                    l.splice(kbRow.index, 1);
                    l.unshift(kbRow.modelData);
                    page.d.kbLayouts = l;
                }
            }
            IconButton {
                icon: "edit-delete"
                size: 24
                Accessible.name: "Remove " + kbRow.title
                onClicked: page.d.kbLayouts = Array.from(page.d.kbLayouts).filter(x => x !== kbRow.modelData)
            }
        }
    }
    TextField {
        id: kbSearch
        Layout.fillWidth: true
        placeholder: "Add a layout — marathi, german, dvorak, russian…"
    }
    Repeater {
        model: {
            const q = kbSearch.text.trim().toLowerCase();
            return q.length < 2 ? [] : page.catalogue.filter(c => c.name.toLowerCase().indexOf(q) >= 0 || c.id.indexOf(q) === 0).slice(0, 8);
        }
        ListRow {
            required property var modelData
            Layout.fillWidth: true
            icon: "list-add"
            title: modelData.name
            subtitle: modelData.id
            onClicked: {
                // the first layout added keeps US English beside it unless it is US itself
                const l = Array.from(page.d.kbLayouts);
                if (l.length === 0 && modelData.id !== "us")
                    l.push("us");
                if (l.indexOf(modelData.id) < 0)
                    l.push(modelData.id);
                page.d.kbLayouts = l;
                kbSearch.text = "";
            }
        }
    }
    Picks {
        visible: page.d.kbLayouts.length > 1
        label: "Switch layouts with"
        options: [{ label: "Super+Space", value: "grp:win_space_toggle" }, { label: "Alt+Shift", value: "grp:alt_shift_toggle" }, { label: "Caps Lock", value: "grp:caps_toggle" }, { label: "Both Shifts", value: "grp:shifts_toggle" }]
        current: page.d.kbSwitch
        onPicked: v => page.d.kbSwitch = v
    }
    Button {
        visible: page.d.kbLayouts.length > 0
        text: "Use for the login screen too"
        onClicked: {
            const l = Array.from(page.d.kbLayouts);
            // localed's X11 keymap: what niri uses when its config names no layout
            loginKeymap.command = ["localectl", "set-x11-keymap", l.map(x => x.split("+")[0]).join(","), "",
                                   l.map(x => x.split("+")[1] || "").join(","), l.length > 1 ? page.d.kbSwitch : ""];
            loginKeymap.running = true;
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.loginError !== ""
        text: page.loginError
        color: page.loginError.startsWith("Set") ? Theme.dim : Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }

    SectionTitle { Layout.fillWidth: true; text: "Touchpad" }
    SwitchRow { Layout.fillWidth: true; text: "Tap to click"; checked: page.d.tapToClick; onToggled: on => page.d.tapToClick = on }
    SwitchRow { Layout.fillWidth: true; text: "Natural scrolling"; hint: "content moves with your fingers"; checked: page.d.naturalScroll; onToggled: on => page.d.naturalScroll = on }
    SwitchRow { Layout.fillWidth: true; text: "Off while typing"; hint: "no stray clicks from a palm"; checked: page.d.typingGuard; onToggled: on => page.d.typingGuard = on }
    Picks {
        label: "Pointer speed"
        options: [{ label: "Slow", value: -0.4 }, { label: "Normal", value: 0 }, { label: "Fast", value: 0.4 }, { label: "Fastest", value: 0.8 }]
        current: page.d.touchpadSpeed
        onPicked: v => page.d.touchpadSpeed = v
    }
    Text {
        Layout.fillWidth: true
        text: "Gestures: three fingers left or right move between columns, up or down between workspaces; four fingers up open the overview."
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }

    SectionTitle { Layout.fillWidth: true; text: "Mouse" }
    SwitchRow { Layout.fillWidth: true; text: "Natural scrolling"; checked: page.d.mouseNaturalScroll; onToggled: on => page.d.mouseNaturalScroll = on }
    SwitchRow { Layout.fillWidth: true; text: "Left-handed"; hint: "swap the buttons (mouse and touchpad)"; checked: page.d.leftHanded; onToggled: on => page.d.leftHanded = on }
    Picks {
        label: "Pointer speed"
        options: [{ label: "Slow", value: -0.4 }, { label: "Normal", value: 0 }, { label: "Fast", value: 0.4 }, { label: "Fastest", value: 0.8 }]
        current: page.d.mouseSpeed
        onPicked: v => page.d.mouseSpeed = v
    }

    SectionTitle { Layout.fillWidth: true; text: "Keyboard" }
    Picks {
        label: "Repeat starts after"
        options: [{ label: "Short", value: 250 }, { label: "Normal", value: 400 }, { label: "Long", value: 600 }, { label: "Longest", value: 900 }]
        current: page.d.keyRepeatDelay
        onPicked: v => page.d.keyRepeatDelay = v
    }
    Picks {
        label: "Repeat speed"
        options: [{ label: "Slow", value: 15 }, { label: "Normal", value: 30 }, { label: "Fast", value: 45 }]
        current: page.d.keyRepeatRate
        onPicked: v => page.d.keyRepeatRate = v
    }
    TextField {
        Layout.fillWidth: true
        placeholder: "Try the repeat here"
    }
}
