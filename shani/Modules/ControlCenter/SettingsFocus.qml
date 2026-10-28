// Settings > Notifications > Focus modes: what each mode does and when —
// its schedule (days and hours), the apps whose notifications still come
// through, and whether it warms the screen or keeps it awake. Edits replace
// the mode in Settings.focusModes; Focus picks them up on its next check.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    readonly property var d: Settings.data
    readonly property var dayNames: ["S", "M", "T", "W", "T", "F", "S"]

    function update(i, patch) {
        const modes = JSON.parse(JSON.stringify(Array.from(d.focusModes)));
        modes[i] = Object.assign(modes[i], patch);
        d.focusModes = modes;
    }
    function updateSchedule(i, patch) {
        const sc = Object.assign({ days: [], from: "", to: "", on: false }, JSON.parse(JSON.stringify(d.focusModes[i].schedule || {})), patch);
        update(i, { schedule: sc });
    }

    SectionTitle { Layout.fillWidth: true; text: "Focus modes" }
    Repeater {
        model: page.d.focusModes
        ColumnLayout {
            id: mode
            required property var modelData
            required property int index
            readonly property var sc: modelData.schedule || { days: [], from: "", to: "", on: false }
            Layout.fillWidth: true
            spacing: 6
            RowLayout {
                spacing: 8
                Icon { name: mode.modelData.icon || "weather-clear-night"; size: 18; color: Theme.accent }
                Text { text: mode.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 * Theme.fontScale; font.weight: Font.DemiBold }
            }
            SwitchRow {
                Layout.fillWidth: true
                text: "On a schedule"
                hint: mode.sc.on ? mode.sc.from + " to " + mode.sc.to : "only when chosen"
                checked: mode.sc.on
                onToggled: on => page.updateSchedule(mode.index, { on: on, from: mode.sc.from || "09:00", to: mode.sc.to || "17:00",
                                                                    days: mode.sc.days.length ? mode.sc.days : [1, 2, 3, 4, 5] })
            }
            RowLayout {
                visible: mode.sc.on
                spacing: 4
                Repeater {
                    model: 7
                    Choice {
                        required property int index
                        readonly property bool on: Array.from(mode.sc.days).indexOf(index) >= 0
                        text: page.dayNames[index]
                        selected: on
                        Accessible.name: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][index]
                        onClicked: page.updateSchedule(mode.index, { days: on ? Array.from(mode.sc.days).filter(x => x !== index)
                                                                              : Array.from(mode.sc.days).concat([index]).sort() })
                    }
                }
            }
            RowLayout {
                visible: mode.sc.on
                spacing: 8
                Text { text: "From"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                TextField {
                    Layout.preferredWidth: 90
                    text: mode.sc.from
                    placeholder: "09:00"
                    onAccepted: if (/^\d\d?:\d\d$/.test(text.trim())) page.updateSchedule(mode.index, { from: text.trim() })
                }
                Text { text: "to"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                TextField {
                    Layout.preferredWidth: 90
                    text: mode.sc.to
                    placeholder: "17:00"
                    onAccepted: if (/^\d\d?:\d\d$/.test(text.trim())) page.updateSchedule(mode.index, { to: text.trim() })
                }
            }
            Text {
                visible: page.d.notifApps.length > 0
                text: "Notifications that still come through:"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: page.d.notifApps
                    Choice {
                        required property string modelData
                        readonly property bool on: Array.from(mode.modelData.allow || []).indexOf(modelData) >= 0
                        text: modelData
                        selected: on
                        onClicked: page.update(mode.index, { allow: on ? Array.from(mode.modelData.allow || []).filter(x => x !== modelData)
                                                                       : Array.from(mode.modelData.allow || []).concat([modelData]) })
                    }
                }
            }
            SwitchRow { Layout.fillWidth: true; text: "Night light while on"; checked: !!mode.modelData.nightLight; onToggled: on => page.update(mode.index, { nightLight: on }) }
            SwitchRow { Layout.fillWidth: true; text: "Keep the screen awake"; checked: !!mode.modelData.caffeine; onToggled: on => page.update(mode.index, { caffeine: on }) }
        }
    }
}
