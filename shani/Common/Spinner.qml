// Small rotating arc for "working" states — Ananta UI (ui/Spinner.qml) on the
// shell palette. Stops entirely when the surface is hidden or motion is reduced.
import QtQuick
import QtQuick.Shapes
import qs.Common

Item {
    id: spinner
    property real size: Theme.px(18)
    property color color: Theme.accent
    readonly property int thickness: Math.max(2, Math.round(size / 8))

    width: size
    height: size

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: spinner.color
            strokeWidth: spinner.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: spinner.width / 2
                centerY: spinner.height / 2
                radiusX: (Math.min(spinner.width, spinner.height) - spinner.thickness) / 2
                radiusY: (Math.min(spinner.width, spinner.height) - spinner.thickness) / 2
                startAngle: 0
                sweepAngle: 270
            }
        }
    }

    RotationAnimator on rotation {
        running: spinner.visible && !Settings.data.reduceMotion
        from: 0
        to: 360
        duration: Theme.mot(900)
        loops: Animation.Infinite
    }

    Accessible.ignored: true   // the button or row around it carries the name
}
