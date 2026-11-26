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

            // ---- today's tiles -----------------------------------------------
            RowLayout {
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
                Layout.fillWidth: true
                implicitHeight: Theme.px(72)
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
                            text: Health.stress.length ? String(Health.stress[Health.stress.length - 1].value) : "—"
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(20) * Theme.fontScale
                            font.weight: Font.DemiBold
                            Accessible.name: Health.stress.length ? Tr.t("Latest stress reading %1", Health.stress[Health.stress.length - 1].value) : Tr.t("No stress reading yet")
                        }
                    }
                    Text {
                        visible: Health.stress.length > 0
                        text: Tr.t("%1 readings", Health.stress.length)
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                }
            }

            // ---- a week of steps ---------------------------------------------
            Text {
                Layout.fillWidth: true
                text: Tr.t("Steps this week")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Sparkline {
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
                Layout.fillWidth: true
                text: Tr.t("Sleep stages")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
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

            // ---- daily trend --------------------------------------------------
            Text {
                Layout.fillWidth: true
                text: Tr.t("Daily trend")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            ListView {
                id: trend
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
                Layout.fillWidth: true
                text: Tr.t("Workouts")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            ListView {
                id: workouts
                Layout.fillWidth: true
                implicitHeight: Math.min(Theme.px(140), Health.workouts.length * Theme.px(28))
                clip: true
                model: Health.workouts
                Accessible.role: Accessible.List
                Accessible.name: Tr.t("Workouts")
                delegate: RowLayout {
                    required property var modelData
                    width: workouts.width
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
