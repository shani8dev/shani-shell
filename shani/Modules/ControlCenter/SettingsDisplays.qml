// Settings > Displays: arrange the screens (drag one; it snaps to the edge of
// the nearest), and for each — on or off, resolution and refresh rate, scale,
// rotation, variable refresh. Every change asks to be kept (Displays).
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    onActiveChanged: if (active) Displays.refresh()
    property string selected: Displays.outputs.length ? Displays.outputs[0].name : ""
    readonly property var sel: Displays.outputs.find(o => o.name === selected) || null

    component Picks: ColumnLayout {
        id: picks
        property string label
        property var options: []
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
                    selected: String(picks.current) === String(modelData.value)
                    onClicked: picks.picked(modelData.value)
                }
            }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: "Displays" }

    // ---- the arrangement ---------------------------------------------------------------
    Rectangle {
        id: map
        Layout.fillWidth: true
        Layout.preferredHeight: 170
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
                radius: 6
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
                    font.pixelSize: 10 * Theme.fontScale
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
        text: "Drag a screen to where it stands on your desk."
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }

    // ---- the chosen screen ---------------------------------------------------------------
    Flow {
        Layout.fillWidth: true
        spacing: 6
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
        spacing: 10
        SwitchRow {
            Layout.fillWidth: true
            visible: Displays.outputs.length > 1
            text: "On"
            checked: page.sel ? page.sel.on : false
            onToggled: on => Displays.apply(page.selected, { off: !on })
        }
        // resolution, largest first; then the refresh rates that resolution has
        Picks {
            label: "Resolution"
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
            label: "Refresh rate"
            options: page.sel ? page.sel.modes.filter(m => m.w + "x" + m.h === size).sort((a, b) => b.r - a.r)
                .map(m => ({ label: Math.round(m.r) + " Hz", value: size + "@" + m.r.toFixed(3) })) : []
            current: page.sel ? page.sel.mode : ""
            onPicked: v => Displays.apply(page.selected, { mode: v })
        }
        Picks {
            label: "Scale"
            options: [1, 1.25, 1.5, 1.75, 2].map(s => ({ label: Math.round(s * 100) + " %", value: s }))
            current: page.sel ? page.sel.scale : 1
            onPicked: v => Displays.apply(page.selected, { scale: v })
        }
        Picks {
            label: "Rotation"
            options: [{ label: "Normal", value: "normal" }, { label: "90°", value: "90" }, { label: "180°", value: "180" }, { label: "270°", value: "270" }]
            current: page.sel ? page.sel.transform : "normal"
            onPicked: v => Displays.apply(page.selected, { transform: v })
        }
        SwitchRow {
            Layout.fillWidth: true
            visible: page.sel ? page.sel.vrrSupported : false
            text: "Variable refresh rate"
            hint: "smoother games and video; some screens flicker with it"
            checked: page.sel ? page.sel.vrr : false
            onToggled: on => Displays.apply(page.selected, { vrr: on })
        }
        // external monitors' own brightness, over DDC/CI (a laptop's screen is the sidebar's slider)
        Repeater {
            model: Brightness.device !== "" ? Brightness.ddc : []
            ColumnLayout {
                id: ddcRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 4
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
}
