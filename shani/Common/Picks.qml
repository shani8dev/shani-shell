// A label over a row of choices. options are [{ label, value }] or plain values;
// current is the chosen value (numbers match to 0.001, so 1.25 from a slider
// still lights its chip); picked(value) hands back the new one.
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: picks
    property string label
    property var options: []
    property var current
    signal picked(var value)
    function valueOf(o) { return o !== null && typeof o === "object" ? o.value : o; }
    function isCurrent(v) { return typeof v === "number" && typeof current === "number" ? Math.abs(current - v) < 0.001 : String(current) === String(v); }
    Layout.fillWidth: true
    spacing: 6
    Text { visible: picks.label !== ""; text: picks.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: picks.options
            Choice {
                required property var modelData
                text: modelData !== null && typeof modelData === "object" ? modelData.label : String(modelData)
                selected: picks.isCurrent(picks.valueOf(modelData))
                onClicked: picks.picked(picks.valueOf(modelData))
            }
        }
    }
}
