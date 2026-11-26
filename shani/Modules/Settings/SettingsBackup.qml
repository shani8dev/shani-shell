// Settings > Backup: what the backup tool says through the shell's service, and
// the daily switch and time. The work is done by the same bridge the Backup
// window uses; no other app is started.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    readonly property bool installed: Backup.available
    onActiveChanged: if (active) Backup.refresh()
    Component.onCompleted: if (active) Backup.refresh()
    readonly property string summary: Backup.versions + " | " + Backup.drive
    onSummaryChanged: Ui.backupSummary = summary
    property string customTime: ""

    InfoBanner {
        visible: Backup.error !== ""
        Layout.fillWidth: true
        tone: "error"
        title: Tr.t("Backup did not finish")
        text: Backup.error
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Your files")
        Text {
            visible: !page.installed
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Tr.t("The backup tool is not installed.")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        Repeater {
            model: page.installed ? [
                { title: Tr.t("Earlier versions"), sub: Backup.versions, icon: "document-open-recent", tab: "home" },
                { title: Tr.t("Backups to another drive"), sub: Backup.drive, icon: "drive-harddisk", tab: "backups" }] : []
            SettingRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: modelData.icon
                title: modelData.title
                subtitle: modelData.sub
                control: Button {
                    text: Tr.t("Open")
                    enabled: Backup.available
                    onClicked: { Backup.open(modelData.tab); Ui.closeAll(); }
                    Accessible.name: Tr.t("Open Backup at %1", modelData.title)
                }
            }
        }
    }

    SettingsSection {
        visible: page.installed
        Layout.fillWidth: true
        title: Tr.t("Daily backup")
        hint: Tr.t("A copy of your home folder is made on the backup drive every day while you are signed in.")
        SwitchRow {
            Layout.fillWidth: true
            text: Tr.t("Back up every day")
            hint: Tr.t("A copy each day; older ones are thinned out automatically")
            checked: Backup.scheduleOn
            enabled: Backup.busyOp === ""
            onToggled: on => Backup.setSchedule(on)
        }
        SwitchRow {
            Layout.fillWidth: true
            text: Tr.t("Keep a daily copy")
            hint: Backup.timerHint()
            checked: Backup.timerEnabled
            enabled: Backup.timerKnown && Backup.busyOp === ""
            onToggled: on => Backup.setHomeTimer(on)
        }
        Picks {
            label: Tr.t("At")
            options: [{ label: Tr.t("Morning · 06:00"), value: "06:00" },
                      { label: Tr.t("Noon · 12:30"), value: "12:30" },
                      { label: Tr.t("Evening · 18:00"), value: "18:00" },
                      { label: Tr.t("Night · 21:15"), value: "21:15" }]
            current: Backup.scheduleTime
            enabled: Backup.busyOp === ""
            onPicked: t => Backup.setScheduleTime(t)
        }
        RowLayout {
            Layout.fillWidth: true
            TextField {
                Layout.fillWidth: true
                label: Tr.t("Another time (optional)")
                placeholder: "07:45"
                text: page.customTime
                onTextChanged: page.customTime = text
                onAccepted: { if (page.customTime) Backup.setScheduleTime(page.customTime); }
            }
            Button {
                text: Tr.t("Set time")
                enabled: page.customTime !== "" && Backup.busyOp === ""
                onClicked: Backup.setScheduleTime(page.customTime)
                Accessible.name: Tr.t("Set the daily backup time to the time typed")
            }
        }
        InfoBanner {
            Layout.fillWidth: true
            tone: "info"
            text: Tr.t("Before each update, an earlier copy of your home is made automatically. The updater's settings control this; there is no switch here.")
        }
    }

    SettingsSection {
        visible: page.installed
        Layout.fillWidth: true
        title: Tr.t("Snapshots on this disk")
        hint: Tr.t("Snapshots keep earlier versions of your files without overwriting anything.")
        RowLayout {
            Layout.fillWidth: true
            Button {
                text: Tr.t("Take a snapshot now")
                enabled: Backup.busyOp === ""
                busy: Backup.busyOp === "home-snapshot"
                onClicked: Backup.homeSnapshotNow()
                Accessible.name: Tr.t("Take a snapshot of your home now")
            }
            Button {
                text: Tr.t("Open Backup")
                onClicked: { Backup.open("home"); Ui.closeAll(); }
                Accessible.name: Tr.t("Open the Backup window")
            }
            Item { Layout.fillWidth: true }
            Text {
                text: Backup.snapshots.length ? Tr.t("%1 earlier versions", Backup.snapshots.length) : Tr.t("None yet")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
        }
    }
}
