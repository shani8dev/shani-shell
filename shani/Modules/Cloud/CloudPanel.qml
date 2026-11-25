// Cloud sync: the jobs the session daemon is running with rclone. A job is a
// remote:path folder and a local folder, a direction, what to do on a clash, a
// bandwidth cap and a repeat interval. The work happens in the daemon; this
// only sends commands and shows its state, including the current file and the
// last runs. This window has no `appName`: the shell's app table names apps a
// dock/switcher can launch (tests/test_apps.py checks every appName against
// it), and adding an entry means editing bin/shani + ShellApps.js — outside
// this feature. AppWindow's appName is optional, so a self-registering window
// without one keeps that table and its test intact; whoever wires this panel
// into shell.qml can give it a flag there.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Cloud sync"
    visible: Ui.cloudSync
    onGone: win.visible = false
    implicitWidth: Theme.px(860)
    implicitHeight: Theme.px(660)

    property string selected: ""
    property string notice: ""
    property string directionChoice: "download"
    property string conflictChoice: "rename"

    function percent(j) { return Math.max(0, Math.min(1, Number(j.progress) || 0)); }
    function tone(state) {
        if (state === "running") return "accent";
        if (state === "done") return "ok";
        if (state === "error") return "error";
        if (state === "paused") return "warn";
        return "neutral";
    }
    function label(state) {
        if (state === "running") return Tr.t("Syncing");
        if (state === "paused") return Tr.t("Paused");
        if (state === "done") return Tr.t("Up to date");
        if (state === "error") return Tr.t("Failed");
        return Tr.t("Idle");
    }
    function bytes(n) {
        const v = Number(n) || 0;
        if (v >= 1073741824) return (v / 1073741824).toFixed(1) + " GB";
        if (v >= 1048576) return (v / 1048576).toFixed(1) + " MB";
        if (v >= 1024) return (v / 1024).toFixed(0) + " KB";
        return v + " B";
    }
    function add() {
        const id = idField.text.trim(), remote = remoteField.text.trim(), local = localPicker.value.trim();
        if (!/^[A-Za-z0-9][A-Za-z0-9 _-]{0,40}$/.test(id)) { win.notice = Tr.t("Give the job a name of letters and digits"); return; }
        if (!/^[^:]+:.+/.test(remote)) { win.notice = Tr.t("The remote is remote:path, e.g. drive:Photos"); return; }
        if (!local.startsWith("/")) { win.notice = Tr.t("Pick a local folder"); return; }
        win.notice = "";
        CloudSync.add(id, remote, local, win.directionChoice, win.conflictChoice, bandwidthField.text.trim(),
                      parseInt(intervalField.text.trim(), 10) || 0);
        idField.text = ""; remoteField.text = ""; localPicker.value = "";
    }
    Component.onCompleted: CloudSync.loadRemotes()

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: win.visible = false
    }

    Glass {
        anchors.fill: parent
        radius: Theme.radiusLarge
        strong: true

        ColumnLayout {
            anchors { fill: parent; margins: Theme.px(16) }
            spacing: Theme.px(10)

            // ---- header -----------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Cloud sync")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(17) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton {
                    icon: "view-refresh"; tip: Tr.t("Refresh"); size: Theme.px(22)
                    onClicked: CloudSync.refresh()
                }
                IconButton {
                    icon: "window-close"; tip: Tr.t("Close"); size: Theme.px(22)
                    onClicked: win.visible = false
                }
            }
            InfoBanner {
                objectName: "cloud-error"
                Layout.fillWidth: true
                visible: !CloudSync.available || CloudSync.error !== "" || win.notice !== ""
                tone: "error"
                iconName: "dialog-error"
                title: !CloudSync.available ? Tr.t("Could not load cloud sync")
                     : CloudSync.error !== "" ? Tr.t("Could not sync") : Tr.t("Check the job details")
                text: !CloudSync.available ? Tr.t("rclone is not installed — cloud sync cannot run")
                                           : (CloudSync.error !== "" ? CloudSync.error : win.notice)
                accessibleRole: Accessible.StatusBar
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.px(12)

                // ---- new job -------------------------------------------------------
                Flickable {
                    Layout.preferredWidth: Theme.px(330)
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: form.implicitHeight
                    clip: true
                    flickableDirection: Flickable.VerticalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: form
                        width: parent.width
                        spacing: Theme.px(8)
                        Text {
                            text: Tr.t("New sync job")
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(13) * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        TextField {
                            id: idField
                            Layout.fillWidth: true
                            placeholder: Tr.t("Name, e.g. Photos")
                            label: Tr.t("Job name")
                            Accessible.name: Tr.t("Job name")
                        }
                        Text {
                            text: Tr.t("Remote — pick a cloud, then add a path")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.px(5)
                            Repeater {
                                model: CloudSync.remotes
                                Choice {
                                    required property var modelData
                                    text: modelData.name + ":"
                                    onClicked: remoteField.text = modelData.name + ":"
                                }
                            }
                        }
                        TextField {
                            id: remoteField
                            Layout.fillWidth: true
                            placeholder: "drive:Photos"
                            label: Tr.t("Remote path")
                            Accessible.name: Tr.t("Remote path")
                        }
                        FolderPicker {
                            id: localPicker
                            label: Tr.t("Local folder")
                            placeholder: Tr.t("Choose a folder on this computer")
                        }
                        Text {
                            text: Tr.t("Direction")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Repeater {
                                model: [["download", Tr.t("Download")], ["upload", Tr.t("Upload")]]
                                Choice {
                                    required property var modelData
                                    text: modelData[1]
                                    selected: win.directionChoice === modelData[0]
                                    onClicked: win.directionChoice = modelData[0]
                                }
                            }
                        }
                        Text {
                            text: Tr.t("If a file exists there already")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.px(5)
                            Repeater {
                                model: [["rename", Tr.t("Rename")], ["keepboth", Tr.t("Keep both")], ["skip", Tr.t("Skip")]]
                                Choice {
                                    required property var modelData
                                    text: modelData[1]
                                    selected: win.conflictChoice === modelData[0]
                                    onClicked: win.conflictChoice = modelData[0]
                                }
                            }
                        }
                        TextField {
                            id: bandwidthField
                            Layout.fillWidth: true
                            placeholder: Tr.t("e.g. 2M — blank means no limit")
                            label: Tr.t("Bandwidth limit")
                            Accessible.name: Tr.t("Bandwidth limit")
                        }
                        TextField {
                            id: intervalField
                            Layout.fillWidth: true
                            placeholder: Tr.t("Repeat every, in seconds — 0 means by hand")
                            label: Tr.t("Repeat interval")
                            mode: "digits"
                            Accessible.name: Tr.t("Repeat interval in seconds")
                        }
                        Button {
                            Layout.fillWidth: true
                            kind: "primary"
                            text: Tr.t("Add job")
                            enabled: CloudSync.available
                            onClicked: win.add()
                        }
                    }
                }

                // ---- jobs ----------------------------------------------------------
                ListView {
                    id: jobs
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: CloudSync.jobs
                    clip: true
                    reuseItems: true
                    spacing: Theme.px(8)
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: jobs.width
                        radius: Theme.radiusSmall
                        color: Theme.surface1
                        border.width: win.selected === row.modelData.id ? 1 : 0
                        border.color: Theme.accent
                        implicitHeight: inner.implicitHeight + Theme.px(16)
                        ColumnLayout {
                            id: inner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.px(8) }
                            spacing: Theme.px(6)
                            RowLayout {
                                Layout.fillWidth: true
                                MouseArea {
                                    Layout.fillWidth: true
                                    implicitHeight: title.implicitHeight
                                    onClicked: win.selected = win.selected === row.modelData.id ? "" : row.modelData.id
                                    Text {
                                        id: title
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: row.modelData.id + " · " + row.modelData.direction
                                        color: Theme.text
                                        elide: Text.ElideMiddle
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(13) * Theme.fontScale
                                        font.weight: Font.DemiBold
                                    }
                                }
                                StatusPill {
                                    text: win.label(row.modelData.state)
                                    tone: win.tone(row.modelData.state)
                                }
                                IconButton {
                                    visible: row.modelData.state !== "running" && row.modelData.state !== "paused"
                                    icon: "media-playback-start"; size: Theme.px(24)
                                    tip: Tr.t("Start %1").arg(row.modelData.id)
                                    onClicked: CloudSync.start(row.modelData.id)
                                }
                                IconButton {
                                    visible: row.modelData.state === "running"
                                    icon: "media-playback-pause"; size: Theme.px(24)
                                    tip: Tr.t("Pause %1").arg(row.modelData.id)
                                    onClicked: CloudSync.pause(row.modelData.id)
                                }
                                IconButton {
                                    visible: row.modelData.state === "paused"
                                    icon: "media-playback-start"; size: Theme.px(24)
                                    tip: Tr.t("Resume %1").arg(row.modelData.id)
                                    onClicked: CloudSync.resume(row.modelData.id)
                                }
                                IconButton {
                                    visible: row.modelData.state === "running" || row.modelData.state === "paused"
                                    icon: "media-playback-stop"; size: Theme.px(24)
                                    tip: Tr.t("Stop %1").arg(row.modelData.id)
                                    onClicked: CloudSync.stop(row.modelData.id)
                                }
                                IconButton {
                                    icon: "list-remove"; size: Theme.px(24)
                                    tip: Tr.t("Remove %1").arg(row.modelData.id)
                                    onClicked: CloudSync.remove(row.modelData.id)
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (row.modelData.direction === "upload"
                                       ? row.modelData.local + " → " + row.modelData.remote
                                       : row.modelData.remote + " → " + row.modelData.local)
                                color: Theme.dim
                                elide: Text.ElideMiddle
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                                Accessible.name: row.modelData.remote + " to " + row.modelData.local
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.px(6)
                                radius: Theme.px(3)
                                color: Theme.surface3
                                visible: row.modelData.state === "running" || row.modelData.state === "paused" || row.modelData.state === "done"
                                Accessible.role: Accessible.ProgressBar
                                Accessible.name: Tr.t("Progress of %1").arg(row.modelData.id)
                                Accessible.value: win.percent(row.modelData) * 100
                                Rectangle {
                                    width: parent.width * win.percent(row.modelData)
                                    height: parent.height
                                    radius: parent.radius
                                    color: Theme.accent
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: row.modelData.state === "running" || row.modelData.state === "paused"
                                text: (row.modelData.file || Tr.t("Preparing…")) + " · " + win.bytes(row.modelData.transferred)
                                      + " / " + win.bytes(row.modelData.total)
                                color: Theme.dim
                                elide: Text.ElideMiddle
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                            InfoBanner {
                                objectName: "cloud-job-error"
                                Layout.fillWidth: true
                                visible: row.modelData.state === "error"
                                tone: "error"
                                title: Tr.t("Could not sync %1", row.modelData.id)
                                text: row.modelData.error
                            }
                            // ---- settings and history, revealed by the title ----------
                            GridLayout {
                                Layout.fillWidth: true
                                visible: win.selected === row.modelData.id
                                columns: 2
                                Text { text: Tr.t("Conflicts"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                                RowLayout {
                                    spacing: Theme.px(4)
                                    Repeater {
                                        model: [["rename", Tr.t("Rename")], ["keepboth", Tr.t("Keep both")], ["skip", Tr.t("Skip")]]
                                        Choice {
                                            required property var modelData
                                            text: modelData[1]
                                            selected: row.modelData.conflict === modelData[0]
                                            onClicked: CloudSync.settings(row.modelData.id, modelData[0],
                                                                          row.modelData.bandwidth || "", row.modelData.interval || 0)
                                        }
                                    }
                                }
                                Text { text: Tr.t("Bandwidth"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                                TextField {
                                    Layout.fillWidth: true
                                    text: row.modelData.bandwidth || ""
                                    placeholder: Tr.t("e.g. 2M")
                                    Accessible.name: Tr.t("Bandwidth limit for %1").arg(row.modelData.id)
                                    onAccepted: CloudSync.settings(row.modelData.id, row.modelData.conflict,
                                                                   text.trim(), row.modelData.interval || 0)
                                }
                                Text { text: Tr.t("Repeat every (seconds)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                                TextField {
                                    Layout.fillWidth: true
                                    text: String(row.modelData.interval || 0)
                                    mode: "digits"
                                    Accessible.name: Tr.t("Repeat interval for %1").arg(row.modelData.id)
                                    onAccepted: CloudSync.settings(row.modelData.id, row.modelData.conflict,
                                                                   row.modelData.bandwidth || "", parseInt(text.trim(), 10) || 0)
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: win.selected === row.modelData.id && row.modelData.history && row.modelData.history.length > 0
                                text: Tr.t("Last runs")
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                            Repeater {
                                model: win.selected === row.modelData.id ? (row.modelData.history || []).slice().reverse().slice(0, 8) : []
                                Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: new Date(modelData.time * 1000).toLocaleString(Qt.locale()) + " · " + win.label(modelData.state)
                                          + (modelData.error ? " · " + modelData.error : "")
                                    color: Theme.faint
                                    elide: Text.ElideMiddle
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(10) * Theme.fontScale
                                }
                            }
                        }
                    }
                    EmptyState {
                        objectName: "cloud-empty"
                        anchors.centerIn: parent
                        width: Math.min(parent.width - Theme.px(30), Theme.px(360))
                        visible: jobs.count === 0
                        icon: "folder-remote"
                        title: Tr.t("No sync jobs yet")
                        subtitle: Tr.t("Choose a cloud folder and a local folder to copy between them")
                        actionText: Tr.t("Try again")
                        onAction: CloudSync.refresh()
                    }
                }
            }
        }
    }
}
