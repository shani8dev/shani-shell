// Health: steps, sleep, workouts, trends and spot readings in a window of the
// shell's own. Services/Health owns every read: bridge/health.py keeps a sqlite
// journal under XDG_DATA_HOME, so nothing here is uploaded and there is no
// account. A paired watch is optional — the local journal works without one.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Health"
    visible: Ui.health
    onGone: Ui.health = false
    implicitWidth: Theme.px(720)
    implicitHeight: Theme.px(640)

    property string logKind: "step"      // step | sleep | workout
    property string stepText: ""
    property string deepText: ""
    property string lightText: ""
    property string awakeText: ""
    property string workoutKind: ""
    property string workoutMinutes: ""
    readonly property bool hasJournal: Health.history.some(d => d.steps > 0 || d.deep_min > 0 || d.light_min > 0 || d.awake_min > 0) || Health.workouts.length > 0
    readonly property bool hasWatch: Health.connected && (!!Health.device || !!Health.deviceModel || Health.lastRead !== "")
    readonly property int steps2DaysAgo: Health.history.length >= 3 ? Math.max(0, Number(Health.history[Health.history.length - 3].steps) || 0) : 0
    readonly property int stepsYesterdayFromHistory: Health.history.length >= 2 ? Math.max(0, Number(Health.history[Health.history.length - 2].steps) || 0) : 0
    readonly property int barCeiling: Math.max(Health.stepsGoal, Health.stepsToday, win.steps2DaysAgo, win.stepsYesterdayFromHistory, 1)

    onVisibleChanged: if (visible) Health.refresh()

    function pickImport() {
        FilePicker.open({
            mode: "open",
            title: Tr.t("Import health data"),
            filters: ["csv", "json"],
            onPicked: paths => { if (paths && paths.length) Health.importFile(paths[0]); }
        });
    }
    function submit() {
        if (win.logKind === "step") Health.logStep(win.stepText);
        else if (win.logKind === "sleep") Health.logSleep(win.deepText, win.lightText, win.awakeText);
        else Health.logWorkout(win.workoutKind, win.workoutMinutes);
    }
    function clockTime(value) {
        const s = String(value || "");
        return s.length >= 16 ? s.slice(11, 16) : s;
    }
    function stageMinutes(stage) {
        return Health.sleepStages.reduce((n, s) => n + (String(s && s.stage).toLowerCase() === stage ? Math.max(0, Number(s && s.minutes) || 0) : 0), 0);
    }
    function stageTotal() {
        return Health.sleepStages.reduce((n, s) => n + Math.max(0, Number(s && s.minutes) || 0), 0);
    }
    function stressValues() {
        const src = Health.stressSeries.length ? Health.stressSeries : Health.stress;
        return src.map(p => Math.max(0, Math.min(100, Number(p && p.value) || 0)));
    }
    function stressWord(value) {
        const v = Math.max(0, Number(value) || 0);
        return v < 30 ? Tr.t("Relaxed") : v < 60 ? Tr.t("Normal") : v < 80 ? Tr.t("Medium") : Tr.t("High");
    }

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Ui.health = false
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: Theme.px(16)
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: parent.width
            spacing: Theme.px(10)

            // ---- header ------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                // the title is the window's own (AppWindow's header), not repeated here
                Item { Layout.fillWidth: true }
                Button {
                    text: Tr.t("Import…")
                    flat: true
                    Accessible.name: Tr.t("Import steps, sleep or workouts from a CSV or JSON file")
                    onClicked: win.pickImport()
                }
                Button {
                    text: Tr.t("Refresh")
                    flat: true
                    Accessible.name: Tr.t("Refresh health data")
                    onClicked: Health.refresh()
                }
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Stays on this computer — no account, no cloud, nothing uploaded.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StatusBar
                Accessible.name: text
            }

            // ---- companion switch --------------------------------------------
            SwitchRow {
                id: companion
                Layout.fillWidth: true
                text: Tr.t("Keep my watch connected to this computer")
                hint: Tr.t("Turn this off if your phone app needs the watch instead.")
                checked: Health.connected
                enabled: !Health.busy
                onToggled: value => Health.watchConnect(value)
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Staying connected lets this computer ring the watch and take readings.")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StatusBar
                Accessible.name: text
            }
            InfoBanner {
                objectName: "health-error"
                visible: Health.error !== ""
                Layout.fillWidth: true
                tone: "warn"
                iconName: "dialog-warning"
                title: Tr.t("Could not load health data")
                text: Health.error
                accessibleRole: Accessible.StatusBar
            }
            InfoBanner {
                objectName: "health-note"
                visible: Health.note !== ""
                Layout.fillWidth: true
                tone: "accent"
                text: Health.note
                accessibleRole: Accessible.StatusBar
            }

            // ---- no watch, no journal: a way forward, not a grid of zeros ----
            EmptyState {
                objectName: "health-no-watch"
                visible: !win.hasWatch && !win.hasJournal && Health.loaded && !Health.busy
                icon: "bluetooth"
                title: Tr.t("No watch yet")
                subtitle: Tr.t("Pair a watch or fitness band once, then connect it here to see steps, sleep and heart rate.")
                actionText: Tr.t("Connect a watch")
                onAction: Health.watchConnect(true)
            }

            // ---- the watch itself ---------------------------------------------
            Rectangle {
                objectName: "health-watch-header"
                visible: win.hasWatch
                Layout.fillWidth: true
                implicitHeight: watchRow.implicitHeight + Theme.px(16)
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.border
                RowLayout {
                    id: watchRow
                    anchors { fill: parent; margins: Theme.px(8) }
                    spacing: Theme.px(10)
                    Icon {
                        name: "alarm"
                        size: Theme.px(28)
                        color: Theme.accent
                        Accessible.ignored: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: Health.device || Health.deviceModel || Tr.t("My watch")
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(14) * Theme.fontScale
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Accessible.name: text
                        }
                        Text {
                            Layout.fillWidth: true
                            text: [Health.deviceModel, Health.deviceFirmware].filter(Boolean).join(" · ")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            elide: Text.ElideRight
                            visible: text !== ""
                        }
                        Text {
                            Layout.fillWidth: true
                            text: Health.lastRead ? Tr.t("Read at %1", win.clockTime(Health.lastRead)) : Tr.t("Not read yet")
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            Accessible.name: text
                        }
                    }
                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: Health.battery >= 0 ? Tr.t("%1 percent", Health.battery) : Tr.t("Battery not available")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            horizontalAlignment: Text.AlignRight
                            Accessible.name: text
                        }
                        Rectangle {
                            Layout.preferredWidth: Theme.px(64)
                            implicitHeight: Theme.px(6)
                            radius: Theme.px(3)
                            color: Theme.surface2
                            Rectangle {
                                width: parent.width * (Health.battery >= 0 ? Math.min(1, Math.max(0, Health.battery / 100)) : 0)
                                height: parent.height
                                radius: parent.radius
                                color: Health.battery >= 0 && Health.battery < 20 ? Theme.danger : Theme.success
                            }
                            Accessible.role: Accessible.Graphic
                            Accessible.name: Tr.t("Watch battery %1 percent", Math.max(0, Health.battery))
                        }
                    }
                    Button {
                        text: Tr.t("Refresh")
                        flat: true
                        enabled: !Health.busy
                        Accessible.name: Tr.t("Read the watch again")
                        onClicked: Health.refresh()
                    }
                }
            }

            // ---- activity: ring, km/kcal and the last three days --------------
            Rectangle {
                objectName: "health-activity"
                visible: win.hasWatch || win.hasJournal
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(170)
                clip: true
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.border
                ColumnLayout {
                    anchors { fill: parent; margins: Theme.px(10) }
                    spacing: Theme.px(6)
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("Activity")
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(13) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(10)
                        Item {
                            Layout.preferredWidth: Theme.px(108)
                            Layout.preferredHeight: Theme.px(108)
                            Canvas {
                                id: activityRing
                                anchors.fill: parent
                                antialiasing: true
                                Accessible.role: Accessible.Graphic
                                Accessible.name: Tr.t("%1 of %2 steps", Health.stepsToday, Health.stepsGoal)
                                Connections {
                                    target: Theme
                                    function onDarkTChanged() { activityRing.requestPaint(); }
                                }
                                Connections {
                                    target: Health
                                    function onStepsTodayChanged() { activityRing.requestPaint(); }
                                    function onStepsGoalChanged() { activityRing.requestPaint(); }
                                }
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.reset();
                                    const cx = width / 2, cy = height / 2;
                                    const r = Math.min(width, height) / 2 - Theme.px(5);
                                    ctx.lineWidth = Theme.px(9);
                                    ctx.lineCap = "round";
                                    ctx.strokeStyle = Theme.surface2;
                                    ctx.beginPath();
                                    ctx.arc(cx, cy, r, 0, Math.PI * 2);
                                    ctx.stroke();
                                    const part = Math.min(1, Math.max(0, Health.stepsToday / Math.max(1, Health.stepsGoal)));
                                    if (part > 0) {
                                        ctx.strokeStyle = Theme.success;
                                        ctx.beginPath();
                                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * part);
                                        ctx.stroke();
                                    }
                                }
                                Component.onCompleted: requestPaint()
                            }
                            Column {
                                anchors.centerIn: parent
                                spacing: 0
                                Text {
                                    width: Math.min(Theme.px(88), parent.parent.width)
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Health.stepsToday.toLocaleString()
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(18) * Theme.fontScale
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    width: Math.min(Theme.px(88), parent.parent.width)
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Tr.t("of %1 steps", Health.stepsGoal.toLocaleString())
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(10) * Theme.fontScale
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Text {
                                Layout.fillWidth: true
                                text: Tr.t("%1 km · %2 kcal", (Health.distanceM / 1000).toFixed(2), Health.calories)
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(12) * Theme.fontScale
                                Accessible.name: text
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(6)
                                Repeater {
                                    model: [
                                        [Tr.t("2 days ago"), win.steps2DaysAgo],
                                        [Tr.t("Yesterday"), win.stepsYesterdayFromHistory || Health.stepsYesterday],
                                        [Tr.t("Today"), Health.stepsToday]
                                    ]
                                    ColumnLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text {
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: (modelData[1] || 0).toLocaleString()
                                            color: Theme.dim
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(10) * Theme.fontScale
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: Theme.px(48)
                                            radius: Theme.radiusSmall
                                            color: Theme.surface2
                                            Rectangle {
                                                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                                height: parent.height * Math.min(1, Math.max(0, (modelData[1] || 0) / win.barCeiling))
                                                radius: parent.radius
                                                color: Theme.success
                                            }
                                            Accessible.role: Accessible.Graphic
                                            Accessible.name: Tr.t("%1: %2 steps", modelData[0], modelData[1] || 0)
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: modelData[0]
                                            color: Theme.faint
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(10) * Theme.fontScale
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Component.onCompleted: activityRing.requestPaint()
            }

            // ---- today's tiles -------------------------------------------------
            RowLayout {
                visible: win.hasWatch || win.hasJournal
                Layout.fillWidth: true
                spacing: Theme.px(8)

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.px(66)
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    border.width: 1
                    border.color: Theme.border
                    ColumnLayout {
                        anchors { fill: parent; margins: Theme.px(8) }
                        spacing: 2
                        Text {
                            text: Tr.t("Steps today")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        Text {
                            text: Health.stepsToday.toLocaleString()
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(20) * Theme.fontScale
                            font.weight: Font.DemiBold
                            Accessible.name: Tr.t("%1 steps today", Health.stepsToday)
                        }
                        Text {
                            text: !Health.device && !win.hasJournal ? Tr.t("Pair a watch, or log a day, to count steps")
                                : Tr.t("of %1 · %2 yesterday", Health.stepsGoal, Health.stepsYesterday)
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.px(66)
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    border.width: 1
                    border.color: Theme.border
                    ColumnLayout {
                        anchors { fill: parent; margins: Theme.px(8) }
                        spacing: 2
                        Text {
                            text: Tr.t("Asleep")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        Text {
                            text: Health.duration(Health.sleep.asleep)
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(20) * Theme.fontScale
                            font.weight: Font.DemiBold
                            Accessible.name: Tr.t("Asleep %1", Health.duration(Health.sleep.asleep))
                        }
                        Text {
                            // the computer measures nothing itself: without a watch it is what was logged
                            text: Health.device ? Tr.t("From %1", Health.device) : Tr.t("Logged by you · no watch paired")
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            elide: Text.ElideRight
                        }
                    }
                }
                Rectangle {
                    visible: Health.battery >= 0
                    Layout.fillWidth: true
                    implicitHeight: Theme.px(66)
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    border.width: 1
                    border.color: Theme.border
                    ColumnLayout {
                        anchors { fill: parent; margins: Theme.px(8) }
                        spacing: 2
                        Text {
                            text: Tr.t("Watch battery")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        Text {
                            text: Tr.t("%1 percent", Health.battery)
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(20) * Theme.fontScale
                            font.weight: Font.DemiBold
                            Accessible.name: Tr.t("Watch battery %1 percent", Health.battery)
                        }
                        Text {
                            text: Health.device || Tr.t("Paired watch")
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ---- stress -------------------------------------------------------
            Rectangle {
                objectName: "health-stress"
                visible: win.hasWatch || win.hasJournal
                Layout.fillWidth: true
                implicitHeight: Theme.px(122)
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.border
                RowLayout {
                    anchors { fill: parent; margins: Theme.px(8) }
                    spacing: Theme.px(8)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: Tr.t("Stress today")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        Text {
                            text: win.stressValues().length ? String(win.stressValues()[win.stressValues().length - 1]) : "—"
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(20) * Theme.fontScale
                            font.weight: Font.DemiBold
                            Accessible.name: win.stressValues().length ? Tr.t("Latest stress reading %1", win.stressValues()[win.stressValues().length - 1]) : Tr.t("No stress reading yet")
                        }
                        Text {
                            visible: win.stressValues().length > 0
                            text: Tr.t("%1 · %2", win.stressWord(win.stressValues()[win.stressValues().length - 1]),
                                       Health.stressSeries.length && Health.stressSeries[Health.stressSeries.length - 1].when
                                       ? win.clockTime(Health.stressSeries[Health.stressSeries.length - 1].when) : "")
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                    }
                    ColumnLayout {
                        Layout.preferredWidth: Theme.px(260)
                        spacing: 2
                        Text {
                            visible: win.stressValues().length > 0
                            text: Tr.t("%1 readings", win.stressValues().length)
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        Sparkline {
                            Layout.fillWidth: true
                            values: win.stressValues()
                            maximum: 100
                            color: Theme.accent
                            Accessible.role: Accessible.Graphic
                            Accessible.name: Tr.t("Stress over today")
                        }
                    }
                }
            }

            // ---- a week of steps ---------------------------------------------
            Text {
                visible: win.hasWatch || win.hasJournal
                Layout.fillWidth: true
                text: Tr.t("Steps this week")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Sparkline {
                visible: win.hasWatch || win.hasJournal
                Layout.fillWidth: true
                values: Health.stepsWeek
                maximum: Health.stepsGoal
                color: Theme.accent
                Accessible.role: Accessible.Graphic
                Accessible.name: Tr.t("Steps over the last seven days")
            }
            EmptyState {
                objectName: "health-loading"
                visible: !Health.loaded
                icon: "activity"
                title: Tr.t("Reading your journal…")
                subtitle: Tr.t("Nothing leaves this computer")
                actionText: Tr.t("Try again")
                onAction: Health.refresh()
            }

            // ---- sleep stages -------------------------------------------------
            Text {
                visible: win.hasWatch || win.hasJournal
                Layout.fillWidth: true
                text: Tr.t("Sleep stages")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            ColumnLayout {
                visible: win.hasWatch || win.hasJournal
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Repeater {
                    model: [
                        [Tr.t("Deep"), Health.sleep.deep, Theme.blue],
                        [Tr.t("Light"), Health.sleep.light, Theme.accent],
                        [Tr.t("REM"), Health.sleep.rem, Theme.blue],
                        [Tr.t("Awake"), Health.sleep.awake, Theme.amber]
                    ]
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Theme.px(6)
                        Text {
                            Layout.preferredWidth: Theme.px(56)
                            text: modelData[0]
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.px(9)
                            radius: Theme.px(4)
                            color: Theme.surface2
                            Rectangle {
                                width: Math.min(parent.width, parent.width * Math.min(1, modelData[1] / Math.max(1, Health.sleep.asleep + Health.sleep.awake + (Health.sleep.rem || 0))))
                                height: parent.height
                                radius: parent.radius
                                color: modelData[2]
                            }
                        }
                        Text {
                            Layout.preferredWidth: Theme.px(72)
                            horizontalAlignment: Text.AlignRight
                            text: Health.duration(modelData[1])
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                            Accessible.name: modelData[0] + ": " + Health.duration(modelData[1])
                        }
                    }
                }
                // the watch's own night, as one strip of stages
                Item {
                    visible: Health.sleepStages.length > 0
                    Layout.fillWidth: true
                    implicitHeight: Theme.px(12)
                    Repeater {
                        model: Health.sleepStages
                        Rectangle {
                            required property var modelData
                            required property int index
                            x: parent.width * Health.sleepStages.slice(0, index).reduce((n, s) => n + Math.max(0, Number(s && s.minutes) || 0), 0) / Math.max(1, win.stageTotal())
                            width: parent.width * Math.max(0.01, Math.max(0, Number(modelData.minutes) || 0) / Math.max(1, win.stageTotal()))
                            height: parent.height
                            color: String(modelData.stage).toLowerCase() === "deep" ? Theme.blue
                                 : String(modelData.stage).toLowerCase() === "awake" ? Theme.amber : Theme.accent
                            Accessible.role: Accessible.Graphic
                            Accessible.name: Tr.t("%1 %2", modelData.stage, Health.duration(modelData.minutes))
                        }
                    }
                }
                Text {
                    visible: Health.sleepStages.length > 0
                    Layout.fillWidth: true
                    text: Tr.t("Deep %1 · Light %2 · Awake %3",
                               Health.duration(win.stageMinutes("deep")),
                               Health.duration(win.stageMinutes("light")),
                               Health.duration(win.stageMinutes("awake")))
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                    Accessible.name: text
                }
            }

            // ---- daily trend --------------------------------------------------
            Text {
                visible: win.hasWatch || win.hasJournal
                Layout.fillWidth: true
                text: Tr.t("Daily trend")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            ListView {
                id: trend
                visible: win.hasWatch || win.hasJournal
                Layout.fillWidth: true
                implicitHeight: Theme.px(120)
                clip: true
                // rows only when there is something logged: all-zero days drew
                // "0 steps 0 min" lines underneath the empty state
                model: win.hasJournal ? Health.history.slice().reverse() : []
                Accessible.role: Accessible.List
                Accessible.name: Tr.t("Daily steps and sleep")
                delegate: RowLayout {
                    required property var modelData
                    width: trend.width
                    spacing: Theme.px(6)
                    Text {
                        Layout.preferredWidth: Theme.px(72)
                        elide: Text.ElideRight
                        text: Health.dayLabel(modelData.day)
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Text {
                        Layout.preferredWidth: Theme.px(96)
                        elide: Text.ElideRight
                        text: Tr.t("%1 steps", modelData.steps || 0)
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Health.duration((modelData.deep_min || 0) + (modelData.light_min || 0))
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: !win.hasJournal && !Health.busy
                    icon: "chart-line"
                    title: Tr.t("No history yet")
                    subtitle: Tr.t("Log a day or import a CSV/JSON file to see a trend")
                }
            }

            // ---- workouts -----------------------------------------------------
            Text {
                visible: win.hasWatch || win.hasJournal
                Layout.fillWidth: true
                text: Tr.t("Workouts")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            ListView {
                id: workouts
                visible: win.hasWatch || win.hasJournal
                Layout.fillWidth: true
                implicitHeight: Math.min(Theme.px(180), Health.workouts.length * Theme.px(48))
                clip: true
                model: Health.workouts
                Accessible.role: Accessible.List
                Accessible.name: Tr.t("Workouts")
                delegate: Rectangle {
                    required property var modelData
                    width: workouts.width
                    implicitHeight: Theme.px(44)
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    border.width: 1
                    border.color: Theme.border
                    RowLayout {
                        anchors { fill: parent; margins: Theme.px(6) }
                        spacing: Theme.px(6)
                        Text {
                            Layout.preferredWidth: Theme.px(72)
                            elide: Text.ElideRight
                            text: Health.dayLabel(modelData.day)
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.kind
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                            elide: Text.ElideRight
                        }
                        Text {
                            text: Health.duration(modelData.minutes)
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                    }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: Tr.t("%1 on %2, %3", modelData.kind, Health.dayLabel(modelData.day), Health.duration(modelData.minutes))
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: Health.workouts.length === 0
                    icon: "sports-mode"
                    title: Tr.t("No workouts yet")
                    subtitle: Tr.t("Log one below — or import a file")
                }
            }

            // ---- spot checks --------------------------------------------------
            Text {
                Layout.fillWidth: true
                text: Health.measures.length ? Tr.t("Last: %1", Health.reading(Health.measures[0]))
                    : Tr.t("Spot checks need a worn watch")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.StatusBar
                Accessible.name: text
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Button {
                    text: Tr.t("Heart rate")
                    flat: true
                    Accessible.name: Tr.t("Measure heart rate now")
                    onClicked: Health.spot("hr")
                }
                Button {
                    text: Tr.t("Oxygen")
                    flat: true
                    Accessible.name: Tr.t("Measure blood oxygen now")
                    onClicked: Health.spot("spo2")
                }
                Button {
                    text: Tr.t("Blood pressure")
                    flat: true
                    Accessible.name: Tr.t("Measure blood pressure now")
                    onClicked: Health.spot("bp")
                }
            }

            // ---- find my watch ------------------------------------------------
            // The phone backends already know how to ring a paired watch.
            Text {
                Layout.fillWidth: true
                text: Tr.t("Make a paired watch ring so you can find it")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StatusBar
                Accessible.name: text
            }
            Button {
                text: Tr.t("Find my watch")
                flat: true
                Accessible.name: Tr.t("Ring the paired watch")
                enabled: !Health.busy
                onClicked: Health.findWatch()
            }

            // ---- manual log ---------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Repeater {
                        model: [["step", Tr.t("Steps")], ["sleep", Tr.t("Sleep")], ["workout", Tr.t("Workout")]]
                        Choice {
                            required property var modelData
                            text: modelData[1]
                            selected: win.logKind === modelData[0]
                            Accessible.name: Tr.t("Log %1", modelData[1])
                            onClicked: win.logKind = modelData[0]
                        }
                    }
                }
            }
            RowLayout {
                visible: win.logKind === "step"
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("Steps")
                    label: Tr.t("Steps to log")
                    text: win.stepText
                    onTextChanged: win.stepText = text
                }
                Button {
                    text: Tr.t("Save steps")
                    kind: "primary"
                    Accessible.name: Tr.t("Save today's steps")
                    onClicked: win.submit()
                }
            }
            RowLayout {
                visible: win.logKind === "sleep"
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("Deep (min)")
                    label: Tr.t("Deep sleep minutes")
                    text: win.deepText
                    onTextChanged: win.deepText = text
                }
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("Light (min)")
                    label: Tr.t("Light sleep minutes")
                    text: win.lightText
                    onTextChanged: win.lightText = text
                }
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("Awake (min)")
                    label: Tr.t("Awake minutes")
                    text: win.awakeText
                    onTextChanged: win.awakeText = text
                }
                Button {
                    text: Tr.t("Save sleep")
                    kind: "primary"
                    onClicked: win.submit()
                }
            }
            RowLayout {
                visible: win.logKind === "workout"
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("Workout name")
                    label: Tr.t("Workout name")
                    text: win.workoutKind
                    onTextChanged: win.workoutKind = text
                }
                TextField {
                    Layout.preferredWidth: Theme.px(90)
                    placeholder: Tr.t("Minutes")
                    label: Tr.t("Workout minutes")
                    text: win.workoutMinutes
                    onTextChanged: win.workoutMinutes = text
                }
                Button {
                    text: Tr.t("Save workout")
                    kind: "primary"
                    onClicked: win.submit()
                }
            }
        }
    }
}
