// Settings > Power > Battery: how worn the battery is (what it holds today
// against what it held new, and its charge cycles), what it is doing now, the
// charge over the last day or week, and what is using the most power right
// now. bridge/battery.py reads UPower; nothing here is estimated by the shell.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 10
    property bool active: false
    readonly property string tool: Quickshell.env("SHANI_BATTERY_TOOL") || "/usr/lib/shani-shell/battery.py"
    property var info: ({ present: false })
    property var history: []                // [[time, percent, state]]
    property int span: 86400                // the graph: a day or a week
    property var hungry: []                 // [{ name, cpu }]
    visible: info.present === true

    onActiveChanged: if (active) refresh()
    onSpanChanged: if (active) histProc.running = true
    function refresh() {
        infoProc.running = true;
        histProc.running = true;
        hungryProc.running = true;
    }
    Timer { interval: 30000; repeat: true; running: page.active && page.visible; onTriggered: page.refresh() }

    Process {
        id: infoProc
        command: ["python3", page.tool, "info"]
        stdout: StdioCollector { onStreamFinished: { try { page.info = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: histProc
        command: ["python3", page.tool, "history", String(page.span)]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    // upowerd's first rows can be 0 % "unknown" (before it read the battery)
                    page.history = JSON.parse(text).filter(r => r[2] !== "unknown" || r[1] > 0);
                } catch (e) {}
                chart.requestPaint();
            }
        }
    }
    // what is busiest now: a second of top's own measurement, not a lifetime average
    Process {
        id: hungryProc
        // top's %CPU is per core (a busy process on four cores reads 390): divided by the
        // cores, it is the share of the whole processor
        command: ["sh", "-c", 'nproc; top -b -n 2 -d 1 -o %CPU -w 200 | awk "/^top -/{n++} n==2 && \\$1 ~ /^[0-9]+$/ {print \\$9\\"\\t\\"\\$12}" | head -n 6']
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                const lines = text.split("\n");
                const cores = Math.max(1, parseInt(lines.shift()) || 1);
                for (const l of lines) {
                    const [cpu, name] = l.split("\t");
                    if (!name || parseFloat(cpu) < 0.5 || name === "top") continue;
                    seen[name] = (seen[name] || 0) + parseFloat(cpu);
                }
                page.hungry = Object.keys(seen).map(n => ({ name: n, cpu: Math.round(seen[n] / cores) })).sort((a, b) => b.cpu - a.cpu).slice(0, 5);
            }
        }
    }

    function clock(sec) {
        if (sec <= 0) return "";
        const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
        return h > 0 ? Tr.t("%1 h %2 min", h, m) : Tr.t("%1 min", m);
    }
    readonly property real health: info.health || 0
    readonly property string verdict: health >= 80 ? Tr.t("Good") : health >= 60 ? Tr.t("Worn, still fine for a day's use") : Tr.t("Worn: a new battery would last much longer")
    readonly property color healthColour: health >= 80 ? Theme.accent : health >= 60 ? Theme.amber : Theme.danger

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Battery") }

    // ---- health: one number, what it means, and why ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 16
        ColumnLayout {
            spacing: 0
            Text {
                text: Math.round(page.health) + " %"
                color: page.healthColour
                font.family: Theme.font
                font.pixelSize: 34 * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Text { text: Tr.t("health"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Text { text: page.verdict; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale; font.weight: Font.DemiBold }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 8
                radius: 4
                color: Theme.surface3
                Rectangle { width: parent.width * Math.min(1, page.health / 100); height: parent.height; radius: 4; color: page.healthColour }
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Holds %1 Wh of the %2 Wh it held new", page.info.energyFull || 0, page.info.energyDesign || 0)
                    + (page.info.cycles > 0 ? "  ·  " + Tr.t("%1 charge cycles", page.info.cycles) : "")
                color: Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
        }
    }

    // ---- now ----
    Text {
        Layout.fillWidth: true
        text: Math.round(page.info.percent || 0) + " %  ·  "
            + (page.info.state === "charging" ? Tr.t("charging") + (page.info.timeToFull > 0 ? ", " + Tr.t("full in %1", page.clock(page.info.timeToFull)) : "")
               : page.info.state === "discharging" ? Tr.t("on battery") + (page.info.timeToEmpty > 0 ? ", " + Tr.t("about %1 left", page.clock(page.info.timeToEmpty)) : "")
               : page.info.state === "full" ? Tr.t("full") : Tr.t("plugged in, not charging"))
            + (page.info.rate > 0.05 ? "  ·  " + page.info.rate.toFixed(1) + " W" : "")
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }

    // ---- the charge over time (upowerd's own record) ----
    RowLayout {
        Layout.fillWidth: true
        Text { Layout.fillWidth: true; text: Tr.t("Charge"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
        Choice { text: Tr.t("24 hours"); selected: page.span === 86400; onClicked: page.span = 86400 }
        Choice { text: Tr.t("7 days"); selected: page.span === 604800; onClicked: page.span = 604800 }
    }
    Canvas {
        id: chart
        Layout.fillWidth: true
        implicitHeight: 150
        onWidthChanged: requestPaint()
        Connections { target: Theme; function onAccentChanged() { chart.requestPaint(); } }
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height, padL = 30, padB = 18, gw = w - padL - 6, gh = h - padB - 6;
            const now = Date.now() / 1000, from = now - page.span;
            ctx.font = Math.round(10 * Theme.fontScale) + "px " + Theme.font;
            // 0, 50 and 100 %: faint lines, labelled
            for (const v of [0, 50, 100]) {
                const y = 6 + gh * (1 - v / 100);
                ctx.strokeStyle = Theme.alpha(Theme.text, 0.12);
                ctx.lineWidth = 1;
                ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(w - 6, y); ctx.stroke();
                ctx.fillStyle = Theme.faint;
                ctx.fillText(v + "%", 0, y + 3);
            }
            ctx.fillStyle = Theme.faint;
            ctx.fillText(page.span > 86400 ? Tr.t("a week ago") : Tr.t("a day ago"), padL, h - 3);
            ctx.fillText(Tr.t("now"), w - 30, h - 3);
            const pts = page.history.filter(r => r[0] >= from);
            if (pts.length < 2)
                return;
            const X = t => padL + gw * (t - from) / page.span, Y = v => 6 + gh * (1 - v / 100);
            // the area under the line, faint; then the line, accent while charging
            ctx.beginPath();
            ctx.moveTo(X(pts[0][0]), Y(0));
            for (const p of pts) ctx.lineTo(X(p[0]), Y(p[1]));
            ctx.lineTo(X(pts[pts.length - 1][0]), Y(0));
            ctx.closePath();
            ctx.fillStyle = Theme.alpha(Theme.accent, 0.14);
            ctx.fill();
            ctx.lineWidth = 2;
            for (let i = 1; i < pts.length; i++) {
                ctx.strokeStyle = pts[i][2] === "charging" ? Theme.accent : Theme.alpha(Theme.text, 0.75);
                ctx.beginPath(); ctx.moveTo(X(pts[i - 1][0]), Y(pts[i - 1][1])); ctx.lineTo(X(pts[i][0]), Y(pts[i][1])); ctx.stroke();
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.history.filter(r => r[0] >= Date.now() / 1000 - page.span).length < 2
        text: Tr.t("No history yet: the system records the charge as the battery is used.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
    Text {
        Layout.fillWidth: true
        text: Tr.t("Accent: charging. The line: on battery.")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10 * Theme.fontScale
    }

    // ---- what is using the most power right now ----
    Text {
        Layout.fillWidth: true
        visible: page.hungry.length > 0
        text: Tr.t("Busiest right now (processor use, the best guide to what drains the battery)")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Repeater {
        model: page.hungry
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 8
            Text { Layout.preferredWidth: 160; text: modelData.name; color: Theme.text; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Theme.surface3
                Rectangle { width: parent.width * Math.min(1, modelData.cpu / 100); height: parent.height; radius: 3; color: Theme.accent }
            }
            Text { Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight; text: modelData.cpu + " %"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
        }
    }

    // ---- what it is ----
    Text {
        Layout.fillWidth: true
        text: [page.info.technology, [page.info.vendor, page.info.model].filter(x => x).join(" "),
               page.info.voltage > 0 ? page.info.voltage.toFixed(1) + " V" : "",
               page.info.temperature > 0 ? page.info.temperature.toFixed(0) + " °C" : ""].filter(x => x).join("  ·  ")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
