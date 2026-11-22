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
    spacing: Theme.px(12)
    readonly property var d: Settings.data

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

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Keyboard layouts") }
    Text {
        Layout.fillWidth: true
        visible: page.d.kbLayouts.length === 0
        text: Tr.t("Using the system's keyboard. Add a layout to choose your own.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
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
                size: Theme.px(24)
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
                size: Theme.px(24)
                Accessible.name: "Remove " + kbRow.title
                onClicked: page.d.kbLayouts = Array.from(page.d.kbLayouts).filter(x => x !== kbRow.modelData)
            }
        }
    }
    TextField {
        id: kbSearch
        Layout.fillWidth: true
        placeholder: Tr.t("Add a layout — marathi, german, dvorak, russian…")
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
        label: Tr.t("Switch layouts with")
        options: [{ label: Tr.t("Alt+Shift"), value: "grp:alt_shift_toggle" }, { label: Tr.t("Caps Lock"), value: "grp:caps_toggle" }, { label: Tr.t("Both Shifts"), value: "grp:shifts_toggle" }]
        current: page.d.kbSwitch
        onPicked: v => page.d.kbSwitch = v
    }
    SwitchRow {
        Layout.fillWidth: true
        visible: page.d.kbLayouts.length > 1
        text: Tr.t("Each window keeps its own layout")
        hint: Tr.t("switch to Marathi in a chat, and the editor stays in English")
        checked: page.d.kbPerWindow
        onToggled: on => page.d.kbPerWindow = on
    }
    Button {
        visible: page.d.kbLayouts.length > 0
        text: Tr.t("Use for the login screen too")
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
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Touchpad") }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Tap to click"); checked: page.d.tapToClick; onToggled: on => page.d.tapToClick = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Natural scrolling"); hint: Tr.t("content moves with your fingers"); checked: page.d.naturalScroll; onToggled: on => page.d.naturalScroll = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Off while typing"); hint: Tr.t("no stray clicks from a palm"); checked: page.d.typingGuard; onToggled: on => page.d.typingGuard = on }
    Picks {
        label: Tr.t("Pointer speed")
        options: [{ label: Tr.t("Slow"), value: -0.4 }, { label: Tr.t("Normal"), value: 0 }, { label: Tr.t("Fast"), value: 0.4 }, { label: Tr.t("Fastest"), value: 0.8 }]
        current: page.d.touchpadSpeed
        onPicked: v => page.d.touchpadSpeed = v
    }
    Picks {
        label: Tr.t("Click with")
        options: [{ label: Tr.t("Whole pad (1, 2, 3 fingers)"), value: "clickfinger" }, { label: Tr.t("Bottom corners"), value: "button-areas" }]
        current: page.d.tpClick
        onPicked: v => page.d.tpClick = v
    }
    Picks {
        label: Tr.t("Scroll with")
        options: [{ label: Tr.t("Two fingers"), value: "two-finger" }, { label: Tr.t("The edge"), value: "edge" }]
        current: page.d.tpScrollMethod
        onPicked: v => page.d.tpScrollMethod = v
    }
    Picks {
        label: Tr.t("Scroll speed")
        options: [{ label: Tr.t("Slow"), value: 0.5 }, { label: Tr.t("Normal"), value: 0.8 }, { label: Tr.t("Fast"), value: 1.2 }]
        current: page.d.tpScroll
        onPicked: v => page.d.tpScroll = v
    }
    Picks {
        label: Tr.t("Acceleration")
        options: [{ label: Tr.t("Adaptive"), value: "adaptive" }, { label: Tr.t("Flat (the same at any speed)"), value: "flat" }]
        current: page.d.tpAccel
        onPicked: v => page.d.tpAccel = v
    }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Off while a mouse is plugged in"); checked: page.d.tpOffWithMouse; onToggled: on => page.d.tpOffWithMouse = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Middle click with both buttons"); hint: Tr.t("press left and right together"); checked: page.d.tpMiddleEmulation; onToggled: on => page.d.tpMiddleEmulation = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Tap and slide to drag"); hint: Tr.t("off: a tap is only ever a click"); checked: page.d.tpDrag; onToggled: on => page.d.tpDrag = on }
    SwitchRow { Layout.fillWidth: true; enabled: page.d.tpDrag; text: Tr.t("Drag lock"); hint: Tr.t("keep dragging after the finger lifts"); checked: page.d.tpDragLock; onToggled: on => page.d.tpDragLock = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Off while the pointing stick is used"); hint: Tr.t("a ThinkPad's red dot: no stray touches from the hand on the pad"); checked: page.d.tpDwtp; onToggled: on => page.d.tpDwtp = on }
    Picks {
        label: Tr.t("Tap button order")
        options: [{ label: Tr.t("Left, right, middle"), value: "left-right-middle" }, { label: Tr.t("Left, middle, right"), value: "left-middle-right" }]
        current: page.d.tpTapButtonMap
        onPicked: v => page.d.tpTapButtonMap = v
    }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Drag a window to an edge scrolls the view"); checked: page.d.dndEdgeViewScroll; onToggled: on => page.d.dndEdgeViewScroll = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Drag a window to an edge switches workspaces"); checked: page.d.dndEdgeWorkspaceSwitch; onToggled: on => page.d.dndEdgeWorkspaceSwitch = on }
    Text {
        Layout.fillWidth: true
        text: Tr.t("Gestures: three fingers left or right move between columns, up or down between workspaces; four fingers up open the overview.")
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Mouse") }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Natural scrolling"); checked: page.d.mouseNaturalScroll; onToggled: on => page.d.mouseNaturalScroll = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Left-handed"); hint: Tr.t("swap the buttons (mouse and touchpad)"); checked: page.d.leftHanded; onToggled: on => page.d.leftHanded = on }
    Picks {
        label: Tr.t("Pointer speed")
        options: [{ label: Tr.t("Slow"), value: -0.4 }, { label: Tr.t("Normal"), value: 0 }, { label: Tr.t("Fast"), value: 0.4 }, { label: Tr.t("Fastest"), value: 0.8 }]
        current: page.d.mouseSpeed
        onPicked: v => page.d.mouseSpeed = v
    }

    Picks {
        label: Tr.t("Mouse acceleration")
        options: [{ label: Tr.t("Adaptive"), value: "adaptive" }, { label: Tr.t("Flat (games, drawing)"), value: "flat" }]
        current: page.d.mouseAccel
        onPicked: v => page.d.mouseAccel = v
    }
    Picks {
        label: Tr.t("Mouse scroll speed")
        options: [{ label: Tr.t("Slow"), value: 0.6 }, { label: Tr.t("Normal"), value: 1.0 }, { label: Tr.t("Fast"), value: 1.6 }]
        current: page.d.mouseScroll
        onPicked: v => page.d.mouseScroll = v
    }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Middle-click pastes"); hint: Tr.t("the text last selected - in every app"); checked: page.d.middlePaste; onToggled: on => page.d.middlePaste = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Scroll by holding the middle button"); hint: Tr.t("for a mouse without a wheel: hold it and move"); checked: page.d.mouseScrollButton; onToggled: on => page.d.mouseScrollButton = on }
    SwitchRow {
        Layout.fillWidth: true
        visible: page.d.mouseScrollButton || page.d.tballScrollButton
        text: Tr.t("Click to start and stop scrolling")
        hint: Tr.t("no holding the button down")
        checked: page.d.scrollButtonLock
        onToggled: on => page.d.scrollButtonLock = on
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Pointing stick & trackball") }
    Picks {
        label: Tr.t("Pointing stick speed")
        options: [{ label: Tr.t("Slow"), value: -0.4 }, { label: Tr.t("Normal"), value: 0 }, { label: Tr.t("Fast"), value: 0.4 }, { label: Tr.t("Fastest"), value: 0.8 }]
        current: page.d.tpointSpeed
        onPicked: v => page.d.tpointSpeed = v
    }
    Picks {
        label: Tr.t("Pointing stick acceleration")
        options: [{ label: Tr.t("Adaptive"), value: "adaptive" }, { label: Tr.t("Flat (the same at any speed)"), value: "flat" }]
        current: page.d.tpointAccel
        onPicked: v => page.d.tpointAccel = v
    }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Pointing stick: natural scrolling"); hint: Tr.t("with the middle button held"); checked: page.d.tpointNaturalScroll; onToggled: on => page.d.tpointNaturalScroll = on }
    Picks {
        label: Tr.t("Trackball speed")
        options: [{ label: Tr.t("Slow"), value: -0.4 }, { label: Tr.t("Normal"), value: 0 }, { label: Tr.t("Fast"), value: 0.4 }, { label: Tr.t("Fastest"), value: 0.8 }]
        current: page.d.tballSpeed
        onPicked: v => page.d.tballSpeed = v
    }
    Picks {
        label: Tr.t("Trackball acceleration")
        options: [{ label: Tr.t("Adaptive"), value: "adaptive" }, { label: Tr.t("Flat (the same at any speed)"), value: "flat" }]
        current: page.d.tballAccel
        onPicked: v => page.d.tballAccel = v
    }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Trackball: natural scrolling"); checked: page.d.tballNaturalScroll; onToggled: on => page.d.tballNaturalScroll = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Trackball: scroll by rolling with a button held"); hint: Tr.t("for a trackball without a wheel"); checked: page.d.tballScrollButton; onToggled: on => page.d.tballScrollButton = on }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Pointer") }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Hide the pointer while typing"); checked: page.d.cursorHideTyping; onToggled: on => page.d.cursorHideTyping = on }
    Picks {
        label: Tr.t("Hide the pointer when it is still")
        options: [{ label: Tr.t("Never"), value: 0 }, { label: Tr.t("After 3 s"), value: 3 }, { label: Tr.t("After 5 s"), value: 5 }, { label: Tr.t("After 10 s"), value: 10 }]
        current: page.d.cursorHideIdle
        onPicked: v => page.d.cursorHideIdle = v
    }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("The pointer goes to the window you switch to"); hint: Tr.t("with the keyboard: Alt+Tab, Mod+arrows"); checked: page.d.warpMouseToFocus; onToggled: on => page.d.warpMouseToFocus = on }
    Picks {
        label: Tr.t("Double-click speed")
        options: [{ label: Tr.t("Slow"), value: 600 }, { label: Tr.t("Normal"), value: 400 }, { label: Tr.t("Fast"), value: 250 }, { label: Tr.t("Fastest"), value: 150 }]
        current: page.d.doubleClickSpeed
        onPicked: v => page.d.doubleClickSpeed = v
    }
    // GNOME's own key, which GTK apps read: written when a speed is picked
    Process {
        id: dblClick
        command: ["gsettings", "set", "org.gnome.desktop.peripherals.mouse", "double-click", String(page.d.doubleClickSpeed)]
    }
    Connections { target: page.d; function onDoubleClickSpeedChanged() { dblClick.running = true; } }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Drawing tablet & touchscreen") }
    // which one is plugged in: the settings below apply to the tablet, and with
    // two of them it helps to see which one the system found
    Text {
        Layout.fillWidth: true
        text: !Tablet.available ? Tr.t("libwacom is not installed on this computer")
            : Tablet.devices.length === 0 ? Tr.t("No drawing tablet connected")
            : Tablet.devices.length === 1 ? Tr.t("Connected: %1", Tablet.devices[0])
            : Tr.t("Connected: %1", Tablet.devices.join(", "))
        color: Tablet.devices.length ? Theme.text : Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
    }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Keyboard button when hidden"); hint: Tr.t("on a touchscreen, or with no keyboard: a small button brings the screen keyboard back"); checked: page.d.oskButton; onToggled: on => page.d.oskButton = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Screen keyboard in tablet mode"); hint: Tr.t("folded into a tablet it comes up, unfolded it goes"); checked: page.d.oskWithTabletMode; onToggled: on => page.d.oskWithTabletMode = on }
    Repeater {
        model: [{ key: "tabletOutput", label: Tr.t("A drawing tablet draws on") }, { key: "touchOutput", label: Tr.t("The touchscreen is") }]
        ColumnLayout {
            id: mapRow
            required property var modelData
            Layout.fillWidth: true
            spacing: Theme.px(4)
            Text { text: modelData.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    // a tablet can also follow the screen being worked on (niri's map-to-focused-output)
                    model: [""].concat(Displays.outputs.map(o => o.name), mapRow.modelData.key === "tabletOutput" ? ["@focused", "@window"] : [])
                    Choice {
                        required property string modelData
                        readonly property string key: mapRow.modelData.key
                        text: modelData === "" ? Tr.t("Every screen") : modelData === "@focused" ? Tr.t("The screen I'm working on")
                            : modelData === "@window" ? Tr.t("The window I'm drawing in") : modelData
                        selected: (page.d[key] || "") === modelData
                        onClicked: page.d[key] = modelData
                    }
                }
            }
        }
    }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Left-handed tablet"); hint: Tr.t("the tablet turned around, buttons on the right"); checked: page.d.tabletLeftHanded; onToggled: on => page.d.tabletLeftHanded = on }
    // a touch or the pen lands off from where it was put: four targets touched, and it is right
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Button { text: Tr.t("Calibrate the touchscreen…"); onClicked: Calibrate.start("touch") }
        Button { text: Tr.t("Calibrate the pen…"); onClicked: Calibrate.start("tablet") }
        Button {
            visible: (page.d.touchMatrix || []).length === 6 || (page.d.tabletMatrix || []).length === 6
            flat: true
            text: Tr.t("Undo calibration")
            onClicked: { page.d.touchMatrix = []; page.d.tabletMatrix = []; }
        }
    }
    // niri 26.04 passes the pen's buttons to the app untouched (its tablet settings
    // are the screen, left-handed and a calibration matrix): no remapping to offer here
    Text {
        Layout.fillWidth: true
        text: Tr.t("The pen's own buttons do what the drawing app makes them do - set them up there.")
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Keyboard") }
    Text { text: Tr.t("Keyboard backlight"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Repeater {
            model: [{ id: "auto", label: Tr.t("Automatic") }, { id: "on", label: Tr.t("Always on") }, { id: "off", label: Tr.t("Off") }]
            Choice {
                required property var modelData
                text: modelData.label
                selected: page.d.kbdBacklight === modelData.id
                onClicked: page.d.kbdBacklight = modelData.id
            }
        }
    }
    Flow {
        visible: page.d.kbdBacklight === "on"
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Repeater {
            model: [1, 2, 3]
            Choice {
                required property int modelData
                text: modelData === 1 ? Tr.t("Dim") : modelData === 2 ? Tr.t("Medium") : Tr.t("Bright")
                selected: page.d.kbdBacklightLevel === modelData
                onClicked: page.d.kbdBacklightLevel = modelData
            }
        }
        Choice {
            text: Tr.t("Full")
            selected: page.d.kbdBacklightLevel === 0
            onClicked: page.d.kbdBacklightLevel = 0
        }
    }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Num Lock on at sign-in"); checked: page.d.numlock; onToggled: on => page.d.numlock = on }
    Picks {
        label: Tr.t("Repeat starts after")
        options: [{ label: Tr.t("Short"), value: 250 }, { label: Tr.t("Normal"), value: 400 }, { label: Tr.t("Long"), value: 600 }, { label: Tr.t("Longest"), value: 900 }]
        current: page.d.keyRepeatDelay
        onPicked: v => page.d.keyRepeatDelay = v
    }
    Picks {
        label: Tr.t("Repeat speed")
        options: [{ label: Tr.t("Slow"), value: 15 }, { label: Tr.t("Normal"), value: 30 }, { label: Tr.t("Fast"), value: 45 }]
        current: page.d.keyRepeatRate
        onPicked: v => page.d.keyRepeatRate = v
    }
    // a compose key types é, श, → from a sequence (xkb's compose:ralt etc.)
    Picks {
        label: Tr.t("Compose key")
        options: [{ label: Tr.t("None"), value: "" }, { label: Tr.t("Right Alt"), value: "ralt" }, { label: Tr.t("Right Super"), value: "rwin" }, { label: Tr.t("Menu"), value: "menu" }, { label: Tr.t("Caps Lock"), value: "caps" }]
        current: page.d.kbCompose
        onPicked: v => page.d.kbCompose = v
    }
    // some people want Escape where Caps Lock is (vim, emacs)
    Picks {
        label: Tr.t("Caps Lock behaves as")
        options: [{ label: Tr.t("Caps Lock"), value: "" }, { label: Tr.t("Escape"), value: "caps:escape" }, { label: Tr.t("Backspace"), value: "caps:backspace" }, { label: Tr.t("Ctrl"), value: "ctrl:nocaps" }]
        current: page.d.kbCaps
        onPicked: v => page.d.kbCaps = v
    }
    TextField {
        Layout.fillWidth: true
        placeholder: Tr.t("Try the repeat here")
    }
}
