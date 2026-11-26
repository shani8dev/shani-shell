// Draw on the screen (ZoomIt, Windows Ink's screen sketch, macOS Markup):
// a clear layer over whatever is shown, to point things out in a call or a
// recording. Drag draws; a tool palette offers pen, rectangle, ellipse, arrow,
// text and highlight. Shift+drag a straight line; 1-5 pick a colour, [ and ]
// change the width, Z undo, Ctrl+Y redo, E erase all, S save (and copy), Esc
// closes. The layer is live, not a frozen frame, so video keeps moving.
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
    WlrLayershell.keyboardFocus: (visible) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var colours: ["#e5484d", "#f5d90a", "#46a758", "#0091ff", "#ffffff"]
    property int colour: 0
    readonly property var tools: ["pen", "rect", "ellipse", "arrow", "text", "highlight"]
    readonly property var widths: [2, 5, 12]
    readonly property var toolIcons: ["document-edit", "draw-rectangle", "draw-ellipse", "go-next", "edit-insert", "format-text-highlight"]
    property string tool: "pen"
    property int widthStep: 1
    property real strokeWidth: widths[widthStep]
    property var strokes: []            // [{ c, k, w, pts: [x, y, …], text }]
    property var current: null
    property var redoStack: []
    property var textStroke: null
    property bool hintShown: true
    onVisibleChanged: {
        if (visible) { keys.forceActiveFocus(); hintShown = true; }
        else { strokes = []; current = null; redoStack = []; textBox.visible = false; canvas.requestPaint(); }
        Ui.annotateStrokes = 0;
    }
    // made when opened (shell.qml's LazyLoader)
    Component.onCompleted: if (visible) keys.forceActiveFocus()
    Component.onDestruction: Ui.annotateStrokes = 0

    function setTool(t) {
        if (tools.indexOf(t) === -1) return;
        if (textBox.visible) finishText();
        tool = t; current = null; canvas.requestPaint();
    }
    function commit() {
        if (current) {
            const k = current.k;
            if (k === "text") {
                if (current.text && current.text.trim()) strokes = strokes.concat([current]);
            } else if (current.pts.length >= 4) strokes = strokes.concat([current]);
        }
        current = null;
        redoStack = [];
        Ui.annotateStrokes = strokes.length;
        canvas.requestPaint();
    }
    function undo() {
        if (!strokes.length) return;
        redoStack = redoStack.concat([strokes[strokes.length - 1]]);
        strokes = strokes.slice(0, -1);
        Ui.annotateStrokes = strokes.length;
        canvas.requestPaint();
    }
    function redo() {
        if (!redoStack.length) return;
        strokes = strokes.concat([redoStack[redoStack.length - 1]]);
        redoStack = redoStack.slice(0, -1);
        Ui.annotateStrokes = strokes.length;
        canvas.requestPaint();
    }
    function clear() { strokes = []; current = null; redoStack = []; Ui.annotateStrokes = 0; canvas.requestPaint(); }
    function beginText(x, y) {
        textStroke = { c: colours[colour], k: "text", w: strokeWidth, pts: [x, y], text: "" };
        textBox.x = x; textBox.y = Math.max(0, y - textBox.height);
        textBox.visible = true; textEntry.text = ""; textEntry.forceActiveFocus();
    }
    function finishText() {
        if (textStroke) {
            textStroke.text = textEntry.text;
            if (textStroke.text.trim()) { strokes = strokes.concat([textStroke]); redoStack = []; }
            textStroke = null;
            Ui.annotateStrokes = strokes.length;
        }
        textBox.visible = false;
        canvas.requestPaint();
    }
    function save() {
        // the hint hides first, so the picture is the screen and the drawing only
        hintShown = false;
        hintBack.restart();
        const fmt = Settings.data.screenshotFormat === "jpeg" ? "jpeg" : Settings.data.screenshotFormat === "webp" ? "webp" : "png";
        const q = String(Math.max(1, Math.min(100, Settings.data.screenshotQuality)));
        const cf = Settings.data.clipboardOutputFormat === "jpeg" || Settings.data.clipboardOutputFormat === "webp" ? Settings.data.clipboardOutputFormat : fmt;
        Qt.callLater(() => Quickshell.execDetached(["sh", "-c",
            'sleep 0.15; d="${2:-${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots}"; case "$d" in "~"*) d="$HOME${d#"~"}";; esac; mkdir -p "$d" || exit 1; b="$d/Drawing $(date "+%F %H-%M-%S")"; case "$3" in webp) t=$(mktemp "${d}/.draw-XXXXXX.png") || exit 1; grim -o "$1" "$t" || { rm -f "$t"; exit 1; }; f="$b.webp"; if command -v magick >/dev/null 2>&1; then magick "$t" -quality "$4" "$f"; elif command -v convert >/dev/null 2>&1; then convert "$t" -quality "$4" "$f"; else f="$b.png"; mv "$t" "$f"; fi; rm -f "$t"; [ -s "$f" ] || { f="$b.png"; };; jpeg) f="$b.jpg"; grim -o "$1" -t jpeg -q "$4" "$f" || exit 1;; *) f="$b.png"; grim -o "$1" "$f" || exit 1;; esac; if [ "$5" = "$3" ]; then wl-copy --type "image/$3" < "$f"; else t2=$(mktemp "${d}/.clip-XXXXXX"); if command -v magick >/dev/null 2>&1 && magick "$f" -quality "$4" "$t2" 2>/dev/null; then wl-copy --type "image/$5" < "$t2"; elif command -v convert >/dev/null 2>&1 && convert "$f" -quality "$4" "$t2" 2>/dev/null; then wl-copy --type "image/$5" < "$t2"; else wl-copy --type "image/$3" < "$f"; fi; rm -f "$t2"; fi; notify-send -a Screenshot -i "$f" "Drawing saved" "Saved and copied — ${f##*/}"',
            "sh", win.screen ? win.screen.name : "", Settings.data.screenshotDir || "", fmt, q, cf]));
    }
    // the save only hid the toolbar for the capture: bring it back, or the
    // colour/undo/save buttons stay gone for the rest of this session
    // shortcut: fixed 700ms restore (capture script sleeps 0.15s then runs grim); raise if a large display captures slower
    Timer { id: hintBack; interval: 700; onTriggered: win.hintShown = true }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const g = getContext("2d");
            g.reset();
            g.lineCap = "round";
            g.lineJoin = "round";
            for (const s of win.strokes.concat(win.current ? [win.current] : [])) {
                const k = s.k || "pen";
                const lw = s.w || Theme.px(5);
                g.globalAlpha = 1;
                g.lineWidth = lw;
                g.strokeStyle = s.c;
                g.fillStyle = s.c;
                if (k === "highlight") {
                    g.globalAlpha = 0.35;
                    g.lineWidth = lw * 3;
                }
                if (k !== "text" && s.pts.length < 4) continue;
                if (k === "rect") {
                    g.strokeRect(s.pts[0], s.pts[1], s.pts[2] - s.pts[0], s.pts[3] - s.pts[1]);
                } else if (k === "ellipse") {
                    g.beginPath();
                    g.ellipse((s.pts[0] + s.pts[2]) / 2, (s.pts[1] + s.pts[3]) / 2,
                              Math.abs(s.pts[2] - s.pts[0]) / 2, Math.abs(s.pts[3] - s.pts[1]) / 2,
                              0, 0, Math.PI * 2);
                    g.stroke();
                } else if (k === "arrow") {
                    const x0 = s.pts[0], y0 = s.pts[1], x1 = s.pts[2], y1 = s.pts[3];
                    g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke();
                    const a = Math.atan2(y1 - y0, x1 - x0), h = Math.max(8, lw * 3);
                    g.beginPath();
                    g.moveTo(x1, y1);
                    g.lineTo(x1 - h * Math.cos(a - 0.5), y1 - h * Math.sin(a - 0.5));
                    g.moveTo(x1, y1);
                    g.lineTo(x1 - h * Math.cos(a + 0.5), y1 - h * Math.sin(a + 0.5));
                    g.stroke();
                } else if (k === "text") {
                    const size = Math.max(14, lw * 4);
                    g.font = size + "px " + Theme.font;
                    g.fillText(s.text || "", s.pts[0], s.pts[1] + size);
                } else {
                    g.beginPath();
                    g.moveTo(s.pts[0], s.pts[1]);
                    for (let i = 2; i < s.pts.length; i += 2) g.lineTo(s.pts[i], s.pts[i + 1]);
                    g.stroke();
                }
            }
            g.globalAlpha = 1;
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        onPressed: m => {
            if (textBox.visible) win.finishText();
            if (win.tool === "text") { win.beginText(m.x, m.y); return; }
            win.current = { c: win.colours[win.colour], k: win.tool, w: win.strokeWidth,
                            line: !!(m.modifiers & Qt.ShiftModifier) || win.tool === "arrow",
                            pts: [m.x, m.y] };
        }
        onPositionChanged: m => {
            if (!win.current) return;
            const k = win.current.k;
            if (k === "pen" || k === "highlight")
                win.current.pts = win.current.pts.concat([m.x, m.y]);
            else
                win.current.pts = [win.current.pts[0], win.current.pts[1], m.x, m.y];
            canvas.requestPaint();
        }
        onReleased: win.commit()
    }

    // inline editor for the text tool (TextInput keeps this layer dependency-free)
    Rectangle {
        id: textBox
        visible: false
        z: 5
        width: Theme.px(240); height: Theme.px(32)
        color: Theme.surface1
        border.color: Theme.accent
        border.width: 1
        radius: Theme.radiusSmall
        TextInput {
            id: textEntry
            anchors.fill: parent
            anchors.margins: Theme.px(4)
            color: win.colours[win.colour]
            font.family: Theme.font
            font.pixelSize: Theme.type("heading")
            onAccepted: win.finishText()
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) Ui.annotate = false;
            else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_5) win.colour = e.key - Qt.Key_1;
            else if (e.key === Qt.Key_Z && (e.modifiers & Qt.ControlModifier) && (e.modifiers & Qt.ShiftModifier)) win.redo();
            else if (e.key === Qt.Key_Z && (e.modifiers & Qt.ControlModifier)) win.undo();
            else if (e.key === Qt.Key_Y && (e.modifiers & Qt.ControlModifier)) win.redo();
            else if (e.key === Qt.Key_Z) win.undo();
            else if (e.key === Qt.Key_Y) win.redo();
            else if (e.key === Qt.Key_E) win.clear();
            else if (e.key === Qt.Key_S) win.save();
            else if (e.key === Qt.Key_P) win.setTool("pen");
            else if (e.key === Qt.Key_R) win.setTool("rect");
            else if (e.key === Qt.Key_O) win.setTool("ellipse");
            else if (e.key === Qt.Key_A) win.setTool("arrow");
            else if (e.key === Qt.Key_T) win.setTool("text");
            else if (e.key === Qt.Key_H) win.setTool("highlight");
            else if (e.key === Qt.Key_BracketLeft) win.widthStep = Math.max(0, win.widthStep - 1);
            else if (e.key === Qt.Key_BracketRight) win.widthStep = Math.min(win.widths.length - 1, win.widthStep + 1);
            else return;
            e.accepted = true;
        }
    }
    Glass {
        visible: win.hintShown
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.px(40)
        width: row.implicitWidth + 32
        height: Theme.px(34)
        strong: true
        Accessible.role: Accessible.Dialog
        Accessible.name: Tr.t("Screen annotation toolbar")
        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.px(8)
            Repeater {
                model: win.tools
                IconButton {
                    required property string modelData
                    required property int index
                    icon: win.toolIcons[index]
                    size: Theme.px(22)
                    opacity: win.tool === modelData ? 1.0 : 0.6
                    tip: Tr.t("Tool: %1", modelData)
                    accessibleName: Tr.t("Draw %1", modelData)
                    onClicked: win.setTool(modelData)
                }
            }
            Repeater {
                model: win.colours
                Rectangle {
                    required property string modelData
                    required property int index
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.px(26); height: Theme.px(26); radius: Theme.px(13)
                    color: modelData
                    border.width: index === win.colour ? 2 : 0
                    border.color: Theme.text
                    // colours were keyboard-only: a pointer user could not pick one
                    MouseArea {
                        anchors.fill: parent
                        onClicked: win.colour = parent.index
                    }
                }
            }
            IconButton {
                icon: "format-text-bold"; size: Theme.px(22)
                tip: Tr.t("Stroke width"); accessibleName: Tr.t("Change the stroke width")
                onClicked: win.widthStep = (win.widthStep + 1) % win.widths.length
            }
            IconButton { icon: "edit-undo"; tip: Tr.t("Undo") + " (Z)"; accessibleName: Tr.t("Undo the last mark"); onClicked: win.undo() }
            IconButton { icon: "edit-redo"; tip: Tr.t("Redo") + " (Ctrl+Y)"; accessibleName: Tr.t("Redo the last undone mark"); onClicked: win.redo() }
            IconButton { icon: "draw-eraser"; tip: Tr.t("Erase") + " (E)"; accessibleName: Tr.t("Erase all marks"); onClicked: win.clear() }
            IconButton { icon: "document-save"; tip: Tr.t("Save") + " (S)"; accessibleName: Tr.t("Save and copy the drawing"); onClicked: win.save() }
            Text {
                text: Tr.t("  1-5 colour  ·  [ ] width  ·  P R O A T H tools  ·  Shift: straight line  ·  Z undo  ·  Ctrl+Y redo  ·  E erase  ·  S save  ·  Esc close")
                      + (Ui.annotateStrokes === 0 ? Tr.t("  ·  Drag to draw") : "")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.type("body")
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }
}
