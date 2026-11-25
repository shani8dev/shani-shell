// The screen keyboard's handwriting pad (after Collabora's plasma-keyboard work):
// ruled rows with room under each for descenders; a pen, a finger or the mouse
// writes; a pen's hover draws nothing (its pressure says so); a scribble rubs out
// what it covers; a pause and each row is read (bridge/handwriting.py, Tesseract,
// on this machine) and typed, rows joined by Return.
import QtQuick
import qs.Common
import qs.Services
import "Handwriting.js" as HW

Item {
    id: pad
    // compact mode rules one row instead of two: less height, and everything
    // written still lands in one line (no row breaks to lose)
    readonly property int rows: Osk.compact ? 1 : 2
    readonly property real rowHeight: height / rows
    property var strokes: []               // [[{x, y, p}]]
    property var current: []
    property bool pen: false
    readonly property bool reading: Osk.reading

    // the recognised word lands in Osk.lastWritten (Services/Osk); the last row
    // read is the one to look up. The clipboard is the word channel to the
    // Dictionary and Ui.dictionary is the flag its shell IPC uses too, so no
    // the Ui singleton source file change is needed.
    function lookUp() {
        const word = String(Osk.lastWritten || "").trim().split("\n").pop().trim();
        if (word === "") return;
        Quickshell.clipboardText = word;
        Ui.dictionary = false;   // re-open so Dictionary re-reads the clipboard
        Ui.dictionary = true;
    }

    function finish() {
        if (current.length > 1) {
            if (HW.isScribble(current))
                strokes = HW.rubOut(strokes, current);
            else
                strokes = strokes.concat([current]);
        }
        current = [];
        ink.requestPaint();
        if (strokes.length)
            pause.restart();
    }
    Timer {
        id: pause
        interval: 1300
        onTriggered: {
            const rows = HW.byRow(pad.strokes, pad.rowHeight, pad.rows).map(r => r.map(s => s.map(p => [Math.round(p.x), Math.round(p.y)])));
            pad.strokes = [];
            ink.requestPaint();
            Osk.recognize(rows);
        }
    }

    // the paper: ruled lines, the writing line a little above each row's foot
    Repeater {
        model: pad.rows
        Rectangle {
            required property int index
            x: 12; width: pad.width - 24; height: 1
            y: (index + 1) * pad.rowHeight - pad.rowHeight * 0.28
            color: Theme.alpha(Theme.text, 0.18)
        }
    }
    Text {
        anchors.centerIn: parent
        visible: pad.strokes.length === 0 && pad.current.length === 0
        text: pad.reading ? Tr.t("Reading…") : Tr.t("Write here, on the lines - scribble over a word to rub it out")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: Theme.px(14) * Theme.fontScale
    }
    Canvas {
        id: ink
        anchors.fill: parent
        onPaint: {
            const c = getContext("2d");
            c.reset();
            c.lineWidth = 3;
            c.lineCap = "round";
            c.lineJoin = "round";
            c.strokeStyle = Theme.text;
            for (const s of pad.strokes.concat(pad.current.length ? [pad.current] : [])) {
                c.beginPath();
                s.forEach((p, i) => i ? c.lineTo(p.x, p.y) : c.moveTo(p.x, p.y));
                c.stroke();
            }
        }
    }
    PointHandler {
        id: hand
        acceptedDevices: PointerDevice.AllDevices
        onActiveChanged: if (!active) pad.finish()
        onPointChanged: {
            if (!active)
                return;
            pad.pen = point.device && point.device.type === PointerDevice.Stylus;
            const pt = { x: point.position.x, y: point.position.y, p: pad.pen ? point.pressure : -1 };
            if (!HW.isInk(pt, pad.pen)) {
                if (pad.current.length)
                    pad.finish();               // lifted to a hover: the stroke ends there
                return;
            }
            pause.stop();
            pad.current = pad.current.concat([pt]);
            ink.requestPaint();
        }
    }

    // look up the word just written, without leaving the handwriting page
    IconButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.px(6)
        visible: String(Osk.lastWritten || "").trim() !== ""
        icon: "accessories-dictionary"
        size: Theme.px(26)
        tip: Tr.t("Look up")
        onClicked: pad.lookUp()
    }
}
