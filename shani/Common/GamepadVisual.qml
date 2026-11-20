// A drawn controller that lights pressed buttons, moves the sticks and shows
// the analogue triggers. Ported from Ananta OS (ananta-gaming/ControllerVisual.qml)
// to shani's own feed: `held` is gamepad.py's button map ("A", "LB", "Left stick"…)
// and `axes` its axis map ("left-x", "right-trigger"…), both 0..1 for triggers.
import QtQuick
import QtQuick.Effects
import qs.Common

Item {
    id: pad
    property var held: ({})
    property var axes: ({})
    property string kind: "xbox"        // xbox | playstation | nintendo

    implicitWidth: Theme.px(440)
    implicitHeight: Theme.px(270)
    width: implicitWidth
    height: implicitHeight

    function on(key) { return !!pad.held[key] }
    function axis(name) { return Math.min(1, Math.max(0, pad.axes[name] || 0)) }
    readonly property color body: Theme.dark ? "#232833" : "#E7EAF0"
    readonly property color part: Theme.dark ? "#303745" : "#FFFFFF"
    readonly property color partLine: Theme.stroke
    readonly property var faceLabels: kind === "playstation" ? { a: "✕", b: "○", x: "□", y: "△" }
                                    : kind === "nintendo" ? { a: "B", b: "A", x: "Y", y: "X" }
                                    : { a: "A", b: "B", x: "X", y: "Y" }

    // Drawn in a fixed 440×270 design space, scaled by the shell's ui scale.
    Item {
        width: 440
        height: 270
        scale: pad.width / 440
        transformOrigin: Item.TopLeft

        // Triggers: analogue gauges above the bumpers.
        Repeater {
            model: [{ axis: "left-trigger", key: "LT", x: 70 }, { axis: "right-trigger", key: "RT", x: 270 }]
            delegate: Item {
                required property var modelData
                x: modelData.x; y: 0; width: 100; height: 14
                Rectangle { anchors.fill: parent; radius: 7; color: pad.partLine }
                Rectangle {
                    width: Math.max(14, parent.width * pad.axis(parent.modelData.axis))
                    height: parent.height
                    radius: 7
                    color: Theme.accent
                    visible: pad.axis(parent.modelData.axis) > 0.02
                }
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData.key + "  " + Math.round(pad.axis(parent.modelData.axis) * 100) + "%"
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: pad.axis(parent.modelData.axis) > 0.45 ? Theme.accentInk : Theme.dim
                }
            }
        }

        // Bumpers.
        Repeater {
            model: [{ key: "LB", x: 66 }, { key: "RB", x: 266 }]
            delegate: Rectangle {
                required property var modelData
                x: modelData.x; y: 24; width: 108; height: 26; radius: 13
                color: pad.on(modelData.key) ? Theme.accent : pad.part
                border.width: 1
                border.color: pad.on(modelData.key) ? Theme.accent : pad.partLine
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData.key
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: pad.on(parent.modelData.key) ? Theme.accentInk : Theme.dim
                }
            }
        }

        // Body and grips, one soft shadow.
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowOpacity: Theme.dark ? 0.5 : 0.18
                shadowBlur: 0.7
                shadowVerticalOffset: 4
                autoPaddingEnabled: true
            }
            Rectangle { x: 20; y: 44; width: 400; height: 150; radius: 75; color: pad.body }
            Rectangle { x: 34; y: 120; width: 132; height: 140; radius: 66; color: pad.body }
            Rectangle { x: 274; y: 120; width: 132; height: 140; radius: 66; color: pad.body }
        }

        component Stick: Item {
            id: stick
            property bool pressed: false
            property real ax: 0
            property real ay: 0
            width: 64; height: 64
            Rectangle { anchors.fill: parent; radius: 32; color: pad.partLine; opacity: 0.6 }
            Rectangle {
                width: 44; height: 44; radius: 22
                x: (stick.width - width) / 2 + stick.ax * 11
                y: (stick.height - height) / 2 + stick.ay * 11
                color: stick.pressed ? Theme.accent : pad.part
                border.width: 1
                border.color: pad.partLine
                Rectangle {
                    anchors.centerIn: parent
                    width: 18; height: 18; radius: 9
                    color: "transparent"
                    border.width: 2
                    border.color: stick.pressed ? Theme.accentInk : pad.partLine
                }
            }
        }
        Stick {
            x: 92; y: 78
            pressed: pad.on("Left stick")
            ax: pad.axis("left-x"); ay: pad.axis("left-y")
        }
        Stick {
            x: 248; y: 150
            pressed: pad.on("Right stick")
            ax: pad.axis("right-x"); ay: pad.axis("right-y")
        }

        // D-pad.
        Repeater {
            model: [{ key: "Up", x: 0, y: -1 }, { key: "Down", x: 0, y: 1 },
                    { key: "Left", x: -1, y: 0 }, { key: "Right", x: 1, y: 0 }]
            delegate: Rectangle {
                required property var modelData
                x: 148 + modelData.x * 22; y: 168 + modelData.y * 22
                width: 22; height: 22; radius: 5
                color: pad.on(modelData.key) ? Theme.accent : pad.part
                border.width: 1
                border.color: pad.on(modelData.key) ? Theme.accent : pad.partLine
            }
        }

        // Face buttons.
        Repeater {
            model: [{ key: "y", label: "Y", x: 0, y: -1 }, { key: "a", label: "A", x: 0, y: 1 },
                    { key: "x", label: "X", x: -1, y: 0 }, { key: "b", label: "B", x: 1, y: 0 }]
            delegate: Rectangle {
                required property var modelData
                x: 312 + modelData.x * 28; y: 96 + modelData.y * 28
                width: 30; height: 30; radius: 15
                color: pad.on(modelData.label) ? Theme.accent : pad.part
                border.width: 1
                border.color: pad.on(modelData.label) ? Theme.accent : pad.partLine
                scale: pad.on(modelData.label) ? 0.92 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.mot(60) } }
                Text {
                    anchors.centerIn: parent
                    text: pad.faceLabels[parent.modelData.key]
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: pad.on(parent.modelData.label) ? Theme.accentInk : Theme.dim
                }
            }
        }

        // Select / Start / Home.
        Rectangle { x: 186; y: 100; width: 26; height: 14; radius: 7; color: pad.on("Select") ? Theme.accent : pad.part; border.width: 1; border.color: pad.partLine }
        Rectangle { x: 228; y: 100; width: 26; height: 14; radius: 7; color: pad.on("Start") ? Theme.accent : pad.part; border.width: 1; border.color: pad.partLine }
        Rectangle {
            x: 206; y: 126; width: 28; height: 28; radius: 14
            color: pad.on("Home") ? Theme.accent : pad.part
            border.width: 1; border.color: pad.partLine
            Rectangle {
                anchors.centerIn: parent
                width: 8; height: 8; radius: 4
                color: pad.on("Home") ? Theme.accentInk : pad.partLine
            }
        }
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: Tr.t("Game controller: buttons light as you press them, sticks move, triggers show their pressure")
}
