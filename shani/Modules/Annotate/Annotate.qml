// Draw on the screen (ZoomIt, Windows Ink's screen sketch, macOS Markup):
// a clear layer over whatever is shown, to point things out in a call or a
// recording. Drag draws; Shift+drag a straight line; 1–5 change the colour;
// Z undoes, E erases all, S saves a screenshot with the drawing (and copies
// it), Esc closes. The layer is live, not a frozen frame, so a video or a
// cursor under it keeps moving.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.annotate
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-annotate"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var colours: ["#e5484d", "#f5d90a", "#46a758", "#0091ff", "#ffffff"]
    property int colour: 0
    property var strokes: []            // [{ c, pts: [x, y, x, y …] }]
    property var current: null
    property bool hintShown: true
    onVisibleChanged: {
        if (visible) { keys.forceActiveFocus(); hintShown = true; }
        else { strokes = []; current = null; canvas.requestPaint(); }
        Ui.annotateStrokes = 0;
    }
    function commit() {
        if (current && current.pts.length >= 4) strokes = strokes.concat([current]);
        current = null;
        Ui.annotateStrokes = strokes.length;
        canvas.requestPaint();
    }
    function undo() { strokes = strokes.slice(0, -1); Ui.annotateStrokes = strokes.length; canvas.requestPaint(); }
    function clear() { strokes = []; Ui.annotateStrokes = 0; canvas.requestPaint(); }
    function save() {
        // the hint hides first, so the picture is the screen and the drawing only
        hintShown = false;
        Qt.callLater(() => Quickshell.execDetached(["sh", "-c",
            'sleep 0.15; d="${2:-${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots}"; case "$d" in "~"*) d="$HOME${d#"~"}";; esac; mkdir -p "$d"; f="$d/Drawing $(date "+%F %H-%M-%S").png"; grim -o "$1" "$f" && wl-copy < "$f" && notify-send -a Screenshot -i "$f" "Drawing saved" "Copied too — ${f##*/}"',
            "sh", win.screen ? win.screen.name : "", Settings.data.screenshotDir || ""]));
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const g = getContext("2d");
            g.reset();
            g.lineCap = "round";
            g.lineJoin = "round";
            g.lineWidth = 5;
            for (const s of win.strokes.concat(win.current ? [win.current] : [])) {
                g.strokeStyle = s.c;
                g.beginPath();
                g.moveTo(s.pts[0], s.pts[1]);
                for (let i = 2; i < s.pts.length; i += 2) g.lineTo(s.pts[i], s.pts[i + 1]);
                g.stroke();
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        onPressed: m => win.current = { c: win.colours[win.colour], line: !!(m.modifiers & Qt.ShiftModifier), pts: [m.x, m.y] }
        onPositionChanged: m => {
            if (!win.current) return;
            win.current.pts = win.current.line ? [win.current.pts[0], win.current.pts[1], m.x, m.y] : win.current.pts.concat([m.x, m.y]);
            canvas.requestPaint();
        }
        onReleased: win.commit()
    }
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) Ui.annotate = false;
            else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_5) win.colour = e.key - Qt.Key_1;
            else if (e.key === Qt.Key_Z) win.undo();
            else if (e.key === Qt.Key_E) win.clear();
            else if (e.key === Qt.Key_S) win.save();
            else return;
            e.accepted = true;
        }
    }
    Glass {
        visible: win.hintShown
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        width: row.implicitWidth + 32
        height: 34
        strong: true
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Repeater {
                model: win.colours
                Rectangle {
                    required property string modelData
                    required property int index
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14; radius: 7
                    color: modelData
                    border.width: index === win.colour ? 2 : 0
                    border.color: Theme.text
                }
            }
            Text {
                text: "  Shift: straight line  ·  Z undo  ·  E erase  ·  S save  ·  Esc close"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
            }
        }
    }
}
