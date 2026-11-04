// A world map you click to pick a time zone — the setup wizard's time page
// and Settings > Date & language both use it (setup/ reaches it through its
// Common symlink, so it works before any settings exist).
//
// Equirectangular, drawn from world-land.js (Natural Earth 1:110m land,
// public domain) in the shell's own colours: the sea is the card and the land
// is the accent, so it belongs to whatever palette is in use. Clicking
// anywhere picks the zone whose representative city (zone1970.tab) is nearest.
// Give it `zone`; it marks that zone's city and says zonePicked(name) on a click.
import QtQuick
import Quickshell.Io
import qs.Common
import "world-land.js" as World

Item {
    id: map
    property string zone: ""
    property var points: []              // [{zone, lat, lon, city}] from zone1970.tab
    // the chosen zone's city, or null
    readonly property var point: { for (const p of map.points) if (p.zone === map.zone) return p; return null; }
    readonly property real lat: point ? point.lat : 0
    readonly property real lon: point ? point.lon : 0
    readonly property string label: point ? point.city : ""
    readonly property bool showMarker: point !== null
    // the projection is cropped at the poles: Antarctica's coastline is a
    // full-width bar in equirectangular and nothing lives there; 84 north
    // still reaches the last settlements
    readonly property real latTop: 84
    readonly property real latBottom: -60
    readonly property real aspect: 360 / (latTop - latBottom)
    signal zonePicked(string zone)
    // the zone whose city is nearest — longitude narrowed towards the poles,
    // where a degree is shorter
    function nearest(lat, lon) {
        let best = null, dist = 1e9;
        for (const p of map.points) {
            const dLon = Math.abs(p.lon - lon);
            const dx = Math.min(dLon, 360 - dLon) * Math.cos(lat * Math.PI / 180);
            const dy = p.lat - lat;
            const d = dx * dx + dy * dy;
            if (d < dist) { dist = d; best = p; }
        }
        return best ? best.zone : "";
    }
    Process {
        running: true
        command: ["sh", "-c", 'cat /usr/share/zoneinfo/zone1970.tab 2>/dev/null || cat /usr/share/zoneinfo/zone.tab 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                // "IN	+2232+08822	Asia/Kolkata	India"
                const out = [];
                for (const line of text.split("\n")) {
                    const f = line.charAt(0) === "#" ? [] : line.split("\t");
                    const m = f.length >= 3 ? /^([+-])(\d{2})(\d{2})([+-])(\d{3})(\d{2})$/.exec(f[1]) : null;
                    if (m)
                        out.push({ zone: f[2], city: f[2].split("/").pop().replace(/_/g, " "),
                                   lat: (parseInt(m[2]) + parseInt(m[3]) / 60) * (m[1] === "-" ? -1 : 1),
                                   lon: (parseInt(m[5]) + parseInt(m[6]) / 60) * (m[4] === "-" ? -1 : 1) });
                }
                map.points = out;
            }
        }
    }

    readonly property real px: (map.lon + 180) / 360 * map.width
    readonly property real py: (map.latTop - map.lat) / (map.latTop - map.latBottom) * map.height

    function lonAt(x) { return Math.max(-180, Math.min(180, x / Math.max(1, map.width) * 360 - 180)); }
    function latAt(y) { return Math.max(map.latBottom, Math.min(map.latTop, map.latTop - y / Math.max(1, map.height) * (map.latTop - map.latBottom))); }

    Accessible.role: Accessible.Pane
    Accessible.name: map.label === "" ? qsTr("World map — click where you are")
                                      : map.label + qsTr(" on the world map")

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: Theme.alpha(Theme.bg, 0.58)
        border.width: 1
        border.color: Theme.stroke
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: 2
        onPaint: draw()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: Theme
            function onAccentChanged() { canvas.requestPaint() }
            function onDarkChanged() { canvas.requestPaint() }
        }

        function css(c, a) {
            return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," +
                   Math.round(c.b * 255) + "," + a + ")";
        }

        function draw() {
            const ctx = getContext("2d");
            const w = width, h = height;
            if (w < 8 || h < 8)
                return;
            ctx.clearRect(0, 0, w, h);
            const X = l => (l + 180) / 360 * w;
            const Y = l => (map.latTop - l) / (map.latTop - map.latBottom) * h;

            // graticule: every 30 degrees, the equator and prime meridian stronger
            ctx.lineWidth = 1;
            for (let l = -150; l <= 150; l += 30) {
                if (l === 0)
                    continue;
                ctx.strokeStyle = css(Theme.text, 0.07);
                ctx.beginPath();
                ctx.moveTo(X(l), 0);
                ctx.lineTo(X(l), h);
                ctx.stroke();
            }
            for (let la = -60; la <= 60; la += 30) {
                if (la === 0)
                    continue;
                ctx.strokeStyle = css(Theme.text, 0.07);
                ctx.beginPath();
                ctx.moveTo(0, Y(la));
                ctx.lineTo(w, Y(la));
                ctx.stroke();
            }
            ctx.strokeStyle = css(Theme.text, 0.12);
            ctx.beginPath();
            ctx.moveTo(0, Y(0));
            ctx.lineTo(w, Y(0));
            ctx.moveTo(X(0), 0);
            ctx.lineTo(X(0), h);
            ctx.stroke();

            // the land, one path
            ctx.beginPath();
            for (const ring of World.rings) {
                ctx.moveTo(X(ring[0][0]), Y(ring[0][1]));
                for (let i = 1; i < ring.length; i++)
                    ctx.lineTo(X(ring[i][0]), Y(ring[i][1]));
                ctx.closePath();
            }
            ctx.fillStyle = css(Theme.accent, 0.30);
            ctx.fill();
            ctx.lineWidth = 0.8;
            ctx.strokeStyle = css(Theme.accent, 0.80);
            ctx.stroke();
        }
    }

    // the marker: a pulse and a dot, so the chosen city is obvious
    Rectangle {
        visible: map.showMarker
        x: map.px - width / 2
        y: map.py - height / 2
        width: 26
        height: 26
        radius: 13
        color: "transparent"
        border.width: 2
        border.color: Theme.alpha(Theme.accent, 0.65)
        opacity: 0
        SequentialAnimation on opacity {
            running: map.showMarker && !Settings.data.reduceMotion
            loops: Animation.Infinite
            NumberAnimation { from: 0.75; to: 0; duration: 1800; easing.type: Easing.OutQuad }
        }
        SequentialAnimation on scale {
            running: map.showMarker && !Settings.data.reduceMotion
            loops: Animation.Infinite
            NumberAnimation { from: 0.55; to: 1.5; duration: 1800; easing.type: Easing.OutQuad }
        }
    }
    Rectangle {
        visible: map.showMarker
        x: map.px - width / 2
        y: map.py - height / 2
        width: 11
        height: 11
        radius: 6
        color: Theme.accent
        border.width: 2
        border.color: Theme.accentInk
    }

    // the city, in a small pill beside the dot (kept inside the map)
    Rectangle {
        visible: map.showMarker && map.label !== ""
        height: 22
        width: cityLabel.implicitWidth + 16
        radius: 11
        x: Math.max(4, Math.min(map.width - width - 4, map.px + 12))
        y: map.py > map.height / 2 ? map.py - height - 8 : map.py + 8
        color: Theme.alpha(Theme.bg, 0.82)
        border.width: 1
        border.color: Theme.accentLine
        Text {
            id: cityLabel
            anchors.centerIn: parent
            text: map.label
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 11 * Theme.fontScale
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { const z = map.nearest(map.latAt(mouse.y), map.lonAt(mouse.x)); if (z) map.zonePicked(z); }
    }

}
