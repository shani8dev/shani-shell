// Settings > Screen time: where the day went - today by app, the week day by
// day - and the gentle reminders (a break, a daily total), told and never
// enforced. As in macOS's and Android's Settings. The minutes are
// Services/ScreenTime's, counted on this computer only.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    property var d: Settings.data

    // the last seven days, oldest first: [{ day "Mon", key "YYYY-MM-DD", total }]
    readonly property var week: {
        const out = [];
        for (let i = 6; i >= 0; i--) {
            const d = new Date(Date.now() - i * 86400000);
            const key = Qt.formatDate(d, "yyyy-MM-dd");
            const apps = ScreenTime.days[key] || {};
            out.push({ day: Qt.formatDate(d, "ddd"), key: key, total: Object.values(apps).reduce((a, b) => a + b, 0) });
        }
        return out;
    }
    readonly property int most: Math.max(3600, ...week.map(d => d.total))   // an hour at least: a few minutes is not a full bar
    readonly property var byApp: Object.entries(ScreenTime.todayByApp).sort((a, b) => b[1] - a[1])


    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Screen time")
        hint: Tr.t("how long each app is in front, kept on this computer")
        checked: page.d.screenTime
        onToggled: on => page.d.screenTime = on
    }

    Text {
        visible: page.d.screenTime
        text: Tr.t("Today") + "  ·  " + ScreenTime.label(ScreenTime.todayTotal)
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.type("subtitle")
        font.weight: Font.DemiBold
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.px(120)
        visible: page.d.screenTime
        spacing: Theme.px(8)
        Repeater {
            model: page.week
            ColumnLayout {
                id: dayCol
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.px(4)
                Accessible.role: Accessible.StaticText
                Accessible.name: dayCol.modelData.day + ": " + ScreenTime.label(dayCol.modelData.total)
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(34, parent.width)
                        height: Math.max(3, parent.height * dayCol.modelData.total / page.most)
                        radius: Theme.px(4)
                        color: dayCol.index === 6 ? Theme.accent : Theme.surface3
                    }
                }
                Text { Layout.alignment: Qt.AlignHCenter; text: dayCol.modelData.day; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small") }
            }
        }
    }
    SettingsSection {
        Layout.fillWidth: true
        visible: page.d.screenTime && page.byApp.length > 0
        title: Tr.t("Today, by app")
        Repeater {
            model: page.d.screenTime ? page.byApp.slice(0, 8) : []
            RowLayout {
                id: appRow
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.px(10)
                Text { Layout.preferredWidth: Theme.px(170); text: appRow.modelData[0]; color: Theme.text; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: Theme.type("body") }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(6)
                    radius: Theme.px(3)
                    color: Theme.surface3
                    Rectangle { width: parent.width * appRow.modelData[1] / Math.max(1, page.byApp[0][1]); height: parent.height; radius: Theme.px(3); color: Theme.accent }
                }
                Text { Layout.preferredWidth: Theme.px(80); horizontalAlignment: Text.AlignRight; text: ScreenTime.label(appRow.modelData[1]); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("body") }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: page.d.screenTime
        title: Tr.t("Reminders")
        Text { visible: page.d.screenTime; text: Tr.t("Remind me to take a break"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("body") }
        Flow {
            visible: page.d.screenTime
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: [0, 20, 30, 45, 60, 90]
                Choice { required property int modelData; text: modelData ? Tr.t("every %1 min", modelData) : Tr.t("Never"); selected: page.d.breakEveryMinutes === modelData; onClicked: page.d.breakEveryMinutes = modelData }
            }
        }
        Text { visible: page.d.screenTime; text: Tr.t("Daily screen time reminder"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("body") }
        Flow {
            visible: page.d.screenTime
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: [0, 120, 240, 360, 480, 600]
                Choice { required property int modelData; text: modelData ? Tr.t("%1 h", modelData / 60) : Tr.t("Off"); selected: page.d.screenLimitMinutes === modelData; onClicked: page.d.screenLimitMinutes = modelData }
            }
        }
    }
}
