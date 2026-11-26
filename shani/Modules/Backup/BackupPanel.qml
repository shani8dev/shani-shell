// Backup: everything Shani Backup can do, in the shell. The service (Backup.qml)
// runs shani-backup's own commands through bridge/backup.py; this panel only
// shows what came back and asks for a choice before anything changes.
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
    implicitWidth: Theme.px(780)
    implicitHeight: Theme.px(620)

    property int tabIndex: 0
    Component.onCompleted: {
        const i = ["home", "backups", "snapshots"].indexOf(Backup.tab);
        if (i >= 0) tabIndex = i;
    }
    Connections {
        target: Backup
        function onTabChanged() {
            const i = ["home", "backups", "snapshots"].indexOf(Backup.tab);
            if (i >= 0 && win.tabIndex !== i) win.tabIndex = i;
        }
    }
    property string customTime: ""
    property string snapshotName: ""
    property string snapshotSource: "/"
    property string restoreTarget: ""

    onVisibleChanged: if (visible) Backup.refresh()
    onTabIndexChanged: {
        Backup.tab = ["home", "backups", "snapshots"][tabIndex];
        Backup.error = "";
        Backup.note = "";
    }

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

            // ---- header ---------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Tr.t("Backup")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(17) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Button {
                    text: Tr.t("Back up now")
                    kind: "outline"
                    busy: Backup.running
                    enabled: Backup.available && Backup.driveSetUp && !Backup.running
                    onClicked: Backup.backupNow()
                    Accessible.name: Tr.t("Back up now to the backup drive")
                }
                IconButton { icon: "window-close"; tip: Tr.t("Close"); onClicked: win.visible = false }
            }

            SegmentedTabs {
                Layout.fillWidth: true
                options: [Tr.t("Your files"), Tr.t("Other drive"), Tr.t("Snapshots & schedule")]
                segmentWidth: Math.max(Theme.px(150), width / 3 - Theme.px(3))
                currentIndex: win.tabIndex
                onActivated: idx => win.tabIndex = idx
            }

            // ---- shared feedback -------------------------------------------------
            BusyNote {
                visible: Backup.busyOp !== "" || Backup.copyBusy
                Layout.fillWidth: true
                align: Text.AlignHCenter
                note: Backup.running ? Tr.t("Backing up your home…")
                    : Backup.busyOp === "restore" ? Tr.t("Restoring your backup…")
                    : Backup.copyBusy ? Tr.t("Restoring the file…")
                    : Backup.busyOp === "home-snapshot" || Backup.busyOp === "snapshot-create" ? Tr.t("Taking a snapshot…")
                    : Backup.busyOp === "snapshot-delete" || Backup.busyOp === "home-remove" ? Tr.t("Removing the snapshot…")
                    : Tr.t("Working…")
            }
            InfoBanner {
                visible: Backup.error !== ""
                Layout.fillWidth: true
                tone: "error"
                title: Tr.t("That did not work")
                text: Backup.error
            }
            InfoBanner {
                visible: Backup.error === "" && Backup.note !== "" && Backup.busyOp === "" && !Backup.copyBusy
                Layout.fillWidth: true
                tone: "ok"
                text: Backup.note
            }
            Text {
                visible: !Backup.available
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Tr.t("Shani Backup is not installed here. Snapshots and backups cannot be made or restored.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.tabIndex

                // ---- tab 1: snapshots of this home -----------------------------
                Item {
                    ColumnLayout {
                        anchors { fill: parent; topMargin: Theme.px(4) }
                        spacing: Theme.px(8)

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: Backup.versions
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                            Button {
                                text: Tr.t("Take a snapshot now")
                                enabled: Backup.available && Backup.busyOp === ""
                                busy: Backup.busyOp === "home-snapshot"
                                onClicked: Backup.homeSnapshotNow()
                                Accessible.name: Tr.t("Take a snapshot of your home now")
                            }
                            Button {
                                text: Tr.t("Open folder")
                                enabled: Backup.snapshots.length > 0
                                onClicked: Backup.openPath(Backup.snapshots[0].path)
                                Accessible.name: Tr.t("Open the newest snapshot in Files")
                            }
                        }

                        EmptyState {
                            visible: !Backup.loading && Backup.snapshots.length === 0 && Backup.available
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            icon: "document-open-recent"
                            title: Tr.t("No earlier versions yet")
                            subtitle: Tr.t("Once a day a copy of your home is made on this disk. Take one now to start.")
                            actionText: Tr.t("Take a snapshot now")
                            onAction: Backup.homeSnapshotNow()
                        }

                        ListView {
                            visible: Backup.snapshots.length > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            reuseItems: true
                            model: Backup.snapshots
                            delegate: ListRow {
                                required property var modelData
                                width: ListView.view.width
                                icon: "document-open-recent"
                                title: modelData.displayDate
                                subtitle: modelData.subtitle + " · " + modelData.name
                                interactive: false
                                Button {
                                    text: Tr.t("Browse")
                                    kind: "outline"
                                    flat: true
                                    onClicked: Backup.openPath(modelData.path)
                                    Accessible.name: Tr.t("Browse the snapshot from %1", modelData.displayDate)
                                }
                                Button {
                                    text: Tr.t("Restore a file")
                                    kind: "outline"
                                    flat: true
                                    enabled: Backup.busyOp === "" && !Backup.copyBusy
                                    onClicked: {
                                        const snap = modelData.path;
                                        FilePicker.open({ mode: "open", title: Tr.t("Pick a file from this snapshot"),
                                            startPath: snap,
                                            onPicked: picks => {
                                                if (!picks.length) return;
                                                const src = picks[0];
                                                FilePicker.open({ mode: "folder", title: Tr.t("Where should the restored file go?"),
                                                    onPicked: dests => {
                                                        if (dests.length) Backup.restoreFromHome(src, dests[0]);
                                                    }});
                                            }});
                                    }
                                    Accessible.name: Tr.t("Restore a file from the snapshot from %1", modelData.displayDate)
                                }
                                Button {
                                    text: Tr.t("Restore a folder")
                                    kind: "outline"
                                    flat: true
                                    enabled: Backup.busyOp === "" && !Backup.copyBusy
                                    onClicked: {
                                        const snap = modelData.path;
                                        FilePicker.open({ mode: "folder", title: Tr.t("Pick a folder from this snapshot"),
                                            startPath: snap,
                                            onPicked: picks => {
                                                if (!picks.length) return;
                                                const src = picks[0];
                                                FilePicker.open({ mode: "folder", title: Tr.t("Where should the restored folder go?"),
                                                    onPicked: dests => {
                                                        if (dests.length) Backup.restoreFromHome(src, dests[0]);
                                                    }});
                                            }});
                                    }
                                    Accessible.name: Tr.t("Restore a folder from the snapshot from %1", modelData.displayDate)
                                }
                                ConfirmButton {
                                    implicitWidth: Math.max(Theme.touchTarget, armedText.length * 8 + 28)
                                    implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                                    text: Tr.t("Remove")
                                    armedText: Tr.t("Remove this version?")
                                    kind: "danger"
                                    value: modelData.name
                                    visible: String(modelData.name).startsWith("manual-") && !modelData.whole
                                    enabled: Backup.busyOp === ""
                                    onConfirmed: name => Backup.homeRemove(name)
                                    Accessible.name: Tr.t("Remove the snapshot %1", modelData.name)
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Tr.t("Taking a snapshot needs administrator rights. Restoring a file puts a copy beside the current one; nothing in your home is overwritten.")
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                    }
                }

                // ---- tab 2: the copy on another drive --------------------------
                Item {
                    ColumnLayout {
                        anchors { fill: parent; topMargin: Theme.px(4) }
                        spacing: Theme.px(8)

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: Backup.drive
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                            Button {
                                text: Tr.t("Open backup drive")
                                enabled: Backup.repository !== ""
                                onClicked: Backup.openPath(Backup.repository)
                                Accessible.name: Tr.t("Open the backup drive in Files")
                            }
                        }

                        // progress comes from the command's own status lines
                        RowLayout {
                            visible: Backup.running
                            Layout.fillWidth: true
                            Rectangle {
                                Layout.fillWidth: true
                                height: Theme.px(8)
                                radius: Theme.px(4)
                                color: Theme.surface2
                                Rectangle {
                                    width: parent.width * Backup.progress / 100
                                    height: parent.height
                                    radius: parent.radius
                                    color: Theme.accent
                                }
                            }
                            Text {
                                text: Backup.progress + "%"
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                        }

                        EmptyState {
                            visible: !Backup.loading && !Backup.driveSetUp && Backup.available
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            icon: "drive-harddisk"
                            title: Tr.t("No backup drive set up")
                            subtitle: Tr.t("Choose another drive or a folder outside your home to keep a copy of your files. A password protects the backups.")
                        }

                        ListView {
                            visible: Backup.driveSetUp && Backup.backups.length > 0
                            Layout.fillWidth: true
                            // in a layout `height` is ignored: size to the rows, scroll past a few
                            Layout.preferredHeight: Math.min(contentHeight, Theme.px(260))
                            clip: true
                            reuseItems: true
                            model: Backup.backups
                            delegate: ListRow {
                                required property var modelData
                                width: ListView.view.width
                                icon: "drive-harddisk"
                                title: Backup.day(modelData.time) + " " + String(modelData.time || "").slice(11, 16)
                                subtitle: modelData.id + (modelData.size ? " · " + Backup.formatBytes(modelData.size) : "")
                                interactive: false
                                Button {
                                    text: Tr.t("Pick to restore")
                                    kind: "outline"
                                    flat: true
                                    onClicked: { win.restoreTarget = ""; Backup.restorePick = modelData.id; win.tabIndex = 1; }
                                    Accessible.name: Tr.t("Pick the backup %1 to restore", modelData.id)
                                }
                            }
                        }

                        EmptyState {
                            visible: Backup.driveSetUp && Backup.backups.length === 0 && !Backup.loading
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            icon: "drive-harddisk"
                            title: Tr.t("No backups yet")
                            subtitle: Tr.t("Press Back up now to make the first copy of your home folder.")
                        }

                        // restore: pick a backup, then a folder, then confirm
                        SettingsSection {
                            Layout.fillWidth: true
                            title: Tr.t("Restore a backup")
                            hint: Tr.t("Everything in the chosen backup is copied into a new folder. Nothing in your home is replaced.")
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(8)
                                Picks {
                                    label: Tr.t("Backup")
                                    options: Backup.backups.map(b => ({ label: Backup.day(b.time) + " " + String(b.time || "").slice(11, 16), value: b.id }))
                                    current: Backup.restorePick
                                    onPicked: v => Backup.restorePick = v
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideMiddle
                                        text: win.restoreTarget || Tr.t("No folder chosen yet")
                                        color: Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                    Button {
                                        text: Tr.t("Choose folder")
                                        onClicked: FilePicker.open({ mode: "folder", title: Tr.t("Where should the backup be restored?"),
                                            onPicked: paths => { if (paths.length) win.restoreTarget = paths[0]; }});
                                        Accessible.name: Tr.t("Choose where to restore the backup")
                                    }
                                }
                                ConfirmButton {
                                    implicitWidth: Math.max(Theme.touchTarget, armedText.length * 8 + 28)
                                    implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                                    text: Tr.t("Restore here")
                                    armedText: Tr.t("Copy the backup here?")
                                    kind: "primary"
                                    enabled: Backup.restorePick !== "" && win.restoreTarget !== "" && Backup.busyOp === ""
                                    onConfirmed: { Backup.restoreTo(Backup.restorePick, win.restoreTarget); win.restoreTarget = ""; }
                                    Accessible.name: Tr.t("Restore the chosen backup into the chosen folder")
                                }
                                Button {
                                    visible: Backup.lastAction === "restore" && Backup.lastTarget !== "" && Backup.error === ""
                                    text: Tr.t("Open restored folder")
                                    onClicked: Backup.openPath(Backup.lastTarget)
                                    Accessible.name: Tr.t("Open the folder the backup was restored into")
                                }
                            }
                        }
                    }
                }

                // ---- tab 3: btrfs snapshots and the daily schedule ------------
                Item {
                    ColumnLayout {
                        anchors { fill: parent; topMargin: Theme.px(4) }
                        spacing: Theme.px(8)

                        SettingsSection {
                            Layout.fillWidth: true
                            title: Tr.t("Daily backup")
                            hint: Tr.t("A copy of your home folder is made every day while you are signed in.")
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(8)
                                SwitchRow {
                                    Layout.fillWidth: true
                                    text: Tr.t("Back up every day")
                                    hint: Tr.t("A copy each day; older ones are thinned out automatically")
                                    checked: Backup.scheduleOn
                                    enabled: Backup.busyOp === ""
                                    onToggled: on => Backup.setSchedule(on)
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
                                        placeholder: Tr.t("Another time, as 07:45")
                                        text: win.customTime
                                        onTextChanged: win.customTime = text
                                        onAccepted: { if (win.customTime) Backup.setScheduleTime(win.customTime); }
                                    }
                                    Button {
                                        text: Tr.t("Set time")
                                        enabled: win.customTime !== "" && Backup.busyOp === ""
                                        onClicked: Backup.setScheduleTime(win.customTime)
                                        Accessible.name: Tr.t("Set the daily backup time to the time typed")
                                    }
                                }
                                InfoBanner {
                                    Layout.fillWidth: true
                                    tone: "info"
                                    text: Tr.t("Before each update, a snapshot of your home is taken automatically.")
                                }
                            }
                        }

                        SettingsSection {
                            Layout.fillWidth: true
                            title: Tr.t("Snapshots on this disk")
                            hint: Tr.t("A snapshot is a point-in-time copy of a folder, kept beside the original. Creating or deleting one asks for administrator rights.")
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(8)
                                RowLayout {
                                    Layout.fillWidth: true
                                    Picks {
                                        Layout.fillWidth: true
                                        label: Tr.t("Folder to snapshot")
                                        options: [{ label: Tr.t("Your home"), value: "/home" },
                                                  { label: Tr.t("The whole system"), value: "/" }]
                                        current: win.snapshotSource
                                        onPicked: v => win.snapshotSource = v
                                    }
                                    TextField {
                                        Layout.fillWidth: true
                                        label: Tr.t("Name (optional)")
                                        placeholder: Tr.t("Before the move")
                                        text: win.snapshotName
                                        onTextChanged: win.snapshotName = text
                                    }
                                    Button {
                                        text: Tr.t("Create snapshot")
                                        enabled: Backup.available && Backup.busyOp === ""
                                        onClicked: {
                                            const label = win.snapshotName.trim();
                                            const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
                                            const dest = Backup.homeTool + "/" + (label ? "manual-" + label.replace(/[^A-Za-z0-9_-]/g, "-") : "manual-" + stamp);
                                            Backup.snapshotCreate(win.snapshotSource, dest, true);
                                            win.snapshotName = "";
                                        }
                                        Accessible.name: Tr.t("Create a snapshot of the chosen folder")
                                    }
                                }
                                EmptyState {
                                    visible: Backup.btrfsSnapshots.length === 0
                                    Layout.fillWidth: true
                                    icon: "document-open-recent"
                                    title: Tr.t("No snapshots here yet")
                                    subtitle: Tr.t("Create one above, or take a snapshot of your home.")
                                }
                                ListView {
                                    visible: Backup.btrfsSnapshots.length > 0
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: Backup.btrfsSnapshots
                                    delegate: ListRow {
                                        required property var modelData
                                        width: ListView.view.width
                                        icon: "document-open-recent"
                                        title: modelData.name
                                        subtitle: modelData.path
                                        interactive: false
                                        Button {
                                            text: Tr.t("Open")
                                            kind: "outline"
                                            flat: true
                                            onClicked: Backup.openPath(modelData.path)
                                            Accessible.name: Tr.t("Open the snapshot %1 in Files", modelData.name)
                                        }
                                        ConfirmButton {
                                            implicitWidth: Math.max(Theme.touchTarget, armedText.length * 8 + 28)
                                            implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                                            text: Tr.t("Delete")
                                            armedText: Tr.t("Delete this snapshot?")
                                            kind: "danger"
                                            value: modelData.path
                                            enabled: Backup.busyOp === ""
                                            onConfirmed: path => Backup.snapshotDelete(path)
                                            Accessible.name: Tr.t("Delete the snapshot %1", modelData.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
