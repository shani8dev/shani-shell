// Settings > Windows: how niri lays windows out (InputConfig writes it into
// the shell's niri include): the gaps between them, the focus ring, how wide a
// new window opens, whether focus follows the pointer, and animations.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    readonly property var d: Settings.data

    component Picks: ColumnLayout {
        id: picks
        property string label
        property var options: []
        property var current
        signal picked(var value)
        Layout.fillWidth: true
        spacing: 6
        Text { text: picks.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: picks.options
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: String(picks.current) === String(modelData.value)
                    onClicked: picks.picked(modelData.value)
                }
            }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: "Windows" }
    Picks {
        label: "Gaps between windows"
        options: [{ label: "None", value: 0 }, { label: "Small", value: 6 }, { label: "Medium", value: 12 }, { label: "Large", value: 20 }]
        current: page.d.winGaps
        onPicked: v => page.d.winGaps = v
    }
    Picks {
        label: "A new window opens"
        options: [{ label: "A third", value: 0.33333 }, { label: "Half", value: 0.5 }, { label: "Two thirds", value: 0.66667 }, { label: "Full width", value: 1 }]
        current: page.d.winDefaultWidth
        onPicked: v => page.d.winDefaultWidth = v
    }
    Picks {
        label: "Focus ring"
        options: [{ label: "Off", value: 0 }, { label: "Thin", value: 2 }, { label: "Thick", value: 4 }]
        current: page.d.winFocusRing
        onPicked: v => page.d.winFocusRing = v
    }
    SwitchRow { Layout.fillWidth: true; text: "Focus follows the pointer"; hint: "the window under the pointer takes the keyboard"; checked: page.d.winFocusFollowsMouse; onToggled: on => page.d.winFocusFollowsMouse = on }
    SwitchRow { Layout.fillWidth: true; text: "Window animations"; hint: "opening, closing and scrolling (Reduce motion turns the shell's own off)"; checked: page.d.winAnimations; onToggled: on => page.d.winAnimations = on }
    Text {
        Layout.fillWidth: true
        text: "Windows sit side by side in columns that scroll; Mod+R cycles a column's width, Mod+F makes it full, Mod+O shows every workspace."
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
