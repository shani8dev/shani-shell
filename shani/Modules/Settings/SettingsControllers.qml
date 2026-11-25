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
    spacing: Theme.px(10)
    property bool active: false
    readonly property string tool: Quickshell.env("SHANI_GAMEPAD_TOOL") || "/usr/lib/shani-shell/gamepad.py"
    property var pads: []                  // [{ name, event, uniq }]
    property string testing: ""           // the event node under test, "" none
    property var held: ({})               // button -> true while pressed
    property var axes: ({})               // axis -> -1 … 1

    function refresh() { list.running = true; lightList.running = true; }

    // Coloured lights (a controller's light bar, a handheld's stick rings): the
    // kernel's multicolour LEDs, read by bridge/lighting.py (no password) and set
    // through shani-admin.py lighting. Ananta OS's Display & Lighting, from the kernel.
    readonly property string lightingTool: Quickshell.env("SHANI_LIGHTING_TOOL") || "/usr/lib/shani-shell/lighting.py"
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property var lights: []                // [{ led, label, color, level }]
    property string lightNote: ""
    readonly property var lightColours: [
        { name: Tr.t("White"), value: "#ffffff" }, { name: Tr.t("Red"), value: "#ff3b30" },
        { name: Tr.t("Orange"), value: "#ff9500" }, { name: Tr.t("Yellow"), value: "#ffcc00" },
        { name: Tr.t("Green"), value: "#34c759" }, { name: Tr.t("Teal"), value: "#00c7be" },
        { name: Tr.t("Blue"), value: "#007aff" }, { name: Tr.t("Purple"), value: "#af52de" },
        { name: Tr.t("Pink"), value: "#ff2d55" }]
    Process {
        id: lightList
        command: ["python3", page.lightingTool, "list"]
        stdout: StdioCollector { onStreamFinished: { try { page.lights = JSON.parse(text); } catch (e) { page.lights = []; } } }
    }
    Process {
        id: lightWriter                   // not "write": that would hide the Process's own write()
        stdinEnabled: true
        property string payload: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { ok: false, error: text.trim() || "cancelled" }; }
                page.lightNote = r.ok ? "" : r.error;
                lightList.running = true;
            }
        }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
    }
    function setLight(led, color, level) {
        if (lightWriter.running) return;
        lightWriter.payload = JSON.stringify({ led: led, color: color, level: level });
        lightWriter.command = adminCmd.concat(["lighting"]);
        lightWriter.stdinEnabled = true;
        lightWriter.running = true;
    }
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

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Game controllers")

        Text {
            Layout.fillWidth: true
            visible: page.pads.length === 0
            text: Tr.t("No controller connected. Plug one in, or pair it in Bluetooth.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        Repeater {
            model: page.pads
            ColumnLayout {
                id: pad
                required property var modelData
                readonly property int battery: Plugged.controllerBattery(modelData.name)
                readonly property bool open: page.testing === modelData.event
                Layout.fillWidth: true
                spacing: Theme.px(6)
                SettingRow {
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
                    spacing: Theme.px(8)
                    Text {
                        text: Ui.padTestLast && Object.keys(page.held).length ? Tr.t("Pressed: %1", Object.keys(page.held).join(", ")) : Tr.t("Press any button, move the sticks.")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
                    // A drawn pad shows the press, the stick position and the analogue
                    // triggers together — the old chip list could not show LT/RT pressure.
                    GamepadVisual {
                        Layout.alignment: Qt.AlignHCenter
                        held: page.held
                        axes: page.axes
                        kind: /playstation|dualsense|dualshock/i.test(pad.modelData.name) ? "playstation"
                            : /switch|joy-?con/i.test(pad.modelData.name) ? "nintendo" : "xbox"
                    }
                }
            }
        }
        SwitchRow {
            Layout.fillWidth: true
            text: Tr.t("Move around the desktop with a controller")
            hint: InputPlumber.managing
                  ? Tr.t("the guide button opens Quick Settings, over a game too - the game sees no press until you close it; the d-pad moves, A selects, B goes back")
                  : Tr.t("the d-pad moves, A selects, B goes back, Start opens Quick Settings - not while a game is fullscreen")
            checked: Settings.data.gamepadNav
            onToggled: on => Settings.data.gamepadNav = on
        }
    }

    // ---- InputPlumber (shani-peripherals): what each controller plays as in games ----
    SettingsSection {
        visible: page.lights.length > 0
        Layout.fillWidth: true
        Layout.topMargin: Theme.px(8)
        title: Tr.t("Lights")

        Repeater {
            model: page.lights
            ColumnLayout {
                id: light
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text { text: light.modelData.label; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Repeater {
                        model: page.lightColours
                        Rectangle {
                            required property var modelData
                            readonly property bool chosen: light.modelData.color.toLowerCase() === modelData.value
                            width: Theme.px(30); height: Theme.px(30); radius: Theme.px(15)
                            color: modelData.value
                            border.width: chosen ? 3 : 1
                            border.color: chosen ? Theme.text : Theme.alpha(Theme.text, 0.25)
                            function choose() { page.setLight(light.modelData.led, modelData.value, light.modelData.level > 0 ? light.modelData.level : 100); }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: light.modelData.label + ": " + modelData.name
                            Accessible.checked: chosen
                            Accessible.onPressAction: choose()
                            Accessible.onToggleAction: choose()      // a radio button's first action is a toggle
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.choose() }
                            KeyFocus { onActivated: parent.choose() }
                        }
                    }
                    // the light's colour now, when it is none of the above (set by its
                    // firmware or another tool): without this nothing would look chosen
                    Rectangle {
                        visible: !page.lightColours.some(c => c.value === light.modelData.color.toLowerCase())
                        width: Theme.px(30); height: Theme.px(30); radius: Theme.px(15)
                        color: light.modelData.color
                        border.width: 3
                        border.color: Theme.text
                        Accessible.role: Accessible.Indicator
                        Accessible.name: light.modelData.label + ": " + Tr.t("its colour now")
                    }
                }
                Picks {
                    label: Tr.t("Brightness")
                    options: [{ label: Tr.t("Off"), value: "0" }, { label: Tr.t("Low"), value: "33" },
                              { label: Tr.t("Medium"), value: "66" }, { label: Tr.t("High"), value: "100" }]
                    current: String([0, 33, 66, 100].reduce((a, b) => Math.abs(b - light.modelData.level) < Math.abs(a - light.modelData.level) ? b : a))
                    onPicked: v => page.setLight(light.modelData.led, light.modelData.color, parseInt(v))
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: page.lightNote !== ""
            text: page.lightNote
            color: Theme.danger
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
    }

    SettingsSection {
        objectName: "in-games"
        visible: InputPlumber.running
        Layout.fillWidth: true
        Layout.topMargin: Theme.px(8)
        title: Tr.t("In games")

        Text {
            visible: InputPlumber.running && InputPlumber.devices.length === 0
            Layout.fillWidth: true
            text: Tr.t("No controller is managed yet: a handheld's own controls are, by themselves; others when \"Manage every controller\" is on.")
            color: Theme.dim
            wrapMode: Text.WordWrap
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        Repeater {
            model: InputPlumber.running ? InputPlumber.devices : []
            ColumnLayout {
                id: ipDev
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text {
                    Layout.fillWidth: true
                    text: ipDev.modelData.name + (ipDev.modelData.profile ? "  ·  " + ipDev.modelData.profile : "")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Text {
                    text: Tr.t("Plays as")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                // gamepad kinds only: its keyboard and mouse (a handheld's touchpad, its
                // extra keys) stay as they are
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: InputPlumber.supportedIds.map((id, i) => ({ id: id, name: InputPlumber.supported[i] || id }))
                                                       .filter(t => ["keyboard", "mouse", "touchpad", "touchscreen", "dbus", "debug"].indexOf(t.id) < 0)
                        Choice {
                            required property var modelData
                            text: modelData.name
                            selected: (ipDev.modelData.targets || []).indexOf(modelData.id) >= 0
                            onClicked: InputPlumber.setTargets(ipDev.modelData.path,
                                [modelData.id].concat((ipDev.modelData.targets || []).filter(t => ["keyboard", "mouse", "touchpad", "touchscreen"].indexOf(t) >= 0)))
                        }
                    }
                }
            }
        }
        SwitchRow {
            visible: InputPlumber.running
            Layout.fillWidth: true
            text: Tr.t("Manage every controller")
            hint: Tr.t("not only a handheld's own: every pad plays as the kind above, and the guide button reaches the desktop")
            checked: InputPlumber.manageAll
            onToggled: on => InputPlumber.setManageAll(on)
        }
    }
}
