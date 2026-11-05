// Settings > Keyboard & input > Game controllers: the ones connected (the kernel's
// joysticks, USB and Bluetooth alike), each with its battery (UPower) and a "Test
// the buttons" view that shows presses and the sticks live. The view's reader
// (bridge/gamepad.py watch) runs only while the view is open. The list is read
// when the category opens and again when a controller comes or goes (Plugged).
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 10
    property bool active: false
    readonly property string tool: Quickshell.env("SHANI_GAMEPAD_TOOL") || "/usr/lib/shani-shell/gamepad.py"
    property var pads: []                  // [{ name, event, uniq }]
    property string testing: ""           // the event node under test, "" none
    property var held: ({})               // button -> true while pressed
    property var axes: ({})               // axis -> -1 … 1

    function refresh() { list.running = true; }
    onActiveChanged: { if (active) refresh(); else testing = ""; }
    Component.onCompleted: if (active) refresh()
    Connections { target: Plugged; function onControllerRevChanged() { if (page.active) page.refresh(); } }
    Process {
        id: list
        command: ["python3", page.tool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.pads = JSON.parse(text); } catch (e) { page.pads = []; }
                Ui.controllersListed = page.pads.length;
                if (page.testing && !page.pads.some(p => p.event === page.testing))
                    page.testing = "";          // unplugged while being tested
            }
        }
    }
    // started by hand, command first: a bound `running` could start before the bound
    // command had the node, and a reader that exits at once never comes back
    readonly property bool reading: testing !== "" && active && visible
    onReadingChanged: {
        watch.running = false;
        if (reading) {
            watch.command = ["python3", page.tool, "watch", page.testing];
            watch.running = true;
        }
    }
    Process {
        id: watch
        onRunningChanged: { page.held = ({}); page.axes = ({}); Ui.padTestRunning = running; }
        stdout: SplitParser {
            onRead: line => {
                const w = line.split(" ");
                if (w[0] === "press" || w[0] === "release") {
                    const h = Object.assign({}, page.held);
                    const b = w.slice(1).join(" ");
                    if (w[0] === "press") { h[b] = true; Ui.padTestLast = b; } else delete h[b];
                    page.held = h;
                } else if (w[0] === "axis") {
                    const a = Object.assign({}, page.axes);
                    a[w[1]] = parseFloat(w[2]);
                    page.axes = a;
                }
            }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Game controllers") }
    Text {
        Layout.fillWidth: true
        visible: page.pads.length === 0
        text: Tr.t("No controller connected. Plug one in, or pair it in Bluetooth.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Repeater {
        model: page.pads
        ColumnLayout {
            id: pad
            required property var modelData
            readonly property int battery: Plugged.controllerBattery(modelData.name)
            readonly property bool open: page.testing === modelData.event
            Layout.fillWidth: true
            spacing: 6
            ListRow {
                Layout.fillWidth: true
                icon: "input-gaming"
                title: pad.modelData.name
                subtitle: pad.battery >= 0 ? Tr.t("Battery %1 %", pad.battery) : Tr.t("Connected")
                Button {
                    text: pad.open ? Tr.t("Done") : Tr.t("Test the buttons")
                    Accessible.name: pad.open ? Tr.t("Done testing %1", pad.modelData.name) : Tr.t("Test the buttons of %1", pad.modelData.name)
                    onClicked: page.testing = pad.open ? "" : pad.modelData.event
                }
            }
            // the test view: each button lights while held, the sticks show where they point
            ColumnLayout {
                visible: pad.open
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: Ui.padTestLast && Object.keys(page.held).length ? Tr.t("Pressed: %1", Object.keys(page.held).join(", ")) : Tr.t("Press any button, move the sticks.")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "Select", "Start", "Home", "Left stick", "Right stick", "Up", "Down", "Left", "Right"]
                        Choice { required property string modelData; text: modelData; selected: !!page.held[modelData]; enabled: false }
                    }
                }
                Row {
                    spacing: 18
                    Repeater {
                        model: [["left-x", "left-y", Tr.t("Left stick")], ["right-x", "right-y", Tr.t("Right stick")]]
                        Column {
                            id: stick
                            required property var modelData
                            spacing: 4
                            Rectangle {
                                width: 64; height: 64; radius: 32
                                color: Theme.hover
                                Rectangle {
                                    width: 12; height: 12; radius: 6
                                    color: Theme.accent
                                    x: 26 + 26 * (page.axes[stick.modelData[0]] || 0)
                                    y: 26 + 26 * (page.axes[stick.modelData[1]] || 0)
                                }
                            }
                            Text { text: stick.modelData[2]; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
                        }
                    }
                }
            }
        }
    }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Move around the desktop with a controller")
        hint: Tr.t("the d-pad moves, A selects, B goes back, Start opens Quick Settings - not while a game is fullscreen")
        checked: Settings.data.gamepadNav
        onToggled: on => Settings.data.gamepadNav = on
    }
}
