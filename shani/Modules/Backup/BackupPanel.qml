// Backup: everything the backup tool (shani-backup) can do, in the shell. The service (Backup.qml)
// runs shani-backup's own commands through bridge/backup.py; this panel only
// shows what came back and asks for a choice before anything changes.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Backup"
    visible: Ui.backup
    onGone: Ui.backup = false
    implicitWidth: Theme.px(780)
    implicitHeight: Theme.px(620)
    tools: [
        Button {
            text: Tr.t("Back up now")
            kind: "outline"
            busy: Backup.running
            enabled: Backup.available && Backup.driveSetUp && !Backup.running
            onClicked: Backup.backupNow()
            Accessible.name: Tr.t("Back up now to the backup drive")
        }
    ]

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
    property string findQuery: ""
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

            ActionStrip {
                Layout.fillWidth: true
                Repeater {
                    model: [Tr.t("Your files"), Tr.t("Other drive"), Tr.t("Snapshots & schedule")]
                    Choice {
                        required property string modelData
                        required property int index
                        text: modelData
                        selected: win.tabIndex === index
                        onClicked: win.tabIndex = index
                    }
                }
            }

            // ---- shared feedback -------------------------------------------------
            BusyNote {
                visible: Backup.busyOp !== "" || Backup.copyBusy
                Layout.fillWidth: true
                align: Text.AlignHCenter
                note: Backup.running ? Tr.t("Backing up your home…")
                    : Backup.busyOp === "restore" ? Tr.t("Restoring your backup…")
                    : Backup.copyBusy ? Tr.t("Restoring the file…")
                    : Backup.busyOp === "find-file" ? Tr.t("Searching earlier copies…")
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
                text: Tr.t("The backup tool is not installed here. Snapshots and backups cannot be made or restored.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("small")
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

                        ColumnLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: Backup.versions
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.type("small")
                            }
                            ActionStrip {
                                Layout.fillWidth: true
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
                        }

                        RowLayout {
                            visible: Backup.diskKnown
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: Tr.t("Space on this disk: %1 free of %2",
                                           Backup.formatBytes(Backup.diskFree), Backup.formatBytes(Backup.diskTotal))
                                Accessible.name: text
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.type("small")
                            }
                            Rectangle {
                                Layout.preferredWidth: Theme.px(120)
                                implicitHeight: Theme.px(8)
                                radius: Theme.px(4)
                                color: Theme.surface2
                                Rectangle {
                                    width: parent.width * Backup.diskPercent() / 100
                                    height: parent.height
                                    radius: parent.radius
                                    color: Backup.diskLow ? Theme.amber : Theme.accent
                                }
                            }
                        }
                        InfoBanner {
                            visible: Backup.diskKnown && Backup.diskLow
                            Layout.fillWidth: true
                            tone: "warn"
                            text: Tr.t("This disk is nearly full. Remove an earlier copy you no longer need.")
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
                            delegate: GridLayout {
                                id: snapshotRow
                                required property var modelData
                                width: ListView.view.width
                                columns: win.compact ? 1 : 2
                                columnSpacing: Theme.space(2)
                                rowSpacing: 0
                                ListRow {
                                    Layout.fillWidth: true
                                    icon: "document-open-recent"
                                    title: snapshotRow.modelData.displayDate
                                    subtitle: snapshotRow.modelData.subtitle + " · " + snapshotRow.modelData.name
                                    interactive: false
                                }
                                ActionStrip {
                                    Layout.fillWidth: win.compact
                                    Layout.maximumWidth: win.compact ? Number.POSITIVE_INFINITY : snapshotRow.width * 0.66
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
                        }
                        SettingsSection {
                            Layout.fillWidth: true
                            title: Tr.t("Find a file")
                            hint: Tr.t("Search your earlier copies by part of a name. Pick a result, then choose where a copy should go.")
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(8)
                                RowLayout {
                                    Layout.fillWidth: true
                                    TextField {
                                        Layout.fillWidth: true
                                        label: Tr.t("Part of the file name")
                                        placeholder: Tr.t("For example, notes.txt")
                                        text: win.findQuery
                                        onTextChanged: win.findQuery = text
                                        onAccepted: { if (win.findQuery.trim().length >= 2) Backup.findFile(win.findQuery.trim()); }
                                    }
                                    Button {
                                        text: Tr.t("Find it")
                                        enabled: win.findQuery.trim().length >= 2 && Backup.busyOp === ""
                                        busy: Backup.busyOp === "find-file"
                                        onClicked: Backup.findFile(win.findQuery.trim())
                                        Accessible.name: Tr.t("Find it")
                                    }
                                }
                                Text {
                                    visible: Backup.findSearched && Backup.findResults.length === 0 && Backup.error === "" && !Backup.busyOp
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: Tr.t("Nothing by that name in any earlier copy. Try a shorter name.")
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.type("small")
                                }
                                Text {
                                    visible: Backup.findTruncated
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: Tr.t("Showing the first 60 matches. Type more of the name to narrow it down.")
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: Theme.type("caption")
                                }
                                ListView {
                                    visible: Backup.findResults.length > 0
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.min(contentHeight, Theme.px(180))
                                    clip: true
                                    reuseItems: true
                                    model: Backup.findResults
                                    delegate: ListRow {
                                        required property var modelData
                                        width: ListView.view.width
                                        icon: "edit-find"
                                        title: modelData.name
                                        subtitle: modelData.path + (modelData.size ? " · " + Backup.formatBytes(modelData.size) : "")
                                        interactive: false
                                        Button {
                                            text: Tr.t("Restore this file")
                                            kind: "outline"
                                            flat: true
                                            enabled: Backup.busyOp === "" && !Backup.copyBusy
                                            onClicked: {
                                                Backup.findPick = modelData.path;
                                                FilePicker.open({ mode: "folder", title: Tr.t("Where should this file go?"),
                                                    startPath: Backup.snapshots.length ? Backup.snapshots[0].path : "",
                                                    onPicked: dests => {
                                                        if (dests.length) Backup.restoreFromHome(Backup.findPick, dests[0]);
                                                    }});
                                            }
                                            Accessible.name: Tr.t("Restore the file %1 from an earlier copy", modelData.name)
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Tr.t("Taking a snapshot needs administrator rights. Restoring a file puts a copy beside the current one; nothing in your home is overwritten.")
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.type("caption")
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
                                font.pixelSize: Theme.type("small")
                            }
                            Button {
                                text: Tr.t("Open backup drive")
                                enabled: Backup.repository !== ""
                                onClicked: Backup.openPath(Backup.repository)
                                Accessible.name: Tr.t("Open the backup drive in Files")
                            }
                        }

                        InfoBanner {
                            visible: Backup.driveSetUp && Backup.restoreTest !== null && Backup.restoreTest.ok === true
                            Layout.fillWidth: true
                            tone: "ok"
                            title: Tr.t("A test restore worked")
                            text: Backup.restoreTest && Backup.restoreTest.file
                                ? Tr.t("A file was read back from the backup: %1", Backup.restoreTest.file)
                                : Tr.t("A file was read back from the backup.")
                        }
                        InfoBanner {
                            visible: Backup.driveSetUp && Backup.restoreTest !== null && Backup.restoreTest.ok !== true
                            Layout.fillWidth: true
                            tone: "warn"
                            title: Tr.t("The test restore did not work")
                            text: Tr.t("A recent check could not read a file back from the backup. Try backing up again.")
                        }
                        InfoBanner {
                            visible: Backup.stale && Backup.backups.length > 0
                            Layout.fillWidth: true
                            tone: "warn"
                            text: Tr.t("The newest backup is from %1. Nothing recent has been saved.", Backup.day(Backup.newest))
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
                                font.pixelSize: Theme.type("small")
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
                                        font.pixelSize: Theme.type("small")
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
                            title: Tr.t("Daily copy on this disk")
                            hint: Tr.t("An earlier version of your home is kept on this disk each day. This is separate from the copy on another drive.")
                            SwitchRow {
                                Layout.fillWidth: true
                                text: Tr.t("Keep a daily copy")
                                hint: Backup.timerHint()
                                checked: Backup.timerEnabled
                                enabled: Backup.timerKnown && Backup.busyOp === ""
                                onToggled: on => Backup.setHomeTimer(on)
                            }
                        }

                        SettingsSection {
                            Layout.fillWidth: true
                            title: Tr.t("Daily backup")
                            hint: Tr.t("A copy of your home folder is made on the backup drive every day while you are signed in.")
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
                                    text: Tr.t("Before each update, an earlier copy of your home is made automatically. The updater's settings control this; there is no switch here.")
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
