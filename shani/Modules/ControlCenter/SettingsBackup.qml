// Settings > Backup: the two questions, answered by Shani Backup itself
// (Services/Backup reads `home list --json` and `backups --json`):
// are there earlier versions of my files, and is my home copied to another
// drive. Each row opens Shani Backup on its page; the work is done there.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    readonly property bool installed: Backup.available
    onActiveChanged: if (active) Backup.refresh()
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) Backup.refresh()
    readonly property string summary: Backup.versions + " | " + Backup.drive
    onSummaryChanged: Ui.backupSummary = summary

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Your files") }
    Text {
        visible: !page.installed
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: Tr.t("Shani Backup is not installed.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Repeater {
        model: page.installed ? [
            { title: Tr.t("Earlier versions"), sub: Backup.versions, icon: "document-open-recent", open: "home" },
            { title: Tr.t("Backups to another drive"), sub: Backup.drive, icon: "drive-harddisk", open: "backups" }] : []
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 10
            Icon { name: modelData.icon; size: 20; color: Theme.accent }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { text: modelData.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale }
                Text { Layout.fillWidth: true; text: modelData.sub; elide: Text.ElideRight; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
            }
            Button { text: Tr.t("Open"); onClicked: { Backup.open(modelData.open); Ui.closeAll(); } }
        }
    }
}
