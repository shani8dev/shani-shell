// A birth chart drawn the North Indian way: the houses stay put (the first at
// the top), each house shows its sign's number and the planets in it. Whole
// sign houses: house n holds the n-th sign from the ascendant. The same
// drawing serves D1 and D9 - only the signs given change.
import QtQuick
import qs.Common

Item {
    id: chart
    // the ascendant's sign and each planet's sign: [{ name, sign, retrograde }]
    property string ascendantSign: ""
    property var planets: []
    readonly property var signs: ["Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo", "Libra",
                                  "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"]
    readonly property int ascIndex: signs.indexOf(ascendantSign)
    // where each house's middle sits, as a fraction of the square
    readonly property var centres: [[0.5, 0.25], [0.25, 0.1], [0.1, 0.25], [0.25, 0.5], [0.1, 0.75], [0.25, 0.9],
                                    [0.5, 0.75], [0.75, 0.9], [0.9, 0.75], [0.75, 0.5], [0.9, 0.25], [0.75, 0.1]]
    readonly property var shortNames: ({
        Sun: Tr.t("Su"), Moon: Tr.t("Mo"), Mars: Tr.t("Ma"), Mercury: Tr.t("Me"), Jupiter: Tr.t("Ju"),
        Venus: Tr.t("Ve"), Saturn: Tr.t("Sa"), Rahu: Tr.t("Ra"), Ketu: Tr.t("Ke"),
        Uranus: Tr.t("Ur"), Neptune: Tr.t("Ne"), Pluto: Tr.t("Pl")
    })
    function house(sign) { return ((signs.indexOf(sign) - ascIndex + 12) % 12) + 1; }
    function inHouse(n) {
        return planets.filter(p => house(p.sign) === n)
                      .map(p => (shortNames[p.name] || p.name.slice(0, 2)) + (p.retrograde ? "ᴿ" : ""));
    }

    implicitWidth: Theme.px(340)
    implicitHeight: implicitWidth
    Accessible.role: Accessible.Graphic
    Accessible.name: ascIndex < 0 ? "" : Tr.t("Birth chart, %1 rising", ascendantSign)

    Canvas {
        id: lines
        anchors.fill: parent
        onPaint: {
            const g = getContext("2d"), w = width, h = height;
            g.reset();
            g.strokeStyle = Theme.dim;
            g.lineWidth = Math.max(1, Theme.px(1.2));
            g.strokeRect(0.5, 0.5, w - 1, h - 1);
            g.beginPath();
            g.moveTo(0, 0); g.lineTo(w, h);
            g.moveTo(w, 0); g.lineTo(0, h);
            g.moveTo(w / 2, 0); g.lineTo(w, h / 2); g.lineTo(w / 2, h); g.lineTo(0, h / 2); g.closePath();
            g.stroke();
        }
        Connections { target: Theme; function onDarkTChanged() { lines.requestPaint(); } }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    Repeater {
        model: 12
        Item {
            id: cell
            required property int index
            readonly property int number: index + 1
            readonly property var here: chart.ascIndex < 0 ? [] : chart.inHouse(number)
            x: chart.centres[index][0] * chart.width - width / 2
            y: chart.centres[index][1] * chart.height - height / 2
            width: chart.width * (index === 0 || index === 3 || index === 6 || index === 9 ? 0.3 : 0.2)
            height: col.implicitHeight
            Column {
                id: col
                width: parent.width
                spacing: 0
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: chart.ascIndex >= 0
                    text: String((chart.ascIndex + cell.index) % 12 + 1)     // the sign's number
                    color: cell.index === 0 ? Theme.accent : Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.type("caption")
                    font.weight: cell.index === 0 ? Font.DemiBold : Font.Normal
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: cell.here.join(" ")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.type(chart.width < Theme.px(300) ? "small" : "body")
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
