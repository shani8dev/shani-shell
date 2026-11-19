// Circular progress ring with a centre slot — ported from Ananta UI (ananta-os/apps/ui/StatusRing.qml).
// value is 0..1; put any QML inside to show the number or label it measures.
// Motion follows Theme.animEnter, so Reduce motion turns the sweep into an instant change.
import QtQuick
import QtQuick.Shapes
import qs.Common

Item {
    id: ring
    property real value: 1.0
    property color color: Theme.accent
    property color trackColor: Theme.surface3
    property int size: Theme.px(96)
    property int thickness: Theme.px(9)
    property string label: ""
    default property alias content: centre.data

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Behavior on value { NumberAnimation { duration: Theme.animEnter; easing.type: Easing.OutCubic } }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: ring.trackColor
            strokeWidth: ring.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                // follow the item: a layout may set a different width than `size`
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: (Math.min(ring.width, ring.height) - ring.thickness) / 2
                radiusY: (Math.min(ring.width, ring.height) - ring.thickness) / 2
                startAngle: -90
                sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: ring.color
            strokeWidth: ring.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: (Math.min(ring.width, ring.height) - ring.thickness) / 2
                radiusY: (Math.min(ring.width, ring.height) - ring.thickness) / 2
                startAngle: -90
                // 359.9 rather than 360: a full circle with round caps draws a seam.
                sweepAngle: 359.9 * Math.min(1, Math.max(0, ring.value))
            }
        }
    }

    Item {
        id: centre
        anchors.fill: parent
    }

    // The number is in the centre slot, so a screen reader reads it from there.
    Accessible.role: Accessible.ProgressBar
    Accessible.name: ring.label
}
