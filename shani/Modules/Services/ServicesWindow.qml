// Services: the person's own units, timers and scheduled jobs — start, stop,
// enable, disable; add and remove cron entries. `systemctl --user` and crontab
// only, so no root and no assistant tool is needed. bridge/services.py owns the
// commands; this window is the view.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Services"
    visible: Ui.servicesApp
    onGone: Ui.servicesApp = false
    implicitWidth: Theme.px(860)
    implicitHeight: Theme.px(640)

    tools: [
        IconButton { icon: "view-refresh"; tip: Tr.t("Refresh"); size: Theme.px(26); on: SysServices.busy; onClicked: SysServices.refresh() }
    ]

    onVisibleChanged: if (visible) SysServices.refresh()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(12)
        spacing: Theme.px(10)

        RowLayout {
            Layout.fillWidth: true
            Repeater {
                model: ["services", "timers", "cron"]
                Choice {
                    required property string modelData
                    text: modelData === "services" ? Tr.t("Services") : modelData === "timers" ? Tr.t("Timers") : Tr.t("Scheduled jobs")
                    selected: SysServices.tab === modelData
                    onClicked: SysServices.setTab(modelData)
                }
            }
            Item { Layout.fillWidth: true }
        }

        Text {
            Layout.fillWidth: true
            visible: SysServices.note !== ""
            text: SysServices.note
            color: Theme.danger
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }

        // ---- services -------------------------------------------------------
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: SysServices.tab === "services"
            clip: true
            spacing: Theme.px(2)
            model: SysServices.services
            delegate: ListRow {
                required property var modelData
                width: ListView.view.width
                icon: modelData.active === "active" ? "dialog-ok" : "dialog-information"
                title: modelData.unit
                subtitle: [modelData.active, modelData.enabled, modelData.description].filter(x => x).join("  ·  ")
                extra: RowLayout {
                    spacing: Theme.px(4)
                    Button { text: modelData.active === "active" ? Tr.t("Stop") : Tr.t("Start"); flat: true; onClicked: SysServices.unit(modelData.unit, modelData.active === "active" ? "stop" : "start") }
                    Button { text: modelData.enabled === "enabled" ? Tr.t("Disable") : Tr.t("Enable"); flat: true; onClicked: SysServices.unit(modelData.unit, modelData.enabled === "enabled" ? "disable" : "enable") }
                }
            }
        }

        // ---- timers ---------------------------------------------------------
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: SysServices.tab === "timers"
            clip: true
            spacing: Theme.px(2)
            model: SysServices.timers
            delegate: ListRow {
                required property var modelData
                width: ListView.view.width
                icon: "preferences-system-time"
                title: modelData.unit
                subtitle: [modelData.next, modelData.left, modelData.description].filter(x => x).join("  ·  ")
                extra: RowLayout {
                    spacing: Theme.px(4)
                    Button { text: Tr.t("Stop"); flat: true; onClicked: SysServices.unit(modelData.unit, "stop") }
                    Button { text: Tr.t("Disable"); flat: true; onClicked: SysServices.unit(modelData.unit, "disable") }
                }
            }
        }

        // ---- cron: the C and D of CRUD -------------------------------------
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: SysServices.tab === "cron"
            clip: true
            spacing: Theme.px(2)
            model: SysServices.cron
            delegate: ListRow {
                required property var modelData
                width: ListView.view.width
                icon: "preferences-system-time"
                title: modelData.line
                subtitle: Tr.t("Entry %1", modelData.index + 1)
                extra: Button { text: Tr.t("Remove"); flat: true; kind: "danger"; onClicked: SysServices.cronRemove(modelData.index) }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: SysServices.tab === "cron"
            spacing: Theme.px(6)
            TextField { id: sched; Layout.fillWidth: true; placeholder: Tr.t("Schedule, e.g. 0 9 * * 1-5"); label: Tr.t("When") }
            TextField { id: cmd; Layout.fillWidth: true; placeholder: Tr.t("The command to run"); label: Tr.t("What") }
            Button {
                text: Tr.t("Add")
                kind: "primary"
                enabled: sched.text.trim() !== "" && cmd.text.trim() !== "" && !SysServices.busy
                onClicked: {
                    SysServices.cronAdd(sched.text.trim(), cmd.text.trim());
                    sched.text = ""; cmd.text = "";
                }
            }
        }
    }
}
