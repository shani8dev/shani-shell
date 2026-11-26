// A birth chart, drawn the way it is read in India: North Indian (the houses
// stay put, the first at the top, each house shows its sign's number), South
// Indian (the signs stay put, Pisces top-left, the rising sign marked with a
// slash) or East Indian (the signs stay put, Aries top centre and on
// anticlockwise, the corner squares split in two). Whole sign houses. The same drawing serves every divisional
// chart - only the signs given change.
import QtQuick
import qs.Common

Item {
    id: chart
    property string style: "north"          // north | south | east
    property string ascendantSign: ""
    property var planets: []                 // [{ name, sign, retrograde }]
    property var tints: ({})                 // planet name -> colour
    readonly property var signs: ["Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo", "Libra",
                                  "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"]
    readonly property int ascIndex: signs.indexOf(ascendantSign)
    readonly property bool south: style === "south"
    readonly property bool east: style === "east"
    readonly property bool fixedSigns: south || east
    // East: each sign's place as fractions of the square (a centre of its cell,
    // or of its triangle in a split corner), Aries first, anticlockwise
    readonly property var eastCentres: [[0.5, 1/6], [2/9, 1/9], [1/9, 2/9], [1/6, 0.5], [1/9, 7/9], [2/9, 8/9],
                                        [0.5, 5/6], [7/9, 8/9], [8/9, 7/9], [5/6, 0.5], [8/9, 2/9], [7/9, 1/9]]
    // North: each house's middle, as a fraction of the square
    readonly property var northCentres: [[0.5, 0.27], [0.25, 0.11], [0.11, 0.25], [0.27, 0.5], [0.11, 0.75], [0.25, 0.89],
                                         [0.5, 0.73], [0.75, 0.89], [0.89, 0.75], [0.73, 0.5], [0.89, 0.25], [0.75, 0.11]]
    // South: each sign's cell on the 4x4 grid (column, row), Aries first
    readonly property var southCells: [[1, 0], [2, 0], [3, 0], [3, 1], [3, 2], [3, 3], [2, 3], [1, 3], [0, 3], [0, 2], [0, 1], [0, 0]]
    readonly property var shortNames: ({
        Sun: Tr.t("Su"), Moon: Tr.t("Mo"), Mars: Tr.t("Ma"), Mercury: Tr.t("Me"), Jupiter: Tr.t("Ju"),
        Venus: Tr.t("Ve"), Saturn: Tr.t("Sa"), Rahu: Tr.t("Ra"), Ketu: Tr.t("Ke")
    })
    readonly property var signShort: [Tr.t("Ar"), Tr.t("Ta"), Tr.t("Ge"), Tr.t("Cn"), Tr.t("Le"), Tr.t("Vi"),
                                      Tr.t("Li"), Tr.t("Sc"), Tr.t("Sg"), Tr.t("Cp"), Tr.t("Aq"), Tr.t("Pi")]
    function inSign(i) { return planets.filter(p => signs.indexOf(p.sign) === i); }

    implicitWidth: Theme.px(360)
    implicitHeight: implicitWidth
    Accessible.role: Accessible.Graphic
    Accessible.name: ascIndex < 0 ? "" : Tr.t("Birth chart, %1 rising: %2", ascendantSign,
        planets.map(p => p.name + " " + p.sign + (p.retrograde ? " " + Tr.t("retrograde") : "")).join(", "))

    Rectangle { anchors.fill: parent; radius: Theme.radiusSmall; color: Theme.surface1 }

    Canvas {
        id: lines
        anchors.fill: parent
        onPaint: {
            const g = getContext("2d"), w = width, h = height, lw = Math.max(1, Theme.px(1.4));
            g.reset();
            g.lineWidth = lw;
            g.strokeStyle = Theme.dim;
            if (chart.east) {
                const c = w / 3, r = h / 3;
                if (chart.ascIndex >= 0) {
                    // the rising sign's place, tinted (a square or a triangle)
                    const e = chart.eastCentres[chart.ascIndex];
                    g.fillStyle = Theme.accentSoft;
                    g.beginPath(); g.arc(e[0] * w, e[1] * h, Math.min(c, r) * 0.32, 0, 2 * Math.PI); g.fill();
                }
                g.strokeRect(lw / 2, lw / 2, w - lw, h - lw);
                g.beginPath();
                g.moveTo(c, 0); g.lineTo(c, h); g.moveTo(2 * c, 0); g.lineTo(2 * c, h);
                g.moveTo(0, r); g.lineTo(w, r); g.moveTo(0, 2 * r); g.lineTo(w, 2 * r);
                // the corners, each split in two
                g.moveTo(0, 0); g.lineTo(c, r); g.moveTo(w, 0); g.lineTo(2 * c, r);
                g.moveTo(0, h); g.lineTo(c, 2 * r); g.moveTo(w, h); g.lineTo(2 * c, 2 * r);
                g.stroke();
            } else if (!chart.south) {
                // the first house, tinted: the diamond at the top
                g.fillStyle = Theme.accentSoft;
                g.beginPath(); g.moveTo(w / 2, 0); g.lineTo(3 * w / 4, h / 4); g.lineTo(w / 2, h / 2); g.lineTo(w / 4, h / 4); g.closePath(); g.fill();
                g.strokeRect(lw / 2, lw / 2, w - lw, h - lw);
                g.beginPath();
                g.moveTo(0, 0); g.lineTo(w, h); g.moveTo(w, 0); g.lineTo(0, h);
                g.moveTo(w / 2, 0); g.lineTo(w, h / 2); g.lineTo(w / 2, h); g.lineTo(0, h / 2); g.closePath();
                g.stroke();
            } else {
                const c = w / 4, r = h / 4;
                if (chart.ascIndex >= 0) {
                    const cell = chart.southCells[chart.ascIndex];
                    g.fillStyle = Theme.accentSoft;
                    g.fillRect(cell[0] * c, cell[1] * r, c, r);
                    g.beginPath(); g.moveTo(cell[0] * c, cell[1] * r + r * 0.35); g.lineTo(cell[0] * c + c * 0.35, cell[1] * r);
                    g.strokeStyle = Theme.accent; g.stroke(); g.strokeStyle = Theme.dim;
                }
                g.strokeRect(lw / 2, lw / 2, w - lw, h - lw);
                g.beginPath();
                for (let i = 1; i < 4; i++) {
                    g.moveTo(i * c, 0); g.lineTo(i * c, i === 2 ? r : h);
                    g.moveTo(0, i * r); g.lineTo(i === 2 ? c : w, i * r);
                }
                // the middle is one empty square
                g.moveTo(2 * c, 3 * r); g.lineTo(2 * c, h);
                g.moveTo(3 * c, 2 * r); g.lineTo(w, 2 * r);
                g.stroke();
            }
        }
        Connections { target: Theme; function onDarkTChanged() { lines.requestPaint(); } }
        Connections { target: chart; function onStyleChanged() { lines.requestPaint(); } function onAscendantSignChanged() { lines.requestPaint(); } }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    // what sits in each house (North) or sign (South)
    Repeater {
        model: 12
        Item {
            id: cell
            required property int index
            // the sign this place shows
            readonly property int sign: chart.fixedSigns ? index : (chart.ascIndex < 0 ? -1 : (chart.ascIndex + index) % 12)
            readonly property var here: sign < 0 ? [] : chart.inSign(sign)
            readonly property real cx: chart.east ? chart.eastCentres[index][0] : chart.south ? (chart.southCells[index][0] + 0.5) / 4 : chart.northCentres[index][0]
            readonly property real cy: chart.east ? chart.eastCentres[index][1] : chart.south ? (chart.southCells[index][1] + 0.5) / 4 : chart.northCentres[index][1]
            width: chart.width * (chart.east ? (index % 3 === 0 ? 0.3 : 0.18) : chart.south ? 0.24 : (index % 3 === 0 ? 0.3 : 0.19))
            height: col.implicitHeight
            x: cx * chart.width - width / 2
            y: cy * chart.height - height / 2
            Column {
                id: col
                width: parent.width
                spacing: Theme.px(1)
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: cell.sign >= 0
                    text: chart.fixedSigns ? chart.signShort[cell.sign] + (cell.sign === chart.ascIndex ? "  " + Tr.t("Asc") : "")
                                      : String(cell.sign + 1)
                    color: (chart.fixedSigns ? cell.sign === chart.ascIndex : cell.index === 0) ? Theme.accent : Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.type("caption")
                    font.weight: (chart.fixedSigns ? cell.sign === chart.ascIndex : cell.index === 0) ? Font.DemiBold : Font.Normal
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    text: cell.here.map(p => "<font color=\"" + String(chart.tints[p.name] || Theme.text) + "\">"
                        + (chart.shortNames[p.name] || String(p.name).slice(0, 2))
                        + (p.retrograde && ["Rahu", "Ketu"].indexOf(p.name) < 0 ? "ᴿ" : "") + "</font>").join("&nbsp; ")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.type(chart.width < Theme.px(320) ? "small" : "body")
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
