// Scheduled tasks — the thin view over the existing engines:
//   - Automations (Services/Automations): "when X, do Y" rules in
//     Settings.data.automations, fired on the become-true transition.
//   - Hooks (Services/Hooks): user shell scripts on shell events,
//     Settings.data.hooks (enabled + one field per event).
// No engine of its own here: the list reads the services, the run/pause
// toggle writes their on flags, delete splices the array.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: Tr.t("Scheduled tasks")
    visible: Ui.scheduled
    onGone: Ui.scheduled = false
    implicitWidth: Theme.px(560)
    implicitHeight: Theme.px(680)

    readonly property var rules: Automations.rules
    readonly property var fired: Automations.fired   // newest 50 firings: { at, rule }
    readonly property var hooks: Settings.data.hooks || {}

    readonly property var whens: [
        { id: "wifi", label: Tr.t("Joining Wi-Fi"), ask: true },
        { id: "power", label: Tr.t("Power"), choices: ["plugged", "battery"] },
        { id: "output", label: Tr.t("Sound output"), ask: true },
        { id: "displays", label: Tr.t("Screens"), choices: ["1", "2", "3"] },
        { id: "time", label: Tr.t("Time"), ask: true }]
    readonly property var thens: [
        { id: "focus", label: Tr.t("Turn on focus mode") },
        { id: "dnd", label: Tr.t("Turn Do not disturb on or off") },
        { id: "volume", label: Tr.t("Set the volume"), ask: true },
        { id: "style", label: Tr.t("Switch the style"), choices: ["dark", "light"] },
        { id: "open", label: Tr.t("Open an app"), ask: true },
        { id: "run", label: Tr.t("Run a command"), ask: true }]
    readonly property var hookKeys: [
        { key: "wallpaperChange", label: Tr.t("the wallpaper changes") },
        { key: "darkModeChange", label: Tr.t("dark style turns on or off") },
        { key: "screenLock", label: Tr.t("the screen locks") },
        { key: "screenUnlock", label: Tr.t("the screen unlocks") },
        { key: "startup", label: Tr.t("the desktop starts") },
        { key: "colorGeneration", label: Tr.t("colors are generated") }]

    // ---- the list over Automations ------------------------------------------
    function sentence(r) {
        const w = { wifi: Tr.t("On joining %1").arg(r.is), power: r.is === "battery" ? Tr.t("On battery") : Tr.t("When plugged in"),
                    output: Tr.t("When sound goes to %1").arg(r.is), displays: Tr.t("With %1 screen").arg(r.is),
                    time: Tr.t("At %1").arg(r.is) }[r.when] || r.when;
        const t = { focus: r.arg ? Tr.t("turn on %1").arg(r.arg) : Tr.t("end the focus mode"),
                   dnd: Tr.t("turn Do not disturb %1").arg(r.arg), volume: Tr.t("set the volume to %1%").arg(r.arg),
                   style: Tr.t("use the %1 style").arg(r.arg), open: Tr.t("open %1").arg(r.arg),
                   run: Tr.t("run %1").arg(r.arg) }[r.then] || r.then;
        return w + ", " + t;
    }
    function setRuleOn(i, on) {
        const l = Automations.rules.slice();
        l[i] = Object.assign({}, l[i], { on: on !== false });
        Automations.prime();   // re-arm: wasTrue was rebuilt at prime, not per edit
        Automations.rulesChanged();
    }
    function runNow(r) { Automations.act(r); }
    function removeRule(i) {
        const l = Automations.rules.slice();
        l.splice(i, 1);
        Automations.rulesChanged();
    }

    // ---- the add form (kept small; Adds goes through Automations' rules array)
    property string when: "wifi"
    property string is: ""
    property string then: "focus"
    property string arg: ""
    property string formNote: ""
    readonly property var w: whens.find(x => x.id === when)
    readonly property var t: thens.find(x => x.id === then)
    Timer { id: noteTimer; interval: 6000; onTriggered: win.formNote = "" }
    function showNote(msg) { win.formNote = msg; noteTimer.restart(); }
    function resetForm() { win.when = "wifi"; win.is = ""; win.then = "focus"; win.arg = ""; }
    function addRule() {
        if (win.is === "") { win.showNote(Tr.t("Pick what starts the rule")); return; }
        if ((win.then === "run" || win.then === "volume") && win.arg === "") {
            win.showNote(Tr.t("That action needs a value")); return;
        }
        Automations.rules.push(Object.assign({ on: true }, { when: win.when, is: win.is, then: win.then, arg: win.arg }));
        win.formNote = ""; win.resetForm();
    }
    // ---- bring an open task's due time in as a rule ----------------------------
    property bool taskPicker: false
    readonly property var schedulableTasks: Tasks.open.filter(t => t.due > 0)
    function taskClock(t) {
        const d = new Date((t && t.due || 0) * 1000);
        return t && t.due && !isNaN(d.getTime()) ? Qt.formatTime(d, "HH:mm") : "";
    }
    function shellQuote(s) { return "'" + String(s || "").replace(/'/g, "'\\''") + "'"; }
    function addFromTask(t) {
        if (!t || !t.due) return;
        // one rule per task: a second click or a reschedule must not pile up rules
        if (Automations.rules.some(r => r.uid === t.uid)) {
            win.showNote(Tr.t("That task already has a rule")); return;
        }
        Automations.rules.push({ uid: t.uid, when: "time", is: win.taskClock(t),
                                 then: "run", arg: "notify-send " + win.shellQuote(t.summary || Tr.t("Task")), on: true });
        Settings.save();
        win.taskPicker = false; win.formNote = "";
    }

    Item {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: { win.visible = false; Ui.scheduled = false; }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(10)

            SectionTitle { Layout.fillWidth: true; text: Tr.t("Scheduled rules") }
            Text {
                Layout.fillWidth: true
                text: Tr.t("A rule fires once, when its moment comes — joining Wi-Fi turns on Focus, plugging in changes the volume.")
                color: Theme.dim; wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            ListView {
                id: list
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                model: win.rules
                spacing: 2
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: list.width; height: Theme.px(46); radius: Theme.radiusSmall
                    Accessible.role: Accessible.ListItem
                    Accessible.name: win.sentence(modelData)
                    RowLayout {
                        anchors { fill: parent; leftMargin: Theme.px(6); rightMargin: Theme.px(6) }
                        spacing: Theme.px(6)
                        SwitchRow {
                            Layout.fillWidth: true
                            text: win.sentence(modelData)
                            checked: modelData.on !== false
                            onToggled: on => win.setRuleOn(list.index, on)
                            Keys.onPressed: e => { if (e.key === Qt.Key_Space) { win.setRuleOn(list.index, !modelData.on); e.accepted = true; } }
                            KeyFocus { name: win.sentence(modelData); onActivated: win.setRuleOn(list.index, !modelData.on) }
                        }
                        IconButton {
                            size: Theme.px(28)
                            icon: "media-play"
                            tip: Tr.t("Run now")
                            Accessible.name: Tr.t("Run now: ") + win.sentence(modelData)
                            onClicked: win.runNow(modelData)
                        }
                        IconButton {
                            size: Theme.px(28)
                            icon: "edit-delete"
                            tip: Tr.t("Delete")
                            Accessible.name: Tr.t("Delete: ") + win.sentence(modelData)
                            onClicked: win.removeRule(list.index)
                        }
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: win.rules.length === 0
                    icon: "view-list-details"
                    title: Tr.t("No scheduled rules")
                    subtitle: Tr.t("Rules fire once, when their trigger happens")
                    actionText: Tr.t("Add a rule")
                    onAction: formWhen.forceActiveFocus()
                }
            }

            // ---- the add form ------------------------------------------------
            SectionTitle { Layout.fillWidth: true; text: Tr.t("Add a rule") }
            Flow {
                id: formWhen
                Layout.fillWidth: true; spacing: Theme.px(6)
                Repeater {
                    model: win.whens
                    Choice {
                        required property var modelData
                        text: modelData.label
                        selected: win.when === modelData.id
                        onClicked: { win.when = modelData.id; win.is = modelData.choices ? modelData.choices[0] : ""; }
                    }
                }
            }
            // the trigger's value: chips, a picker for time, or typed
            ColumnLayout {
                id: formIs
                Layout.fillWidth: true; spacing: Theme.px(4)
                Flow {
                    visible: !!win.w && !!win.w.choices
                    Layout.fillWidth: true; spacing: Theme.px(6)
                    Repeater {
                        model: win.w ? win.w.choices : []
                        Choice {
                            required property string modelData
                            text: modelData
                            selected: win.is === modelData
                            onClicked: win.is = modelData
                        }
                    }
                }
                TimePicker {
                    visible: win.when === "time"
                    label: Tr.t("At this time")
                    value: win.is || "09:00"
                    onPicked: t => win.is = t
                }
                TextField {
                    id: typedIs
                    visible: !!(win.w && win.w.ask)
                    Layout.fillWidth: true
                    placeholder: Tr.t("Type the value, e.g. my Wi-Fi name")
                    text: win.is
                    onAccepted: win.is = text.trim()
                }
            }
            Flow {
                Layout.fillWidth: true; spacing: Theme.px(6)
                Text { text: Tr.t("then"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Repeater {
                    model: win.thens
                    Choice {
                        required property var modelData
                        text: modelData.label
                        selected: win.then === modelData.id
                        onClicked: { win.then = modelData.id; win.arg = ""; }
                    }
                }
            }
            Flow {
                Layout.fillWidth: true; spacing: Theme.px(6)
                visible: !!win.t && !!win.t.choices
                Repeater {
                    model: win.t ? win.t.choices : []
                    Choice {
                        required property string modelData
                        text: modelData
                        selected: win.arg === modelData
                        onClicked: win.arg = modelData
                    }
                }
            }
            TextField {
                id: typedArg
                visible: win.then === "run" || (win.then === "volume" && false)
                Layout.fillWidth: true
                placeholder: Tr.t("Shell command, e.g. notify-send it works")
                text: win.arg
                onAccepted: win.arg = text.trim()
            }
            Text {
                Layout.fillWidth: true
                visible: win.formNote !== ""
                text: win.formNote
                color: Theme.danger; wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.StaticText; Accessible.name: win.formNote
            }
            Button {
                Layout.fillWidth: true
                text: Tr.t("Add rule")
                enabled: win.is !== ""
                onClicked: win.addRule()
            }

            // ---- open tasks as rules -------------------------------------------
            SectionTitle { Layout.fillWidth: true; text: Tr.t("From Tasks") }
            Button {
                flat: true
                text: Tr.t("Add from Tasks")
                Accessible.name: Tr.t("Schedule a rule from an open task")
                onClicked: { win.taskPicker = !win.taskPicker; if (win.taskPicker) Tasks.refresh(); }
            }
            ColumnLayout {
                visible: win.taskPicker
                Layout.fillWidth: true
                spacing: Theme.px(2)
                Repeater {
                    model: win.schedulableTasks
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: Theme.px(6)
                        Text {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            text: modelData.summary + " · " + win.taskClock(modelData)
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                            Accessible.name: text
                        }
                        Button {
                            flat: true
                            text: Tr.t("Add rule")
                            Accessible.name: Tr.t("Schedule %1").arg(modelData.summary)
                            onClicked: win.addFromTask(modelData)
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: win.schedulableTasks.length === 0
                    text: Tr.t("No open tasks have a due time")
                    color: Theme.dim; wrapMode: Text.WordWrap
                    font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }

            // ---- hooks over Services/Hooks ------------------------------------
            SectionTitle { Layout.fillWidth: true; text: Tr.t("Commands on shell events") }
            SwitchRow {
                Layout.fillWidth: true
                text: Tr.t("Run my commands")
                checked: !!win.hooks.enabled
                onToggled: on => { const h = Object.assign({}, win.hooks); h.enabled = on; Settings.data.hooks = h; }
            }
            Repeater {
                model: win.hookKeys
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: Theme.px(8)
                    Text { text: modelData.label; color: Theme.dim; Layout.preferredWidth: Theme.px(120) }
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; color: Theme.text
                           text: win.hooks[modelData.key] || Tr.t("(not set)")
                           font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                }
            }

            // ---- the history the engine keeps --------------------------------
            SectionTitle {
                Layout.fillWidth: true
                text: Tr.t("Recent firings") + (win.fired.length > 0 ? " (" + win.fired.length + ")" : "")
            }
            Text {
                Layout.fillWidth: true
                visible: win.fired.length === 0
                text: Tr.t("Nothing has fired yet")
                color: Theme.dim
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Repeater {
                model: win.fired
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: Theme.px(8)
                    Text { text: Qt.formatDateTime(modelData.at, "hh:mm"); color: Theme.dim
                           font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    Text { Layout.fillWidth: true; text: modelData.rule; elide: Text.ElideRight
                           font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                }
            }
        }
    }
}
