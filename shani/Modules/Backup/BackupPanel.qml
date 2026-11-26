// Backup: restore your home from a snapshot. Shows a timeline of past
// snapshots (from shani-backup home list --json) with sizes and dates.
// You can restore the whole home or specific paths.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Shani Backup"
    visible: Ui.backup
    onGone: Ui.backup = false
    implicitWidth: Theme.px(700)
    implicitHeight: Theme.px(500)

    onVisibleChanged: if (visible) Backup.refresh()

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: win.visible = false
    }

    Glass {
        id: card
        anchors.fill: parent
        radius: Theme.radiusLarge
        strong: true

        ColumnLayout {
            anchors { fill: parent; margins: Theme.px(16) }
            spacing: Theme.px(10)

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Tr.t("Restore from snapshot")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(16) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                // back up now: the same single-flight action the other surfaces use
                Button {
                    text: Tr.t("Back up now")
                    kind: "outline"
                    busy: Backup.running
                    enabled: Backup.available && !Backup.running
                    onClicked: Backup.backupNow()
                }
                Item { Layout.fillWidth: true }
                IconButton { icon: "window-close"; tip: Tr.t("Close"); onClicked: win.visible = false }
            }

            // in-flight feedback: a backup or a shell-driven restore is running
            BusyNote {
                visible: Backup.running || Backup.restoring !== ""
                Layout.fillWidth: true
                align: Text.AlignHCenter
                note: Backup.restoring !== "" ? Tr.t("Restoring %1…", Backup.restoring) : Tr.t("Backing up your home…")
            }

            // backup unavailable: say so instead of offering a setup that will fail
            Text {
                visible: !Backup.available
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Tr.t("Shani Backup is not installed — snapshots cannot be made or restored here")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }

            // timeline empty state: offer a next step when no drive is set up
            EmptyState {
                visible: !Backup.loading && Backup.snapshots.length === 0 && Backup.available
                icon: "document-open-recent"
                title: Backup.driveSetUp ? Tr.t("No snapshots yet") : Tr.t("No backup drive set up")
                actionText: Backup.driveSetUp ? "" : Tr.t("Set up backup drive…")
                onAction: Backup.open("backups")
            }

            ListView {
                id: timeline
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                reuseItems: true
                cacheBuffer: 400
                model: Backup.snapshots
                delegate: ColumnLayout {
                    required property var modelData
                    width: timeline.width
                    spacing: Theme.px(2)
                    ListRow {
                        Layout.fillWidth: true
                        icon: "document-open-recent"
                        title: modelData.displayDate
                        subtitle: modelData.size > 0 ? Backup.formatBytes(modelData.size) + " · " + modelData.name : modelData.name
                        // restore is an explicit button, never a stray row tap
                        interactive: false
                        Button {
                            visible: !win.compact
                            text: Tr.t("Restore")
                            kind: "primary"
                            enabled: Backup.driveSetUp
                            onClicked: {
                                Backup.restoreFromSnapshot(modelData.name, "all");
                                win.visible = false;
                            }
                        }
                        Button {
                            visible: !win.compact
                            text: Tr.t("Files only")
                            kind: "outline"
                            flat: true
                            enabled: Backup.driveSetUp
                            onClicked: {
                                Backup.restoreFromSnapshot(modelData.name, "files");
                                win.visible = false;
                            }
                        }
                    }
                    Flow {
                        visible: win.compact
                        Layout.fillWidth: true
                        spacing: Theme.px(6)
                        Button {
                            text: Tr.t("Restore")
                            kind: "primary"
                            enabled: Backup.driveSetUp
                            onClicked: {
                                Backup.restoreFromSnapshot(modelData.name, "all");
                                win.visible = false;
                            }
                        }
                        Button {
                            text: Tr.t("Files only")
                            kind: "outline"
                            flat: true
                            enabled: Backup.driveSetUp
                            onClicked: {
                                Backup.restoreFromSnapshot(modelData.name, "files");
                                win.visible = false;
                            }
                        }
                    }
                }
            }

            // footer
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Restore returns your home to the state it was in on the snapshot date. Changed files are overwritten.")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
                wrapMode: Text.Wrap
            }
        }
    }
}
