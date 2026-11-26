// Screen Ruler: freeze the screen and measure anything in pixels.
//
// Ported from Screen Ruler (src/ruler.rs): take a full-screen
// screenshot, show it frozen full screen, drag to measure (width × height),
// Shift for a straight line, right-click to clear, Esc to close,
// Ctrl+C to copy the size. Measurements are in the screenshot's real pixels.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/Gestures.js" as Hold

PanelWindow {
    id: win
    visible: Ruler.phase === "ready" || Ruler.phase === "capturing"
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-ruler"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (visible) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // the frozen screenshot
    Image {
        id: screenshot
        anchors.fill: parent
        source: Ruler.image !== "" ? "file://" + Ruler.image : ""
        fillMode: Image.PreserveAspectFit
        smooth: false
        cache: false
        asynchronous: true
    }

    // measuring area
    MouseArea {
        id: measureArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.CrossCursor

        // a finger has no right button: a long press starts over
        onPressAndHold: Ruler.clear()
        onPressed: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                Ruler.straight = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                Ruler.startX = mouse.x;
                Ruler.startY = mouse.y;
                Ruler.endX = mouse.x;
                Ruler.endY = mouse.y;
                Ruler.hasStart = true;
            } else if (mouse.button === Qt.RightButton) {
                Ruler.clear();
            }
        }
        onPositionChanged: function(mouse) {
            Ruler.cursorX = mouse.x;
            Ruler.cursorY = mouse.y;
            if (Ruler.hasStart) {
                // Shift draws a straight line in any direction, so its
                // diagonal length and angle are the measurement
                Ruler.straight = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                Ruler.endX = mouse.x;
                Ruler.endY = mouse.y;
            }
        }
        onReleased: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                // keep the measurement; cursor continues to track
            }
        }
    }

    // crosshair lines (dashed, dark under bright) — drawn on a Canvas
    Canvas {
        id: crosshair
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (!Ruler.hasStart && Ruler.cursorX === 0 && Ruler.cursorY === 0) {
                // draw cursor crosshair only
                drawCrosshair(ctx, width, height, Ruler.cursorX, Ruler.cursorY, false);
                return;
            }
            // cursor crosshair (dashed)
            drawCrosshair(ctx, width, height, Ruler.cursorX, Ruler.cursorY, true);
            // a Shift drag is a line; any other drag stays a rectangle
            if (Ruler.hasStart) {
                if (Ruler.straight) {
                    ctx.strokeStyle = "rgba(0, 0, 0, 0.6)";
                    ctx.lineWidth = 3;
                    ctx.beginPath();
                    ctx.moveTo(Ruler.startX, Ruler.startY); ctx.lineTo(Ruler.endX, Ruler.endY);
                    ctx.stroke();
                    ctx.strokeStyle = "rgba(255, 212, 0, 1.0)";
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(Ruler.startX, Ruler.startY); ctx.lineTo(Ruler.endX, Ruler.endY);
                    ctx.stroke();
                } else {
                    var x0 = Math.min(Ruler.startX, Ruler.endX);
                    var y0 = Math.min(Ruler.startY, Ruler.endY);
                    var rw = Math.abs(Ruler.endX - Ruler.startX);
                    var rh = Math.abs(Ruler.endY - Ruler.startY);
                    // translucent fill
                    ctx.fillStyle = "rgba(255, 208, 0, 0.12)";
                    ctx.fillRect(x0, y0, rw, rh);
                    // border (dark wide under bright thin)
                    ctx.strokeStyle = "rgba(0, 0, 0, 0.6)";
                    ctx.lineWidth = 3;
                    ctx.strokeRect(x0 + 0.5, y0 + 0.5, Math.round(rw), Math.round(rh));
                    ctx.strokeStyle = "rgba(255, 212, 0, 1.0)";
                    ctx.lineWidth = 1;
                    ctx.strokeRect(x0 + 0.5, y0 + 0.5, Math.round(rw), Math.round(rh));
                }
            }
        }
        function drawCrosshair(ctx, w, h, cx, cy, dashed) {
            ctx.save();
            ctx.setLineDash(dashed ? [6, 4] : []);
            ctx.strokeStyle = "rgba(0, 0, 0, 0.6)";
            ctx.lineWidth = 3;
            ctx.beginPath();
            ctx.moveTo(0, cy + 0.5); ctx.lineTo(w, cy + 0.5);
            ctx.moveTo(cx + 0.5, 0); ctx.lineTo(cx + 0.5, h);
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.strokeStyle = "rgba(255, 212, 0, 1.0)";
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(0, cy + 0.5); ctx.lineTo(w, cy + 0.5);
            ctx.moveTo(cx + 0.5, 0); ctx.lineTo(cx + 0.5, h);
            ctx.stroke();
            ctx.restore();
        }
        // redraw on cursor/mouse changes
        Connections {
            target: Ruler
            function onCursorXChanged() { crosshair.requestPaint(); }
            function onCursorYChanged() { crosshair.requestPaint(); }
            function onHasStartChanged() { crosshair.requestPaint(); }
            function onStraightChanged() { crosshair.requestPaint(); }
            function onEndXChanged() { crosshair.requestPaint(); }
            function onEndYChanged() { crosshair.requestPaint(); }
        }
        Connections {
            target: measureArea
            function onPositionChanged() { crosshair.requestPaint(); }
        }
    }

    // size badge near the cursor
    Rectangle {
        visible: Ruler.hasStart
        x: Math.min(Math.max(Ruler.endX + 14, 4), win.width - width - 4)
        y: Math.min(Math.max(Ruler.endY + 14, 4), win.height - height - 4)
        width: badge.implicitWidth + 16
        height: badge.implicitHeight + 10
        radius: Theme.px(6)
        color: Qt.rgba(0.08, 0.08, 0.1, 0.85)
        Text {
            id: badge
            anchors.centerIn: parent
            text: Ruler.sizeLabel() + (Ruler.hasSecond ? "\n" + Ruler.lineLabel() : "")
            color: "#ffffff"
            font.family: Theme.font
            font.pixelSize: Theme.type("heading")
            font.bold: true
        }
    }

    // hint line at top
    Text {
        anchors.top: parent.top
        anchors.topMargin: Theme.px(56)   // clear the top-centre Island
        anchors.horizontalCenter: parent.horizontalCenter
        text: Tr.t("Drag to measure  ·  Shift: straight line  ·  Right-click: clear  ·  Esc: close  ·  Ctrl+C: copy")
        color: "#ffffff"
        font.family: Theme.font
        font.pixelSize: Theme.type("body")
        // dark shadow for readability over any background
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.6)
    }

    // DPI calibration: 0 (the default) keeps px only; a real DPI adds cm/in
    Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.px(24)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.px(8)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Tr.t("DPI calibration:")
            color: "#ffffff"
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.6)
        }
        Rectangle {
            width: Theme.px(76)
            height: Theme.px(28)
            radius: Theme.px(5)
            color: Qt.rgba(0.08, 0.08, 0.1, 0.85)
            border.color: Qt.rgba(1, 1, 1, 0.35)
            TextInput {
                id: dpiInput
                anchors.fill: parent
                anchors.margins: Theme.px(4)
                text: Ruler.dpi > 0 ? String(Ruler.dpi) : ""
                color: "#ffffff"
                inputMethodHints: Qt.ImhDigitsOnly
                font.family: Theme.font
                font.pixelSize: Theme.type("body")
                Accessible.role: Accessible.EditableText
                Accessible.name: Tr.t("DPI calibration")
                onEditingFinished: {
                    Ruler.setDpi(text);
                    dpiInput.text = Ruler.dpi > 0 ? String(Ruler.dpi) : "";
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Ruler.dpi > 0 ? Tr.t("cm / in shown") : Tr.t("Set DPI for cm/in")
            color: "#ffffff"
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.6)
        }
    }

    // keys
    Shortcut {
        sequence: "Escape"
        onActivated: Ruler.close()
    }
    Shortcut {
        sequence: "Ctrl+C"
        onActivated: Ruler.copySize()
    }
    Shortcut {
        sequence: "Delete"
        onActivated: Ruler.clear()
    }
    Shortcut {
        sequence: "Backspace"
        onActivated: Ruler.clear()
    }
}
