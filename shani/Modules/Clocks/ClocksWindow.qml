// Clocks: the world's time, alarms, a stopwatch and a timer in one window.
// The clocks themselves are Services/WorldClock's and FocusTimer's - the same
// alarms and stopwatch the sidebar shows, so one started here is running there.
// This window adds the management around them: edit an alarm in place, group
// and filter alarms, manage snoozes, keep several timers, copy lap splits, add
// a city, convert a time between zones and reach every control by keyboard.
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Clocks"
    visible: Ui.clocks
    onGone: Ui.clocks = false
    implicitWidth: Theme.px(460)
    implicitHeight: Theme.px(520)

    property string tab: Ui.clocksTab || "world"      // world | alarms | stopwatch | timer
    onTabChanged: Ui.clocksTab = tab
    property string alarmTime: Qt.formatTime(new Date(Date.now() + 3600000), "HH:mm")
    property string alarmLabel: ""
    property var alarmDays: []             // empty = every day; 0=Sun .. 6=Sat
    property string alarmGroup: ""         // optional named group, e.g. "Weekdays"
    property string alarmFilter: ""        // "" = all groups
    property int editingAlarm: -1          // >= 0 means the form edits this alarm
    property int snoozeMinutes: 9
    property int timerMinutes: 5
    property bool lapsCopied: false
    property int lastTimerMinutes: 0
    readonly property var alarms: Array.from(WorldClock.alarms || [])
    // an alarm removed elsewhere shifts every index: drop a pending confirmation
    // so the second tap cannot delete a different alarm
    onAlarmsChanged: win.confirmAlarm = -1
    // a row asks before it removes an alarm: two taps, the second within 4 s
    property int confirmAlarm: -1
    Timer { id: alarmTimer; interval: 4000; onTriggered: win.confirmAlarm = -1 }
    Timer { id: copyTimer; interval: 2500; onTriggered: win.lapsCopied = false }

    // Home / End jump to the first / last tab; the page keys step through them.
    // While the person is typing, those keys belong to the text field instead.
    readonly property bool textFocus: labelField.activeFocus || groupField.activeFocus
        || zoneSearch.activeFocus || convFrom.activeFocus || convTo.activeFocus
        || convTime.activeFocus || timerName.activeFocus || timerCustom.activeFocus
    readonly property var tabs: ["world", "alarms", "stopwatch", "timer"]
    function navTab(delta) {
        const i = Math.max(0, win.tabs.indexOf(win.tab));
        win.tab = win.tabs[Math.min(win.tabs.length - 1, Math.max(0, i + delta))];
    }

    // flip an alarm on/off without losing its label, group or repeat days: the
    // service's addAlarm() takes both, removeAlarm() takes only an index.
    function toggleAlarm(index) {
        const item = (win.alarms || [])[index];
        if (!item) return;
        // edit in place: addAlarm would append a duplicate, drop the group and
        // shift every sidebar index
        WorldClock.updateAlarm(index, item.time, item.label,
            Array.isArray(item.days) ? item.days : [], item.enabled === false);
    }
    function editAlarm(index) {
        const a = win.alarms[index];
        if (!a) return;
        win.editingAlarm = index;
        win.alarmTime = a.time || win.alarmTime;
        win.alarmLabel = a.label || "";
        win.alarmDays = Array.isArray(a.days) ? Array.from(a.days) : [];
        win.alarmGroup = a.group || "";
        labelField.text = win.alarmLabel;
        groupField.text = win.alarmGroup;
    }
    function cancelAlarmEdit() {
        win.editingAlarm = -1;
        win.alarmTime = Qt.formatTime(new Date(Date.now() + 3600000), "HH:mm");
        win.alarmLabel = "";
        win.alarmDays = [];
        win.alarmGroup = "";
        labelField.text = "";
        groupField.text = "";
    }
    function saveAlarm() {
        let ok = false;
        const editing = win.alarms ? win.alarms[win.editingAlarm] : null;
        if (win.editingAlarm >= 0 && editing) {
            // update in place so the index the sidebar uses stays valid; a
            // removed alarm must not crash the save (fall through to add)
            ok = WorldClock.updateAlarm(win.editingAlarm, win.alarmTime, win.alarmLabel, win.alarmDays, editing.enabled !== false);
            if (ok) WorldClock.setAlarmGroup(win.editingAlarm, win.alarmGroup);
        } else {
            ok = WorldClock.addAlarm(win.alarmTime, win.alarmLabel, win.alarmDays);
            if (ok) WorldClock.setAlarmGroup(WorldClock.alarms.length - 1, win.alarmGroup);
        }
        if (ok) win.cancelAlarmEdit();
    }
    function alarmVisible(a) {
        return win.alarmFilter === "" || String(a.group || "") === win.alarmFilter;
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.clocks = false
        Keys.onSpacePressed: { if (win.tab === "stopwatch") WorldClock.swToggle(); }
        Keys.onPressed: e => {
            if (win.textFocus) return;               // let the field own Home / End
            if (e.key === Qt.Key_Home) { win.tab = win.tabs[0]; e.accepted = true; }
            else if (e.key === Qt.Key_End) { win.tab = win.tabs[win.tabs.length - 1]; e.accepted = true; }
            else if (e.key === Qt.Key_PageUp) { win.navTab(-1); e.accepted = true; }
            else if (e.key === Qt.Key_PageDown) { win.navTab(1); e.accepted = true; }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(12)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [["world", Tr.t("World")], ["alarms", Tr.t("Alarms")], ["stopwatch", Tr.t("Stopwatch")], ["timer", Tr.t("Timer")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.tab === modelData[0]
                        objectName: "clocks-tab-" + modelData[0]
                        onClicked: win.tab = modelData[0]
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // ---- the time here, always on top ----
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: win.tab === "world" || win.tab === "alarms"
                text: Qt.formatTime(clock.date, Settings.data.use24h ? "HH:mm:ss" : "h:mm:ss AP")
                color: Theme.text
                font.family: Theme.mono
                font.pixelSize: Theme.px(40) * Theme.fontScale
                font.weight: Font.DemiBold
                SystemClock { id: clock; precision: SystemClock.Seconds; enabled: win.visible }
            }

            // ---- world: city clocks plus an in-app zone picker and converter ----
            // the search results and converter are taller than the window, so
            // this tab scrolls like the alarms tab does
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.tab === "world"
                contentWidth: width
                contentHeight: worldCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: worldCol
                    width: parent.width
                    spacing: Theme.px(4)
                Repeater {
                    model: WorldClock.clocks
                    ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        icon: "preferences-system-time"
                        title: modelData.city
                        subtitle: modelData.zone
                        trailing: modelData.time
                        interactive: false
                        Button {
                            objectName: "clocks-remove-city"
                            Accessible.name: Tr.t("Remove world clock %1").arg(modelData.city)
                            text: Tr.t("Remove")
                            onClicked: WorldClock.removeWorldClock(modelData.zone)
                        }
                    }
                }
                EmptyState {
                    visible: WorldClock.clocks.length === 0
                    icon: "preferences-system-time"
                    title: Tr.t("No other cities yet")
                    subtitle: Tr.t("Search a zone below — or add cities in Settings")
                    actionText: Tr.t("Choose cities…")
                    onAction: zoneSearch.forceActiveFocus()
                }

                // GNOME Clocks / KClock let you find a city in the app; the
                // zone list is cached in the service, filtered as you type.
                TextField {
                    id: zoneSearch
                    Layout.fillWidth: true
                    label: Tr.t("Search time zones")
                    placeholder: Tr.t("City or zone — Tokyo, Berlin, New_York…")
                    objectName: "clocks-zone-search"
                }
                Text {
                    Layout.fillWidth: true
                    visible: WorldClock.zonesError !== ""
                    text: WorldClock.zonesError
                    color: Theme.danger
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Repeater {
                    model: zoneSearch.text.trim().length >= 2 ? WorldClock.matchingZones(zoneSearch.text) : []
                    ListRow {
                        required property string modelData
                        Layout.fillWidth: true
                        icon: "list-add"
                        title: modelData.replace(/_/g, " ")
                        subtitle: modelData
                        objectName: "clocks-zone-result"
                        onClicked: {
                            if (WorldClock.addWorldClock(modelData)) zoneSearch.text = "";
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: zoneSearch.text.trim().length >= 2 && WorldClock.matchingZones(zoneSearch.text).length === 0 && WorldClock.zonesError === ""
                    text: Tr.t("No matching time zones")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }

                // A time in one zone, read in another (DST handled by `date`).
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Text {
                        text: Tr.t("Convert a time")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    TextField {
                        id: convFrom
                        Layout.fillWidth: true
                        label: Tr.t("From zone")
                        placeholder: "Asia/Kolkata"
                        objectName: "clocks-convert-from"
                        onAccepted: convGo.clicked()
                    }
                    TextField {
                        id: convTo
                        Layout.fillWidth: true
                        label: Tr.t("To zone")
                        placeholder: "Europe/London"
                        objectName: "clocks-convert-to"
                        onAccepted: convGo.clicked()
                    }
                    TextField {
                        id: convTime
                        Layout.preferredWidth: Theme.px(78)
                        label: Tr.t("Time HH:MM")
                        placeholder: "09:00"
                        objectName: "clocks-convert-time"
                        onAccepted: convGo.clicked()
                    }
                    Button {
                        id: convGo
                        objectName: "clocks-convert-go"
                        Accessible.name: Tr.t("Convert the time to the second zone")
                        text: Tr.t("Convert")
                        onClicked: WorldClock.convertZoneTime(convFrom.text, convTo.text, convTime.text)
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: WorldClock.convertError !== ""
                    text: WorldClock.convertError
                    color: Theme.danger
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Text {
                    Layout.fillWidth: true
                    visible: WorldClock.convertResult !== ""
                    text: Tr.t("It is %1 there").arg(WorldClock.convertResult)
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                }
            }

            // ---- alarms ----
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.tab === "alarms"
                // the time picker is tall: the Add button must stay reachable
                contentWidth: width
                contentHeight: alarmsCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: alarmsCol
                    width: parent.width
                    spacing: Theme.px(6)

                    // groups are named in the form, then filter the list here
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(4)
                        visible: WorldClock.groups.length > 0
                        Text {
                            text: Tr.t("Group")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        Repeater {
                            model: [""].concat(Array.from(WorldClock.groups || []))
                            Choice {
                                required property string modelData
                                text: modelData === "" ? Tr.t("All") : modelData
                                selected: win.alarmFilter === modelData
                                objectName: "clocks-group-filter"
                                onClicked: win.alarmFilter = modelData
                            }
                        }
                    }

                    Repeater {
                        model: win.alarms
                        ColumnLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            visible: win.alarmVisible(modelData)
                            spacing: Theme.px(2)
                            ListRow {
                                Layout.fillWidth: true
                                icon: "alarm"
                                title: modelData.time + (modelData.label ? " — " + modelData.label : "") + (modelData.group ? " [" + modelData.group + "]" : "")
                                subtitle: (Array.isArray(modelData.days) && modelData.days.length ? Tr.t("Repeats") : Tr.t("Daily")) + " · " + (modelData.enabled === false ? Tr.t("Off") : Tr.t("On"))
                                selected: win.editingAlarm === index
                                // tapping the row asks first: a stray click must not lose an alarm
                                trailing: win.confirmAlarm === index ? Tr.t("Tap again to remove") : Tr.t("Remove")
                                onClicked: {
                                    if (win.confirmAlarm === index) { WorldClock.removeAlarm(index); win.confirmAlarm = -1; alarmTimer.restart(); }
                                    else { win.confirmAlarm = index; alarmTimer.restart(); }
                                }
                                Button {
                                    objectName: "clocks-alarm-toggle"
                                    Accessible.name: modelData.enabled === false ? Tr.t("Turn alarm on") : Tr.t("Turn alarm off")
                                    text: modelData.enabled === false ? Tr.t("On") : Tr.t("Off")
                                    onClicked: win.toggleAlarm(index)
                                }
                                Button {
                                    objectName: "clocks-alarm-edit"
                                    Accessible.name: Tr.t("Edit alarm at %1").arg(modelData.time)
                                    text: Tr.t("Edit")
                                    onClicked: win.editAlarm(index)
                                }
                            }
                            // Edit the label and sound right in the row: no
                            // second confirm (only removal needs that), no new
                            // store - both live on the alarm record itself.
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.px(10)
                                spacing: Theme.px(4)
                                TextField {
                                    Layout.fillWidth: true
                                    label: Tr.t("Alarm label")
                                    placeholder: Tr.t("Label — Wake up, …")
                                    text: modelData.label || ""
                                    objectName: "clocks-alarm-row-label"
                                    onAccepted: {
                                        if (!WorldClock.setAlarmLabel(index, text)) text = modelData.label || "";
                                    }
                                }
                                Button {
                                    objectName: "clocks-alarm-sound"
                                    Accessible.name: Tr.t("Sound: %1").arg(WorldClock.alarmSound(modelData.sound))
                                    text: WorldClock.alarmSound(modelData.sound)
                                    onClicked: {
                                        const sounds = WorldClock.alarmSounds;
                                        const cur = WorldClock.alarmSound(modelData.sound);
                                        WorldClock.setAlarmSound(index, sounds[(sounds.indexOf(cur) + 1) % sounds.length]);
                                    }
                                }
                            }
                        }
                    }
                    EmptyState {
                        visible: win.alarms.length === 0
                        icon: "alarm"
                        title: Tr.t("No alarms")
                        subtitle: Tr.t("Pick a time below — it rings once, with a notification")
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: win.alarms.length > 0 && !win.alarms.some(a => win.alarmVisible(a))
                        text: Tr.t("No alarms in this group")
                        color: Theme.dim
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Item { Layout.fillHeight: true }
                    TimePicker {
                        Layout.fillWidth: true
                        label: win.editingAlarm >= 0 ? Tr.t("Edit alarm time") : Tr.t("Alarm time")
                        value: win.alarmTime
                        onPicked: t => win.alarmTime = t
                    }
                    TextField {
                        id: labelField
                        Layout.fillWidth: true
                        placeholder: Tr.t("Label — Wake up, …")
                        label: Tr.t("Alarm label")
                        objectName: "clocks-alarm-label"
                        onTextChanged: win.alarmLabel = text
                        onAccepted: win.saveAlarm()
                    }
                    TextField {
                        id: groupField
                        Layout.fillWidth: true
                        placeholder: Tr.t("Group — Weekdays, Weekend…")
                        label: Tr.t("Alarm group")
                        objectName: "clocks-alarm-group"
                        onTextChanged: win.alarmGroup = text
                        onAccepted: win.saveAlarm()
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(6)
                        Button {
                            id: saveAlarm
                            Layout.fillWidth: true
                            kind: "primary"
                            objectName: "clocks-alarm-save"
                            Accessible.name: win.editingAlarm >= 0 ? Tr.t("Save alarm") : Tr.t("Add alarm at %1").arg(win.alarmTime)
                            text: win.editingAlarm >= 0 ? Tr.t("Save alarm") : Tr.t("Add alarm at %1").arg(win.alarmTime)
                            onClicked: win.saveAlarm()
                        }
                        Button {
                            Layout.fillWidth: true
                            visible: win.editingAlarm >= 0
                            objectName: "clocks-alarm-cancel"
                            text: Tr.t("Cancel edit")
                            onClicked: win.cancelAlarmEdit()
                        }
                    }
                    // CoreTime-style weekday repeat: nothing selected means every day
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(4)
                        Text { text: Tr.t("Repeat on"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                        Repeater {
                            model: [{ n: 0, l: "S" }, { n: 1, l: "M" }, { n: 2, l: "T" }, { n: 3, l: "W" }, { n: 4, l: "T" }, { n: 5, l: "F" }, { n: 6, l: "S" }]
                            Button {
                                required property var modelData
                                Layout.preferredWidth: Theme.px(34)
                                text: modelData.l
                                checked: win.alarmDays.indexOf(modelData.n) >= 0
                                Accessible.name: Tr.t("Repeat on %1").arg(modelData.n)
                                objectName: "clocks-repeat-day"
                                onClicked: {
                                    const d = Array.from(win.alarmDays);
                                    const i = d.indexOf(modelData.n);
                                    if (i >= 0) d.splice(i, 1); else d.push(modelData.n);
                                    win.alarmDays = d;
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text { text: win.alarmDays.length === 0 ? Tr.t("Every day") : Tr.t("Selected days"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    }

                    // step through snooze lengths like GNOME Clocks' 9 minutes,
                    // and cancel a pending one instead of only clearing all
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(4)
                        Text { text: Tr.t("Snooze"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                        Repeater {
                            model: [5, 9, 10, 15]
                            Choice {
                                required property int modelData
                                text: modelData + " " + Tr.t("min")
                                selected: win.snoozeMinutes === modelData
                                objectName: "clocks-snooze-length"
                                onClicked: win.snoozeMinutes = modelData
                            }
                        }
                    }
                    Repeater {
                        model: WorldClock.snoozes
                        ListRow {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            icon: "alarm"
                            title: modelData.label || Tr.t("Alarm")
                            subtitle: (modelData.group ? modelData.group + " · " : "") + Tr.t("Snoozed %1 min").arg(modelData.minutes)
                            trailing: Tr.t("Cancel")
                            objectName: "clocks-snooze-row"
                            onClicked: WorldClock.cancelSnooze(index)
                        }
                    }
                    Button {
                        Layout.fillWidth: true
                        objectName: "clocks-snooze-now"
                        text: Tr.t("Snooze %1 minutes").arg(win.snoozeMinutes)
                        onClicked: WorldClock.snooze(win.alarmLabel || win.alarmTime, win.snoozeMinutes, win.alarmGroup)
                    }
                }
            }

            // ---- stopwatch ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.tab === "stopwatch"
                spacing: Theme.px(8)
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: WorldClock.swDisplay
                    color: Theme.text
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(48) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Button { Layout.fillWidth: true; kind: "primary"; text: WorldClock.swRunning ? Tr.t("Pause") : Tr.t("Start"); objectName: "clocks-sw-toggle"; onClicked: WorldClock.swToggle() }
                    Button { Layout.fillWidth: true; text: Tr.t("Lap"); enabled: WorldClock.swRunning; objectName: "clocks-sw-lap"; onClicked: WorldClock.swLap() }
                    Button { Layout.fillWidth: true; text: Tr.t("Reset"); objectName: "clocks-sw-reset"; onClicked: WorldClock.swReset() }
                }
                ListView {
                    reuseItems: true
                    cacheBuffer: 400
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: WorldClock.swLaps
                    Keys.onHomePressed: if (count) currentIndex = 0
                    Keys.onEndPressed: if (count) currentIndex = count - 1
                    Keys.onPageUpPressed: currentIndex = Math.max(0, currentIndex - 8)
                    Keys.onPageDownPressed: currentIndex = Math.min(count - 1, currentIndex + 8)
                    delegate: ListRow {
                        required property string modelData
                        required property int index
                        width: ListView.view.width
                        icon: "alarm"
                        title: Tr.t("Lap %1").arg(index + 1)
                        // split time beside the cumulative one, as in GNOME Clocks
                        trailing: modelData + (WorldClock.swLapDeltas[index] ? "  " + WorldClock.swLapDeltas[index] : "")
                        interactive: false
                    }
                }
                EmptyState {
                    visible: WorldClock.swLaps.length === 0
                    icon: "alarm"
                    title: Tr.t("No laps yet")
                    subtitle: Tr.t("Start the stopwatch, then tap Lap for a split")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Button {
                        Layout.fillWidth: true
                        enabled: WorldClock.swLaps.length > 0
                        objectName: "clocks-sw-export"
                        Accessible.name: Tr.t("Copy all laps to the clipboard")
                        text: Tr.t("Copy laps")
                        onClicked: {
                            Quickshell.clipboardText = WorldClock.swExportText();
                            win.lapsCopied = true;
                            copyTimer.restart();
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: win.lapsCopied
                        text: Tr.t("Laps copied")
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
            }

            // ---- timer: pick how long, no typing ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.tab === "timer"
                spacing: Theme.px(10)
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: FocusTimer.running ? FocusTimer.label : "0:00"
                    color: FocusTimer.running ? Theme.accent : Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(48) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(6)
                    radius: Theme.px(3)
                    color: Theme.surface3
                    visible: FocusTimer.running
                    Rectangle {
                        width: FocusTimer.total > 0 ? parent.width * (1 - FocusTimer.left / FocusTimer.total) : 0
                        height: parent.height
                        radius: Theme.px(3)
                        color: Theme.accent
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: [1, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90]
                        Choice {
                            required property int modelData
                            text: modelData + " " + Tr.t("min")
                            selected: FocusTimer.running && FocusTimer.total === modelData * 60
                            objectName: "clocks-timer-preset"
                            onClicked: { win.lastTimerMinutes = modelData; FocusTimer.start(modelData); }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Button {
                        Layout.fillWidth: true
                        visible: win.lastTimerMinutes > 0
                        objectName: "clocks-timer-restart"
                        text: Tr.t("Restart %1 min").arg(win.lastTimerMinutes)
                        onClicked: FocusTimer.start(win.lastTimerMinutes)
                    }
                    Button {
                        Layout.fillWidth: true
                        visible: FocusTimer.running
                        kind: "danger"
                        objectName: "clocks-timer-stop"
                        text: Tr.t("Stop the timer")
                        onClicked: FocusTimer.stop()
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("It counts down in the Island too, and tells you when it is done.")
                    color: Theme.faint
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }

                // KClock and Apple Clock keep more than one timer at a time,
                // each with a name, pause / resume, restart and remove.
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Other timers")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Repeater {
                        model: [1, 3, 5, 10, 15, 25, 30]
                        Choice {
                            required property int modelData
                            text: modelData + " " + Tr.t("min")
                            selected: win.timerMinutes === modelData
                            objectName: "clocks-multitimer-preset"
                            onClicked: win.timerMinutes = modelData
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    TextField {
                        id: timerName
                        Layout.fillWidth: true
                        label: Tr.t("Timer name")
                        placeholder: Tr.t("Tea, presentation…")
                        objectName: "clocks-timer-name"
                    }
                    TextField {
                        id: timerCustom
                        Layout.preferredWidth: Theme.px(70)
                        label: Tr.t("Minutes")
                        placeholder: String(win.timerMinutes)
                        objectName: "clocks-timer-minutes"
                        mode: "digits"
                        error: text !== "" && !(Number(text) >= 1 && Number(text) <= 600) ? Tr.t("Use 1–600 minutes") : ""
                    }
                    Button {
                        objectName: "clocks-timer-add"
                        Accessible.name: Tr.t("Add a named timer")
                        text: Tr.t("Add timer")
                        enabled: timerCustom.error === ""
                        onClicked: {
                            if (WorldClock.addTimer(Number(timerCustom.text) || win.timerMinutes, timerName.text)) {
                                timerName.text = "";
                                timerCustom.text = "";
                            }
                        }
                    }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: WorldClock.timers
                    Keys.onHomePressed: if (count) currentIndex = 0
                    Keys.onEndPressed: if (count) currentIndex = count - 1
                    Keys.onPageUpPressed: currentIndex = Math.max(0, currentIndex - 8)
                    Keys.onPageDownPressed: currentIndex = Math.min(count - 1, currentIndex + 8)
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        icon: "alarm"
                        title: modelData.label
                        subtitle: modelData.running ? Tr.t("Running") : Tr.t("Paused")
                        trailing: WorldClock.fmt(modelData.left)
                        objectName: "clocks-multitimer-row"
                        onClicked: WorldClock.toggleTimer(index)
                        Button {
                            objectName: "clocks-multitimer-restart"
                            Accessible.name: Tr.t("Restart %1").arg(modelData.label)
                            text: Tr.t("Restart")
                            onClicked: WorldClock.restartTimer(index)
                        }
                        Button {
                            objectName: "clocks-multitimer-remove"
                            Accessible.name: Tr.t("Remove %1").arg(modelData.label)
                            text: Tr.t("Remove")
                            onClicked: WorldClock.removeTimer(index)
                        }
                    }
                }
                EmptyState {
                    visible: WorldClock.timers.length === 0
                    icon: "alarm"
                    title: Tr.t("No other timers")
                    subtitle: Tr.t("Pick minutes and a name above to run one alongside the Island timer")
                }
            }
        }
    }
}
