// Settings > Displays: arrange the screens (drag one; it snaps to the edge of
// the nearest), and for each — on or off, resolution and refresh rate, scale,
// rotation, variable refresh. Every change asks to be kept (Displays).
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/FormFactor.js" as FF

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    onActiveChanged: if (active) Displays.refresh()
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) Displays.refresh()
    property string selected: Displays.outputs.length ? Displays.outputs[0].name : ""
    readonly property var sel: Displays.outputs.find(o => o.name === selected) || null

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Displays")

    // ---- the arrangement ---------------------------------------------------------------
    Rectangle {
        id: map
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.px(170)
        radius: Theme.radius
        color: Theme.hover
        visible: Displays.outputs.length > 0
        readonly property var on: Displays.outputs.filter(o => o.on)
        readonly property real minX: Math.min(...on.map(o => o.x), 0)
        readonly property real minY: Math.min(...on.map(o => o.y), 0)
        readonly property real spanW: Math.max(...on.map(o => o.x + o.width), 1) - minX
        readonly property real spanH: Math.max(...on.map(o => o.y + o.height), 1) - minY
        readonly property real k: Math.min((width - 40) / spanW, (height - 30) / spanH)
        readonly property real ox: (width - spanW * k) / 2
        readonly property real oy: (height - spanH * k) / 2

        // where a dropped screen goes: against the nearest side of the nearest other one
        function snap(o, x, y) {
            const others = on.filter(p => p.name !== o.name);
            if (!others.length)
                return { x: 0, y: 0 };
            let best = null, dist = 1e12;
            for (const p of others) {
                const spots = [
                    { x: p.x + p.width, y: p.y }, { x: p.x - o.width, y: p.y },
                    { x: p.x, y: p.y + p.height }, { x: p.x, y: p.y - o.height }
                ];
                for (const s of spots) {
                    const dd = (s.x - x) * (s.x - x) + (s.y - y) * (s.y - y);
                    if (dd < dist) { dist = dd; best = s; }
                }
            }
            return best;
        }
        Repeater {
            model: map.on
            Rectangle {
                id: screenRect
                required property var modelData
                x: map.ox + (modelData.x - map.minX) * map.k + drag.dx
                y: map.oy + (modelData.y - map.minY) * map.k + drag.dy
                width: modelData.width * map.k
                height: modelData.height * map.k
                radius: Theme.px(6)
                color: page.selected === modelData.name ? Theme.accentSoft : Theme.glassStrong
                border.width: 2
                border.color: page.selected === modelData.name ? Theme.accent : Theme.stroke
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                    text: screenRect.modelData.label + "\n" + screenRect.modelData.name
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                MouseArea {
                    id: drag
                    anchors.fill: parent
                    property real dx: 0
                    property real dy: 0
                    property point start
                    cursorShape: map.on.length > 1 ? Qt.SizeAllCursor : Qt.PointingHandCursor
                    onPressed: m => { page.selected = screenRect.modelData.name; start = mapToItem(map, m.x, m.y); }
                    onPositionChanged: m => {
                        if (map.on.length < 2) return;
                        const p = mapToItem(map, m.x, m.y);
                        dx = p.x - start.x;
                        dy = p.y - start.y;
                    }
                    onReleased: {
                        if (Math.abs(dx) + Math.abs(dy) > 4) {
                            const o = screenRect.modelData;
                            const s = map.snap(o, o.x + dx / map.k, o.y + dy / map.k);
                            // every screen's position, moved so the top-left one is at 0,0
                            const pos = map.on.map(p => p.name === o.name ? { name: p.name, x: s.x, y: s.y } : { name: p.name, x: p.x, y: p.y });
                            const mx = Math.min(...pos.map(p => p.x)), my = Math.min(...pos.map(p => p.y));
                            Displays.apply_all(pos.map(p => ({ name: p.name, patch: { x: p.x - mx, y: p.y - my } })));
                        }
                        dx = 0;
                        dy = 0;
                    }
                }
            }
        }
    }
    Text {
        visible: map.on.length > 1
        text: Tr.t("Drag a screen to where it stands on your desk.")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }

    // ---- the chosen screen ---------------------------------------------------------------
    Flow {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        visible: Displays.outputs.length > 1
        Repeater {
            model: Displays.outputs
            Choice {
                required property var modelData
                text: modelData.label + (modelData.on ? "" : " (off)")
                selected: page.selected === modelData.name
                onClicked: page.selected = modelData.name
            }
        }
    }
    ColumnLayout {
        visible: page.sel !== null
        Layout.fillWidth: true
        spacing: Theme.px(10)
        SwitchRow {
            Layout.fillWidth: true
            visible: Displays.outputs.length > 1
            text: Tr.t("On")
            checked: page.sel ? page.sel.on : false
            onToggled: on => Displays.apply(page.selected, { off: !on })
        }
        // resolution, largest first; then the refresh rates that resolution has
        Picks {
            label: Tr.t("Resolution")
            readonly property var sizes: page.sel ? Array.from(new Set(page.sel.modes.map(m => m.w + "x" + m.h)))
                .sort((a, b) => b.split("x")[0] * b.split("x")[1] - a.split("x")[0] * a.split("x")[1]) : []
            options: sizes.slice(0, 8).map(s => ({ label: s.replace("x", " × ") + (page.sel.modes.some(m => m.preferred && m.w + "x" + m.h === s) ? "  ★" : ""), value: s }))
            current: page.sel && page.sel.mode ? page.sel.mode.split("@")[0] : ""
            onPicked: v => {
                const best = page.sel.modes.filter(m => m.w + "x" + m.h === v).sort((a, b) => b.r - a.r)[0];
                Displays.apply(page.selected, { mode: v + "@" + best.r.toFixed(3) });
            }
        }
        Picks {
            readonly property string size: page.sel && page.sel.mode ? page.sel.mode.split("@")[0] : ""
            visible: options.length > 1
            label: Tr.t("Refresh rate")
            options: page.sel ? page.sel.modes.filter(m => m.w + "x" + m.h === size).sort((a, b) => b.r - a.r)
                .map(m => ({ label: Math.round(m.r) + " Hz", value: size + "@" + m.r.toFixed(3) })) : []
            current: page.sel ? page.sel.mode : ""
            onPicked: v => Displays.apply(page.selected, { mode: v })
        }
        Picks {
            label: Tr.t("Scale")
            options: [1, 1.25, 1.5, 1.75, 2].map(s => ({ label: Math.round(s * 100) + " %", value: s }))
            current: page.sel ? page.sel.scale : 1
            onPicked: v => Displays.apply(page.selected, { scale: v })
        }
        // what kind of screen this is: the shell's size and layout follow it
        // (Services/FormFactor); Automatic tells it by its size and input
        Picks {
            label: Tr.t("Kind of screen")
            options: [{ label: Tr.t("Automatic") + (page.sel ? " (" + Tr.t(FF.label(FormFactor.detected(page.selected))) + ")" : ""), value: "auto" }]
                .concat(["computer", "laptop", "tablet", "handheld", "phone", "tv", "board"].map(p => ({ label: Tr.t(FF.label(p)), value: p })))
            current: (Settings.data.formFactors || {})[page.selected] || "auto"
            onPicked: v => FormFactor.choose(page.selected, v)
        }
        Picks {
            label: Tr.t("Shell size")
            options: [{ label: Tr.t("Automatic"), value: "auto" }]
                .concat([1, 1.25, 1.5, 1.75, 2].map(s => ({ label: Math.round(s * 100) + " %", value: s })))
            current: (Settings.data.formFactorScales || {})[page.selected] || "auto"
            onPicked: v => FormFactor.chooseScale(page.selected, v)
        }
        Picks {
            label: Tr.t("Rotation")
            options: [{ label: Tr.t("Normal"), value: "normal" }, { label: "90°", value: "90" }, { label: "180°", value: "180" }, { label: "270°", value: "270" }]
            current: page.sel ? page.sel.transform : "normal"
            onPicked: v => Displays.apply(page.selected, { transform: v })
        }
        SwitchRow {
            Layout.fillWidth: true
            visible: page.sel ? page.sel.vrrSupported : false
            text: Tr.t("Variable refresh rate")
            hint: Tr.t("smoother games and video; some screens flicker with it")
            checked: page.sel ? page.sel.vrr : false
            onToggled: on => Displays.apply(page.selected, { vrr: on })
        }
        // colour depth: 10 bits a channel where cable and screen take it (smoother gradients, HDR's way in)
        Picks {
            label: Tr.t("Colour depth")
            options: [{ label: Tr.t("Automatic"), value: "" }, { label: Tr.t("8 bits"), value: "8" }, { label: Tr.t("10 bits"), value: "10" }]
            current: String(((Settings.data.displays || {})[page.selected] || {}).bpc || "")
            onPicked: v => Displays.apply(page.selected, { bpc: v === "" ? 0 : parseInt(v) })
        }
        // a resolution the screen does not offer (a projector, an old monitor): kept only if confirmed
        Picks {
            label: Tr.t("Resolution of your own")
            options: [{ label: Tr.t("None"), value: "" }, { label: "1280×720", value: "1280x720@60" }, { label: "1600×900", value: "1600x900@60" },
                      { label: "1920×1080", value: "1920x1080@60" }, { label: "2560×1440", value: "2560x1440@60" }, { label: "3840×2160", value: "3840x2160@30" }]
            current: String(((Settings.data.displays || {})[page.selected] || {}).customMode || "")
            onPicked: v => Displays.apply(page.selected, { customMode: v })
        }
        RowLayout {
            Layout.fillWidth: true
            TextField { id: customMode; Layout.fillWidth: true; placeholderText: Tr.t("Other: width x height @ refresh, e.g. 1680x1050@60") }
            Button { text: Tr.t("Try it"); enabled: /^\d{3,5}x\d{3,5}@\d{2,3}(\.\d+)?$/.test(customMode.text.trim()); onClicked: Displays.apply(page.selected, { customMode: customMode.text.trim() }) }
        }
        SwitchRow {
            Layout.fillWidth: true
            visible: Displays.outputs.length > 1
            text: Tr.t("Start the session on this screen")
            checked: Settings.data.startupOutput === page.selected
            onToggled: on => { Settings.data.startupOutput = on ? page.selected : ""; Settings.touch("startupOutput"); }
        }
        SwitchRow {
            Layout.fillWidth: true
            text: Tr.t("This is a VR headset")
            hint: Tr.t("lent whole to the VR app (SteamVR, Monado) instead of being a desktop screen")
            checked: !!((Settings.data.displays || {})[page.selected] || {}).vrLease
            onToggled: on => Displays.apply(page.selected, { vrLease: on })
        }
        // external monitors' own brightness, over DDC/CI (a laptop's screen is the sidebar's slider)
        Repeater {
            model: Brightness.device !== "" ? Brightness.ddc : []
            ColumnLayout {
                id: ddcRow
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text { text: "Brightness — " + ddcRow.modelData.model; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                SliderRow {
                    Layout.fillWidth: true
                    icon: "display-brightness"
                    value: ddcRow.modelData.value
                    onMoved: v => Brightness.setDdc(ddcRow.modelData.display, v)
                }
            }
        }
        Button {
            visible: Displays.canMirror && Displays.outputs.length > 1
            text: Displays.mirroring ? "Stop mirroring" : "Mirror this screen on another"
            onClicked: Displays.toggleMirror(page.selected)
        }
    }

    // ---- battery: the built-in panel at 60 Hz until the charger is back ------------
    }

    // ---- scale presets: resolution=scale applied when a display changes ---------
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Scale presets")
        hint: Tr.t("Apply a scale automatically when a display's resolution changes. One per line: 2560x1440=1.5 or DP-3:1920x1080=1.25 (port-specific wins).")
    TextField {
        Layout.fillWidth: true
        placeholder: Tr.t("Add a preset: 2560x1440=1.5 or DP-3:1920x1080=1.25")
        label: Tr.t("Scale preset")
        id: presetField
        onAccepted: {
            const s = text.trim();
            if (s && /^(?:(?:[\w-]+):)?\d+x\d+=[\d.]+$/.test(s)) {
                const all = (Settings.data.displayScalePresets || []).concat([s]);
                Settings.data.displayScalePresets = all;
                text = "";
            }
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Repeater {
            model: Settings.data.displayScalePresets || []
            Rectangle {
                required property string modelData
                required property int index
                implicitWidth: presetLabel.implicitWidth + 30
                height: Theme.px(26)
                radius: Theme.px(13)
                color: Theme.surface1
                Text { id: presetLabel; anchors.centerIn: parent; text: modelData; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                IconButton {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    size: Theme.px(20)
                    icon: "edit-clear-all"
                    tip: Tr.t("Remove preset")
                    onClicked: {
                        const all = (Settings.data.displayScalePresets || []).slice();
                        all.splice(index, 1);
                        Settings.data.displayScalePresets = all;
                    }
                }
            }
        }
    }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Apply presets automatically")
        hint: Tr.t("when a display's resolution changes")
        checked: Settings.data.displayScalePresetsAuto !== false
        onToggled: on => Settings.data.displayScalePresetsAuto = on
    }
    }

    SwitchRow {
        Layout.fillWidth: true
        visible: Power.hasBattery
        text: Tr.t("60 Hz on battery")
        hint: Tr.t("the laptop's own screen steps down from a faster refresh while unplugged, and back up on the charger")
        checked: Settings.data.batteryRefresh60
        onToggled: on => Settings.data.batteryRefresh60 = on
    }

    // ---- auto-rotate: tablets and convertibles with an accelerometer --------------
    SectionTitle { Layout.fillWidth: true; visible: AutoRotate.available; text: Tr.t("Rotation") }
    // ---- multi-GPU: which card niri renders on -----------------------------------
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Graphics")
    Text {
        Layout.fillWidth: true
        visible: Gpu.renderDevices.length > 1
        wrapMode: Text.WordWrap
        text: Tr.t("Which graphics card Niri uses. On a laptop, the integrated card saves battery; a game can still be opened on the other card with the launcher's “Run on other GPU”.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    Repeater {
        model: Gpu.renderDevices
        delegate: Choice {
            required property var modelData
            text: modelData.name + "  (" + modelData.path.split("/").pop() + ")"
            selected: Settings.data.niriRenderDevice === modelData.path
            visible: Gpu.renderDevices.length > 1
            onClicked: Settings.data.niriRenderDevice = modelData.path
        }
    }
    Choice {
        visible: Gpu.renderDevices.length > 1 && Settings.data.niriRenderDevice !== ""
        text: Tr.t("Let Niri choose")
        selected: false
        onClicked: Settings.data.niriRenderDevice = ""
    }
    }

    SwitchRow {
        Layout.fillWidth: true
        visible: AutoRotate.available
        text: Tr.t("Rotate the screen automatically")
        hint: Tr.t("tablets and convertibles: portrait when held upright, landscape flat")
        checked: Settings.data.autoRotate
        onToggled: on => Settings.data.autoRotate = on
    }
}
