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

    property int confirmCron: -1
    Timer { id: cronConfirmTimer; interval: 4000; onTriggered: win.confirmCron = -1 }

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
            color: SysServices.note === Tr.t("Saved") || SysServices.note === Tr.t("Job removed") ? Theme.dim : Theme.danger
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }

        // ---- services -------------------------------------------------------
        ListView {
            id: serviceList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: SysServices.tab === "services"
            clip: true
            spacing: Theme.px(2)
            model: SysServices.services
            delegate: ListRow {
                required property var modelData
                width: ListView.view.width
                interactive: false
                icon: modelData.active === "active" ? "dialog-ok" : "dialog-information"
                title: modelData.unit
                subtitle: [modelData.active, modelData.enabled, modelData.description].filter(x => x).join("  ·  ")
                extra: RowLayout {
                    spacing: Theme.px(4)
                    Button {
                        text: modelData.active === "active" ? Tr.t("Stop") : Tr.t("Start")
                        flat: true
                        enabled: !SysServices.busy
                        Accessible.name: (modelData.active === "active" ? Tr.t("Stop") : Tr.t("Start")) + " " + modelData.unit
                        onClicked: SysServices.unit(modelData.unit, modelData.active === "active" ? "stop" : "start")
                    }
                    Button {
                        text: modelData.enabled === "enabled" ? Tr.t("Disable") : Tr.t("Enable")
                        flat: true
                        enabled: !SysServices.busy
                        Accessible.name: (modelData.enabled === "enabled" ? Tr.t("Disable") : Tr.t("Enable")) + " " + modelData.unit
                        onClicked: SysServices.unit(modelData.unit, modelData.enabled === "enabled" ? "disable" : "enable")
                    }
                }
            }
            EmptyState {
                anchors.centerIn: parent
                visible: serviceList.count === 0 && !SysServices.busy
                icon: "dialog-information"
                title: Tr.t("No services")
                subtitle: Tr.t("No user services were found on this system")
            }
        }

        // ---- timers ---------------------------------------------------------
        ListView {
            id: timerList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: SysServices.tab === "timers"
            clip: true
            spacing: Theme.px(2)
            model: SysServices.timers
            delegate: ListRow {
                required property var modelData
                width: ListView.view.width
                interactive: false
                icon: "preferences-system-time"
                title: modelData.unit
                subtitle: [modelData.next, modelData.left, modelData.description].filter(x => x).join("  ·  ")
                extra: RowLayout {
                    spacing: Theme.px(4)
                    Button {
                        text: Tr.t("Stop")
                        flat: true
                        enabled: !SysServices.busy
                        Accessible.name: Tr.t("Stop") + " " + modelData.unit
                        onClicked: SysServices.unit(modelData.unit, "stop")
                    }
                    Button {
                        text: Tr.t("Disable")
                        flat: true
                        enabled: !SysServices.busy
                        Accessible.name: Tr.t("Disable") + " " + modelData.unit
                        onClicked: SysServices.unit(modelData.unit, "disable")
                    }
                }
            }
            EmptyState {
                anchors.centerIn: parent
                visible: timerList.count === 0 && !SysServices.busy
                icon: "preferences-system-time"
                title: Tr.t("No timers")
                subtitle: Tr.t("No user timers are scheduled")
            }
        }

        // ---- cron: the C and D of CRUD -------------------------------------
        ListView {
            id: cronList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: SysServices.tab === "cron"
            clip: true
            spacing: Theme.px(2)
            model: SysServices.cron
            delegate: ListRow {
                required property var modelData
                width: ListView.view.width
                interactive: false
                icon: "preferences-system-time"
                title: modelData.line
                subtitle: Tr.t("Entry %1", modelData.index + 1)
                extra: Button {
                    text: win.confirmCron === modelData.index ? Tr.t("Tap again to remove") : Tr.t("Remove")
                    flat: true
                    kind: "danger"
                    enabled: !SysServices.busy
                    Accessible.name: (win.confirmCron === modelData.index ? Tr.t("Tap again to remove") : Tr.t("Remove")) + " " + modelData.line
                    onClicked: {
                        if (win.confirmCron === modelData.index) {
                            SysServices.cronRemove(modelData.index);
                            win.confirmCron = -1;
                        } else {
                            win.confirmCron = modelData.index;
                            cronConfirmTimer.restart();
                        }
                    }
                }
            }
            EmptyState {
                anchors.centerIn: parent
                visible: cronList.count === 0 && !SysServices.busy
                icon: "preferences-system-time"
                title: Tr.t("No scheduled jobs")
                subtitle: Tr.t("Add a cron job below to run a command on a schedule")
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
