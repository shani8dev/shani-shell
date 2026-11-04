// The charger going in (a phone's charging animation, macOS's chime and
// glyph): a glass card in the middle of the screen in use - a ring filling up
// to the charge there is, a bolt, the percentage and the time to full - for a
// couple of seconds, then gone. Only for a change after the shell is up, and
// only with a battery. Pulling the charger is the OSD's "On battery".
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Services

PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    visible: shown || card.opacity > 0
    implicitWidth: 260
    implicitHeight: 260
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-charging"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}                       // never in the way of a click
    BackgroundEffect.blurRegion: Settings.data.blur && visible ? cardRegion : null
    Region { id: cardRegion; item: card; radius: card.radius }

    property bool shown: false
    property bool armed: false
    property real level: 0               // what the ring shows, animated up to the charge
    function play() {
        level = 0;
        shown = true;
        fill.restart();
        away.restart();
    }
    Timer { interval: 4000; running: true; onTriggered: win.armed = true }
    Timer { id: away; interval: 2600; onTriggered: win.shown = false }
    NumberAnimation { id: fill; target: win; property: "level"; from: 0; to: Math.max(0.02, Power.percent); duration: 1100; easing.type: Easing.OutCubic }
    Connections {
        target: Power
        function onOnBatteryChanged() { if (win.armed && Power.hasBattery && !Power.onBattery) win.play(); }
    }
    // the tests and the showcase
    Connections { target: Ui; function onChargingPreviewChanged() { if (Ui.chargingPreview) { Ui.chargingPreview = false; win.play(); } } }

    Glass {
        id: card
        anchors.centerIn: parent
        width: 220
        height: 220
        radius: 44
        strong: true
        opacity: win.shown ? 1 : 0
        scale: win.shown ? 1 : 0.86
        Behavior on opacity { NumberAnimation { duration: Theme.animEnter * 0.6; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animEnter; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized } }

        Shape {
            id: ring
            anchors.centerIn: parent
            width: 150
            height: 150
            preferredRendererType: Shape.CurveRenderer
            ShapePath {           // the track
                strokeColor: Theme.alpha(Theme.text, 0.12)
                strokeWidth: 10
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 75; centerY: 75; radiusX: 68; radiusY: 68; startAngle: -90; sweepAngle: 360 }
            }
            ShapePath {           // the charge
                strokeColor: Power.percent < 0.2 ? Theme.amber : Theme.accent
                strokeWidth: 10
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 75; centerY: 75; radiusX: 68; radiusY: 68; startAngle: -90; sweepAngle: 360 * win.level }
            }
        }
        Column {
            anchors.centerIn: ring
            spacing: 2
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "battery-level-100-charged"; size: 26; color: Theme.accent }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(win.level * 100) + "%"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 28 * Theme.fontScale
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            text: Power.timeLeft || Tr.t("Charging")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12 * Theme.fontScale
        }
    }
}
