// The Chronoa surface: one conversation, tool activity inline, approvals in place.
// Talks to the shell through `model` + signals; the shell owns the bridge socket.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.Common

PanelWindow {
    id: panel

    property var model
    property bool open: false
    property bool busy: false
    property string state: "idle"
    property string detail: ""
    property string modelLabel: "local · llama.cpp · 8B"
    property color accent: Theme.accent
    property color amber: Theme.amber
    property color textColor: Theme.text
    property color dimColor: Theme.dim
    property int streamIndex: -1

    readonly property bool blurEnabled: Settings.data.blur && Quickshell.env("SHANI_BLUR") !== "0"

    signal ask(string text)
    signal action(string name)
    signal approve(string turnId, string decision)
    signal dismiss()

    function stateColor() {
        if (state === "listening" || state === "idle")
            return accent;
        if (state === "speaking")
            return Theme.blue;
        if (state === "waiting")
            return Theme.red;
        return amber;
    }

    function stateLabel() {
        if (state === "listening")
            return "listening";
        if (state === "thinking")
            return "thinking";
        if (state === "speaking")
            return "speaking";
        if (state === "waiting")
            return "waiting for you";
        if (state === "offline")
            return "offline";
        return "ready";
    }

    function scroll() {
        // The transcript is a Column inside a Flickable, so its height is the
        // content height; the end is one subtraction. (A ListView needed a
        // second layout pass here, and its recycled last delegate stayed
        // unpainted.)
        Qt.callLater(function () {
            list.contentY = Math.max(0, list.contentHeight - list.height);
        });
    }

    function blank(kind) {
        return {
            kind: kind, text: "", title: "", detail: "",
            turnId: "", decided: false, decision: "", optionsJson: "[]"
        };
    }

    function push(kind, text) {
        const row = blank(kind);
        row.text = text;
        model.append(row);
        scroll();
    }

    function addUser(text) {
        streamIndex = -1;
        push("user", text);
    }

    function addTool(text) {
        streamIndex = -1;
        push("tool", text);
    }

    function finishTool(ok) {
        for (let i = model.count - 1; i >= 0; i--) {
            if (model.get(i).kind === "tool") {
                model.setProperty(i, "text",
                                  model.get(i).text + (ok ? "  ✓" : "  ✗"));
                return;
            }
        }
    }

    function addSystem(text) {
        streamIndex = -1;
        push("system", text);
    }

    function addApproval(id, text, detail, options) {
        streamIndex = -1;
        const row = blank("approval");
        row.turnId = id;
        row.title = text;
        row.detail = detail;
        // One button per option the agent offered, so "Allow for this session"
        // reaches permissions.parse_reply as that string rather than as "once".
        // The fallback is for an old producer that sent no options at all.
        // Stored as JSON because a ListModel role holding a bare list is drawn
        // as the model item itself - measured: every button read
        // "QQmlDMAbstractItemModelData".
        row.optionsJson = JSON.stringify((options && options.length)
                ? options.map(o => String(o))
                : ["Allow this once", "Deny"]);
        model.append(row);
        scroll();
    }

    function closeApproval(turnId) {
        for (let i = model.count - 1; i >= 0; i--) {
            const row = model.get(i);
            if (row.kind === "approval" && row.turnId === turnId && !row.decided) {
                model.setProperty(i, "decided", true);
                model.setProperty(i, "decision", "no answer — closed");
                return true;
            }
        }
        return false;
    }

    function appendReply(chunk) {
        if (streamIndex < 0) {
            const row = blank("assistant");
            row.text = chunk;
            streamIndex = model.count;
            model.append(row);
        } else {
            model.setProperty(streamIndex, "text", (model.get(streamIndex).text || "") + chunk);
        }
        scroll();
    }

    function endReply() {
        streamIndex = -1;
        // The last chunk can grow its row after the view has already moved.
        scroll();
    }

    function decide(index, turnId, label) {
        model.setProperty(index, "decided", true);
        model.setProperty(index, "decision", label);
        panel.approve(turnId, label);
    }

    // The option an IpcHandler decision code means, for the row that is open.
    // A caller may pass the option label itself (that is what the Agent
    // contract takes); otherwise "deny"/"always" pick by meaning and anything
    // else is the first option.
    function optionFor(row, decision) {
        const options = JSON.parse(row.optionsJson || "[]");
        if (options.length === 0)
            return decision;
        // Exact label match first (e.g. "Allow for this session" == "Allow for this session")
        if (options.indexOf(decision) >= 0)
            return decision;
        // Pattern-based fallback for "deny" decision code
        if (decision === "deny") {
            for (let i = 0; i < options.length; i++) {
                if (/deny|no\b|cancel|stop/i.test(options[i]))
                    return options[i];
            }
            // No pattern match: return the last option as default
            return options[options.length - 1];
        }
        // Pattern-based fallback for "always" decision code
        if (decision === "always") {
            for (let i = 0; i < options.length; i++) {
                if (/session|always/i.test(options[i]))
                    return options[i];
            }
            // No pattern match: return the first option as default
            return options[0];
        }
        // No pattern matched: return the first option as default
        return options[0];
    }

    // The panel is scriptable (and a future "press A to allow" binding): the
    // newest approval that has not been answered yet.
    function approveLast(decision) {
        for (let i = model.count - 1; i >= 0; i--) {
            const row = model.get(i);
            if (row.kind === "approval" && !row.decided) {
                decide(i, row.turnId, optionFor(row, decision));
                return true;
            }
        }
        return false;
    }

    function submit() {
        const t = input.text.trim();
        if (t === "" || busy)
            return;
        addUser(t);
        input.text = "";
        ask(t);
    }

    visible: open
    screen: Ui.screen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "shani-chronoa"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    BackgroundEffect.blurRegion: blurEnabled ? panelRegion : null
    Region {
        id: panelRegion
        item: card
        radius: 22
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim

        MouseArea {
            anchors.fill: parent
            onClicked: panel.dismiss()
        }
    }

    Rectangle {
        id: card
        width: Math.min(880, parent.width - 140)
        height: Math.min(620, parent.height - 120)
        anchors.centerIn: parent
        radius: 22
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.alpha(Theme.text, 0.12)

        // NOTE: no decorative glow here — a flat translucent circle reads as a
        // hard-edged blob at 0.07 alpha, and a real radial gradient would need
        // Qt5Compat. The border and the wallpaper's own colour are enough.

        // slide up + fade in when the panel opens
        Behavior on opacity { NumberAnimation { duration: Theme.animEnter; easing.type: Easing.OutCubic } }
        transform: Translate {
            y: open ? 0 : 24
            Behavior on y { NumberAnimation { duration: Theme.animEnter; easing.type: Easing.OutCubic } }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            // ---- header -------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item {
                    width: 12
                    height: 12

                    Rectangle {
                        anchors.centerIn: parent
                        width: 9
                        height: 9
                        radius: 5
                        color: panel.stateColor()
                    }
                    Rectangle {
                        id: halo
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 6
                        color: "transparent"
                        border.width: 1.5
                        border.color: panel.stateColor()
                        opacity: 0
                    }
                }

                Text {
                    text: Tr.t("Chronoa")
                    color: panel.textColor
                    font.family: Theme.font
                    font.pixelSize: 16 * Theme.fontScale
                    font.weight: Font.DemiBold
                }

                Text {
                    text: panel.stateLabel()
                    color: panel.stateColor()
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                }

                Text {
                    visible: panel.detail !== ""
                    text: "· " + panel.detail
                    color: panel.dimColor
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                    elide: Text.ElideRight
                    Layout.maximumWidth: 280
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: modelChip.implicitWidth + 16
                    height: 22
                    radius: 11
                    color: Theme.alpha(Theme.text, 0.05)
                    border.width: 1
                    border.color: Theme.alpha(Theme.text, 0.08)

                    Text {
                        id: modelChip
                        anchors.centerIn: parent
                        text: panel.modelLabel
                        color: panel.dimColor
                        font.family: Theme.mono
                        font.pixelSize: 10 * Theme.fontScale
                    }
                }

                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
                    color: closeArea.containsMouse ? Theme.alpha(Theme.text, 0.10) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: panel.dimColor
                        font.pixelSize: 16 * Theme.fontScale
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.dismiss()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.alpha(Theme.text, 0.07)
            }

            // ---- empty state ----------------------------------------------
            Column {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: panel.model.count === 0
                spacing: 16
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter

                // a soft orb like the Island's companion, so the empty state
                // feels like the same companion waiting, not an empty box
                Rectangle {
                    width: 64; height: 64
                    radius: 32
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.alpha(Theme.accent, 0.18) }
                        GradientStop { position: 1.0; color: Theme.alpha(Theme.accent, 0.05) }
                    }
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Theme.alpha(Theme.accent, 0.30)
                        shadowBlur: 16
                        shadowVerticalOffset: 0
                        shadowHorizontalOffset: 0
                        autoPaddingEnabled: true
                    }
                    SequentialAnimation {
                        loops: Animation.Infinite
                        NumberAnimation { target: parent; property: "opacity"; from: 0.55; to: 0.95; duration: 2200; easing.type: Easing.InOutSine }
                        NumberAnimation { target: parent; property: "opacity"; from: 0.95; to: 0.55; duration: 2200; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    text: Tr.t("Ask for a job.")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17 * Theme.fontScale
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    text: Tr.t("Chronoa runs it on this machine,\nand asks before anything changes.")
                    color: Theme.alpha(Theme.dim, 0.7)
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                    lineHeight: 1.5
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // A plain Column, not a ListView: the conversation is short and
            // delegate recycling left the newest row laid out (it had a height
            // and a position) but unpainted until another row arrived.
            Flickable {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: panel.model.count > 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: rows.implicitHeight

                onContentHeightChanged: scroll()

                Column {
                    id: rows
                    width: list.width
                    spacing: 6

                    Repeater {
                        model: panel.model

                        delegate: Item {
                            id: row
                            required property int index
                            required property string kind
                            required property string text
                            required property string title
                            required property string detail
                            required property string turnId
                            required property bool decided
                            required property string decision
                            required property string optionsJson

                            readonly property var optionLabels: JSON.parse(optionsJson || "[]")

                            width: rows.width
                            height: {
                                if (kind === "user")
                                return userBubble.height + 14;
                                if (kind === "assistant")
                                return asstText.height + 14;
                                if (kind === "tool")
                                return 32;
                                if (kind === "approval")
                                return approvalCard.height + 14;
                                return 22;
                            }

                            // user: right-aligned bubble with accent tint
                            Rectangle {
                                id: userBubble
                                visible: row.kind === "user"
                                anchors.right: parent.right
                                anchors.top: parent.top
                                width: Math.min(row.width * 0.72, userText.implicitWidth + 28)
                                height: userText.implicitHeight + 18
                                radius: 12
                                color: Theme.alpha(Theme.accent, 0.16)
                                border.width: 1
                                border.color: Theme.alpha(Theme.accent, 0.28)
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: Theme.shadowSoft
                                    shadowBlur: 4
                                    shadowVerticalOffset: 2
                                    shadowHorizontalOffset: 0
                                    autoPaddingEnabled: true
                                }

                                Text {
                                    id: userText
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    text: row.text
                                    color: panel.textColor
                                    font.family: Theme.font
                                    font.pixelSize: 13 * Theme.fontScale
                                    wrapMode: Text.WordWrap
                                }
                            }

                            // assistant: full-width prose with a subtle accent leader
                            Rectangle {
                                visible: row.kind === "assistant"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                color: "transparent"
                                Rectangle {
                                    width: 3
                                    radius: 2
                                    color: panel.accent
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: -3
                                    height: Math.min(24, asstText.implicitHeight)
                                    Behavior on height { NumberAnimation { duration: Theme.anim } }
                                }
                                Text {
                                    id: asstText
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: 8
                                    text: row.text
                                    color: panel.textColor
                                    font.family: Theme.font
                                    font.pixelSize: 13 * Theme.fontScale
                                    lineHeight: 1.35
                                    wrapMode: Text.WordWrap
                                }
                            }

                            // tool activity: a pill, not a message
                            Rectangle {
                                visible: row.kind === "tool"
                                anchors.left: parent.left
                                anchors.top: parent.top
                                width: toolRow.implicitWidth + 22
                                height: 28
                                radius: 8
                                color: Theme.alpha(Theme.amber, 0.10)
                                border.width: 1
                                border.color: Theme.alpha(Theme.amber, 0.25)

                                Row {
                                    id: toolRow
                                    anchors.centerIn: parent
                                    spacing: 7

                                    Rectangle {
                                        width: 5
                                        height: 5
                                        radius: 3
                                        color: panel.amber
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: row.text
                                        color: Theme.amber
                                        font.family: Theme.mono
                                        font.pixelSize: 10 * Theme.fontScale
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            // approval: inline, not a notification you might miss
                            Glass {
                                id: approvalCard
                                visible: row.kind === "approval"
                                strong: true
                                elevation: "card"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                width: parent.width
                                height: approvalCol.implicitHeight + 24
                                radius: 12
                                color: Theme.alpha(Theme.amber, 0.06)
                                border.width: 1
                                border.color: Theme.alpha(Theme.amber, 0.25)
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: Theme.shadowCard
                                    shadowBlur: 8
                                    shadowVerticalOffset: 2
                                    shadowHorizontalOffset: 0
                                    autoPaddingEnabled: true
                                }

                                Rectangle {
                                    width: 3
                                    radius: 2
                                    color: panel.amber
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: -3
                                    height: Math.min(32, approvalCol.implicitHeight)
                                    Behavior on height { NumberAnimation { duration: Theme.anim } }
                                }

                                Column {
                                    id: approvalCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 12
                                    anchors.leftMargin: 20
                                    spacing: 6

                                    Text {
                                        text: row.title
                                        color: panel.textColor
                                        font.family: Theme.font
                                        font.pixelSize: 13 * Theme.fontScale
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        width: parent.width
                                        text: row.detail
                                        color: panel.dimColor
                                        font.family: Theme.font
                                        font.pixelSize: 11 * Theme.fontScale
                                        wrapMode: Text.WordWrap
                                    }

                                    Flow {
                                        width: parent.width
                                        spacing: 8
                                        visible: !row.decided

                                        Repeater {
                                            model: row.optionLabels

                                            Rectangle {
                                                required property string modelData
                                                required property int index
                                                width: Math.min(btnLabel.implicitWidth, 170) + 22
                                                height: 28
                                                radius: 8
                                                color: index === 0
                                                ? Theme.alpha(Theme.accent, 0.22)
                                                : Theme.alpha(Theme.text, 0.06)
                                                border.width: 1
                                                border.color: index === 0
                                                ? Theme.alpha(Theme.accent, 0.55)
                                                : Theme.alpha(Theme.text, 0.10)

                                                Text {
                                                    id: btnLabel
                                                    anchors.centerIn: parent
                                                    width: Math.min(implicitWidth, 170)
                                                    text: modelData
                                                    elide: Text.ElideRight
                                                    color: panel.textColor
                                                    font.family: Theme.font
                                                    font.pixelSize: 11 * Theme.fontScale
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: panel.decide(row.index, row.turnId, modelData)
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        visible: row.decided
                                        // A closed card is not an answer; do not put a
                                        // tick beside words the person never chose.
                                        text: (row.decision.indexOf("no answer") === 0 ? "· " : "✓ ")
                                        + row.decision
                                        color: panel.accent
                                        font.family: Theme.font
                                        font.pixelSize: 11 * Theme.fontScale
                                    }
                                }
                            }

                            // system line
                            Text {
                                visible: row.kind === "system"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                text: row.text
                                color: panel.dimColor
                                font.family: Theme.mono
                                font.pixelSize: 10 * Theme.fontScale
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }

            // ---- quick skills -------------------------------------------
            Row {
                Layout.fillWidth: true
                spacing: 8
                visible: !panel.busy

                Repeater {
                    model: [
                        { label: Tr.t("Battery"), prompt: "What's eating my battery?" },
                        { label: Tr.t("Summarise screen"), prompt: "Summarise what's on my screen." },
                        { label: Tr.t("Tidy desktop"), prompt: "Tidy my desktop." },
                        { label: Tr.t("Dictate"), prompt: "", action: "dictate" }
                    ]

                    Rectangle {
                        required property var modelData
                        width: chipLabel.implicitWidth + 20
                        height: 26
                        radius: 13
                        color: chipArea.containsMouse ? Theme.alpha(Theme.accent, 0.16) : Theme.alpha(Theme.text, 0.04)
                        border.width: 1
                        border.color: Theme.alpha(Theme.text, 0.08)

                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            color: panel.dimColor
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                        }
                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.action) {
                                    panel.action(modelData.action);
                                } else {
                                    panel.addUser(modelData.prompt);
                                    panel.ask(modelData.prompt);
                                }
                            }
                        }
                    }
                }
            }

            // ---- composer ------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 14
                color: Theme.alpha(Theme.text, 0.05)
                border.width: 1
                border.color: input.activeFocus ? Theme.alpha(Theme.accent, 0.55) : Theme.alpha(Theme.text, 0.10)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 8
                    spacing: 8

                    TextInput {
                        id: input
                        Accessible.role: Accessible.EditableText
                        Accessible.name: Tr.t("Ask Chronoa")
                        Layout.fillWidth: true
                        color: panel.textColor
                        font.family: Theme.font
                        font.pixelSize: 14 * Theme.fontScale
                        selectionColor: Theme.alpha(Theme.accent, 0.35)
                        clip: true

                        Keys.onEscapePressed: panel.dismiss()
                        Keys.onReturnPressed: panel.submit()
                        Keys.onEnterPressed: panel.submit()
                    }

                    Text {
                        visible: input.text === ""
                        text: Tr.t("Ask Chronoa, or describe a task…")
                        color: Theme.alpha(Theme.dim, 0.75)
                        font.family: Theme.font
                        font.pixelSize: 14 * Theme.fontScale
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 9
                        color: micArea.containsMouse ? Theme.alpha(Theme.accent, 0.18) : Theme.alpha(Theme.text, 0.05)
                        visible: panel.state !== "listening"

                        Text {
                            anchors.centerIn: parent
                            text: Tr.t("mic")
                            color: panel.dimColor
                            font.family: Theme.mono
                            font.pixelSize: 9 * Theme.fontScale
                        }
                        MouseArea {
                            id: micArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.action("toggle-listening")
                        }
                    }

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 9
                        visible: panel.state === "listening"
                        color: panel.accent

                        Text {
                            anchors.centerIn: parent
                            text: "■"
                            color: Theme.accentInk
                            font.pixelSize: 12 * Theme.fontScale
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.action("stop-speaking")
                        }
                    }

                    Rectangle {
                        width: 34
                        height: 32
                        radius: 9
                        color: input.text.trim() === "" ? Theme.alpha(Theme.text, 0.04) : Theme.alpha(Theme.accent, 0.30)
                        border.width: 1
                        border.color: input.text.trim() === "" ? Theme.alpha(Theme.text, 0.06) : Theme.alpha(Theme.accent, 0.55)

                        Text {
                            anchors.centerIn: parent
                            text: "↵"
                            color: input.text.trim() === "" ? panel.dimColor : panel.textColor
                            font.pixelSize: 14 * Theme.fontScale
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.submit()
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: Tr.t("↵ send    esc close    ·    tools ask before they change anything")
                color: Theme.alpha(Theme.dim, 0.65)
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
        }
    }

    // pulsing halo while Chronoa is working
    SequentialAnimation {
        running: panel.state === "listening" || panel.state === "thinking" || panel.state === "speaking"
        loops: Animation.Infinite
        NumberAnimation { target: halo; property: "opacity"; from: 0.0; to: 0.9; duration: 520 }
        NumberAnimation { target: halo; property: "opacity"; from: 0.9; to: 0.0; duration: 520 }
    }

    onOpenChanged: {
        if (open) {
            Qt.callLater(function () { input.forceActiveFocus(); });
        } else {
            input.focus = false;
        }
    }
}
