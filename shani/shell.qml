// ShaniOS shell spike — niri + Quickshell 0.3.2
// Bar + launcher + notification popup, with blur via ext-background-effect-v1.
// Set SHANI_BLUR=0 to disable the protocol blur request (for the layer-rule / no-blur runs).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.WindowManager
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    property bool launcherOpen: false
    property bool notifVisible: false
    property string loadAvg: "0.00"
    property int memPct: 0
    property int selIndex: 0

    // ---- Chronoa ------------------------------------------------------
    property bool chronoOpen: false
    property bool chronoBusy: false
    property bool chronoVisible: true
    property string chronoState: "offline"
    property string chronoDetail: ""
    property string cueText: ""
    property bool cueHold: false

    readonly property bool blurEnabled: Quickshell.env("SHANI_BLUR") !== "0"
    readonly property color accent: "#7fd1c1"
    readonly property color textColor: "#e8eef5"
    readonly property color dimColor: "#8fa1b6"

    // ---- system stats -------------------------------------------------
    Process {
        id: statsProc
        command: ["/work/shani/stats.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split("|");
                if (p.length === 2) {
                    root.loadAvg = p[0];
                    root.memPct = parseInt(p[1]);
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: statsProc.running = true
    }

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    // ---- Chronoa bridge socket ---------------------------------------
    ListModel {
        id: chronoModel
    }

    Socket {
        id: chronoSock
        path: "/run/user/0/shani-chronoa.sock"
        connected: true
        parser: SplitParser {
            onRead: line => root.onChronoaLine(line)
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: if (!chronoSock.connected) chronoSock.connected = true
    }

    Timer {
        id: cueTimer
        interval: 3200
        onTriggered: root.cueText = ""
    }

    // ---- notifications ------------------------------------------------
    NotificationServer {
        id: notifServer
        bodySupported: true
        imageSupported: true
        actionsSupported: true
        keepOnReload: true
    }

    readonly property var notifs: notifServer.trackedNotifications.values
    readonly property int notifCount: notifs.length
    readonly property var latestNotif: notifCount > 0 ? notifs[notifCount - 1] : null

    onNotifCountChanged: {
        if (notifCount > 0) {
            notifVisible = true;
            notifTimer.restart();
        } else {
            notifVisible = false;
        }
    }

    Timer {
        id: notifTimer
        interval: 7000
        onTriggered: root.notifVisible = false
    }

    // ---- launcher data ------------------------------------------------
    readonly property var filteredApps: {
        const q = search.text.trim().toLowerCase();
        const all = DesktopEntries.applications.values;
        const list = q === "" ? all : all.filter(a => (a.name || "").toLowerCase().includes(q));
        return list.slice(0, 8);
    }

    function launchSelected() {
        const list = filteredApps;
        if (list.length === 0)
            return;
        const i = Math.max(0, Math.min(selIndex, list.length - 1));
        list[i].execute();
        launcherOpen = false;
    }

    // ---- Chronoa integration -----------------------------------------
    function chronoColor() {
        if (chronoState === "listening" || chronoState === "idle")
            return accent;
        if (chronoState === "speaking")
            return "#7aa2f7";
        if (chronoState === "waiting")
            return "#f7768e";
        if (chronoState === "offline")
            return "#6b7280";
        return "#e0af68";
    }

    function chronoLabel() {
        if (chronoState === "offline")
            return "offline";
        if (chronoState === "thinking")
            return "thinking";
        if (chronoState === "listening")
            return "listening";
        if (chronoState === "speaking")
            return "speaking";
        if (chronoState === "waiting")
            return "waiting";
        return "ready";
    }

    function chronoSend(obj) {
        if (!chronoSock.connected)
            return false;
        chronoSock.write(JSON.stringify(obj) + "\n");
        chronoSock.flush();
        return true;
    }

    function deliverAsk(text) {
        chronoOpen = true;
        chronoBusy = true;
        if (!chronoSend({ op: "ask", text: text })) {
            chronoBusy = false;
            chronoa.addSystem("Chronoa bridge is not connected — start chronoa-bridge.py.");
        }
    }

    function askChronoa(text) {
        chronoa.addUser(text);
        deliverAsk(text);
    }

    function handleTurn(e) {
        if (e.event === "thinking") {
            chronoState = "thinking";
            chronoBusy = true;
        } else if (e.event === "tool") {
            chronoa.addTool(e.text);
            chronoState = "thinking";
            chronoBusy = true;
        } else if (e.event === "reply") {
            chronoa.appendReply(e.text);
            chronoState = "speaking";
        } else if (e.event === "approval") {
            chronoa.addApproval(e.id, e.text, e.detail);
            chronoState = "waiting";
        } else if (e.event === "done") {
            chronoa.endReply();
            chronoBusy = false;
            chronoState = "idle";
        }
    }

    function onChronoaLine(line) {
        let e;
        try {
            e = JSON.parse(line);
        } catch (err) {
            return;
        }
        if (e.type === "state") {
            chronoState = e.state || "idle";
            chronoDetail = e.detail || "";
        } else if (e.type === "hello") {
            chronoState = e.state || "idle";
            chronoDetail = e.detail || "";
            chronoVisible = e.visible !== false;
        } else if (e.type === "cue") {
            cueText = e.text;
            cueHold = !!e.hold;
            cueTimer.interval = cueHold ? 8000 : 3200;
            cueTimer.restart();
        } else if (e.type === "mascot") {
            chronoVisible = !!e.visible;
        } else if (e.type === "notice") {
            if (chronoOpen)
                chronoa.addSystem(e.text);
        } else if (e.type === "error") {
            chronoBusy = false;
            chronoState = "idle";
            chronoa.addSystem(e.text);
            if (!chronoOpen) {
                chronoOpen = true;
            }
        } else if (e.type === "event") {
            handleTurn(e);
        }
    }

    IpcHandler {
        target: "shani"

        function toggleLauncher() {
            root.launcherOpen = !root.launcherOpen;
        }
        function openLauncher() {
            root.launcherOpen = true;
        }
        function closeLauncher() {
            root.launcherOpen = false;
        }
        function openChronoa() {
            root.chronoOpen = true;
        }
        function closeChronoa() {
            root.chronoOpen = false;
        }
        function toggleChronoa() {
            root.chronoOpen = !root.chronoOpen;
        }
        function ask(text: string) {
            root.askChronoa(text);
        }
        function approve(decision: string) {
            chronoa.approveLast(decision);
        }
        function action(name: string) {
            root.chronoSend({ op: "action", name: name });
        }
    }

    // ---- bar ----------------------------------------------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            margins {
                top: 10
                left: 12
                right: 12
            }
            implicitHeight: 44
            color: "transparent"
            exclusiveZone: 54
            exclusionMode: ExclusionMode.Normal

            WlrLayershell.namespace: "shani-panel"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            BackgroundEffect.blurRegion: root.blurEnabled ? barRegion : null
            Region {
                id: barRegion
                item: barGlass
                radius: 16
            }

            Rectangle {
                id: barGlass
                anchors.fill: parent
                radius: 16
                color: Qt.rgba(0.05, 0.07, 0.10, 0.55)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: root.accent
                    }

                    Text {
                        text: "shani"
                        color: root.textColor
                        font.family: "Noto Sans"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.6
                    }

                    Rectangle {
                        width: 1
                        height: 18
                        color: Qt.rgba(1, 1, 1, 0.12)
                    }

                    Repeater {
                        model: WindowManager.windowsets

                        Rectangle {
                            id: pill
                            required property var modelData
                            visible: modelData.shouldDisplay
                            implicitWidth: visible ? 26 : 0
                            height: 24
                            radius: 8
                            color: modelData.active ? Qt.rgba(0.50, 0.82, 0.76, 0.20) : Qt.rgba(1, 1, 1, 0.04)
                            border.width: 1
                            border.color: modelData.active ? Qt.rgba(0.50, 0.82, 0.76, 0.55) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: modelData.name
                                color: modelData.active ? root.accent : root.dimColor
                                font.family: "Noto Sans"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.activate()
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Row {
                        spacing: 8

                        Text {
                            text: Qt.formatDateTime(sysClock.date, "ddd d MMM")
                            color: root.dimColor
                            font.family: "Noto Sans"
                            font.pixelSize: 12
                        }
                        Text {
                            text: "·"
                            color: root.dimColor
                            font.pixelSize: 12
                        }
                        Text {
                            text: Qt.formatDateTime(sysClock.date, "HH:mm")
                            color: root.textColor
                            font.family: "Noto Sans"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "load " + root.loadAvg
                        color: root.dimColor
                        font.family: "DejaVu Sans Mono"
                        font.pixelSize: 11
                    }
                    Text {
                        text: "mem " + root.memPct + "%"
                        color: root.dimColor
                        font.family: "DejaVu Sans Mono"
                        font.pixelSize: 11
                    }

                    Rectangle {
                        width: 1
                        height: 18
                        color: Qt.rgba(1, 1, 1, 0.12)
                    }

                    Rectangle {
                        width: chronoPillRow.implicitWidth + 18
                        height: 28
                        radius: 9
                        color: chronoPillArea.containsMouse
                               ? Qt.rgba(0.50, 0.82, 0.76, 0.18)
                               : Qt.rgba(1, 1, 1, 0.04)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.07)

                        Row {
                            id: chronoPillRow
                            anchors.centerIn: parent
                            spacing: 7

                            Rectangle {
                                width: 7
                                height: 7
                                radius: 4
                                color: root.chronoColor()
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Chronoa"
                                color: root.textColor
                                font.family: "Noto Sans"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "· " + root.chronoLabel()
                                color: root.chronoColor()
                                font.family: "Noto Sans"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: chronoPillArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.launcherOpen = false;
                                root.chronoOpen = !root.chronoOpen;
                            }
                        }
                    }

                    Rectangle {
                        width: 72
                        height: 28
                        radius: 9
                        color: searchBtn.containsMouse ? Qt.rgba(0.50, 0.82, 0.76, 0.22) : Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.08)

                        Text {
                            anchors.centerIn: parent
                            text: "Ask  ⌘K"
                            color: root.textColor
                            font.family: "Noto Sans"
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: searchBtn
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.launcherOpen = false;
                                root.chronoOpen = true;
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- launcher -----------------------------------------------------
    PanelWindow {
        id: launcherWin
        visible: root.launcherOpen
        screen: Quickshell.screens[0]

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "shani-launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.launcherOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        BackgroundEffect.blurRegion: (root.launcherOpen && root.blurEnabled) ? launcherRegion : null
        Region {
            id: launcherRegion
            item: launcherCard
            radius: 22
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.35)

            MouseArea {
                anchors.fill: parent
                onClicked: root.launcherOpen = false
            }
        }

        Rectangle {
            id: launcherCard
            width: Math.min(720, parent.width - 160)
            height: 464
            anchors.centerIn: parent
            radius: 22
            color: Qt.rgba(0.05, 0.07, 0.10, 0.72)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "⌕"
                        color: root.accent
                        font.pixelSize: 20
                        font.family: "DejaVu Sans"
                    }

                    TextInput {
                        id: search
                        Layout.fillWidth: true
                        color: root.textColor
                        font.family: "Noto Sans"
                        font.pixelSize: 18
                        selectionColor: Qt.rgba(0.5, 0.82, 0.76, 0.35)
                        onTextChanged: root.selIndex = 0

                        Keys.onEscapePressed: root.launcherOpen = false
                        Keys.onDownPressed: root.selIndex = Math.min(root.selIndex + 1, root.filteredApps.length - 1)
                        Keys.onUpPressed: root.selIndex = Math.max(root.selIndex - 1, 0)
                        Keys.onReturnPressed: root.launchSelected()
                        Keys.onEnterPressed: root.launchSelected()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                ListView {
                    id: resultsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.filteredApps

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        width: ListView.view.width
                        height: 44
                        radius: 10
                        color: index === root.selIndex ? Qt.rgba(0.50, 0.82, 0.76, 0.16) : "transparent"

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            text: modelData.name
                            color: root.textColor
                            font.family: "Noto Sans"
                            font.pixelSize: 14
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            width: Math.min(320, parent.width / 2)
                            horizontalAlignment: Text.AlignRight
                            text: modelData.comment || ""
                            elide: Text.ElideRight
                            color: root.dimColor
                            font.family: "Noto Sans"
                            font.pixelSize: 11
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: root.selIndex = index
                            onClicked: {
                                modelData.execute();
                                root.launcherOpen = false;
                            }
                        }
                    }
                }

                Text {
                    text: "↑↓ navigate    ↵ launch    esc close"
                    color: root.dimColor
                    font.family: "Noto Sans"
                    font.pixelSize: 11
                }
            }
        }

        onVisibleChanged: {
            if (visible) {
                search.text = "";
                search.forceActiveFocus();
            }
        }
    }

    // ---- notification popup -------------------------------------------
    PanelWindow {
        id: notifWin
        visible: root.notifVisible && root.notifCount > 0
        screen: Quickshell.screens[0]

        anchors {
            top: true
            right: true
        }
        margins {
            top: 68
            right: 14
        }
        implicitWidth: 360
        implicitHeight: notifCard.height
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "shani-notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        BackgroundEffect.blurRegion: (root.notifVisible && root.blurEnabled) ? notifRegion : null
        Region {
            id: notifRegion
            item: notifCard
            radius: 16
        }

        Rectangle {
            id: notifCard
            width: parent.width
            height: notifCol.implicitHeight + 28
            radius: 16
            color: Qt.rgba(0.05, 0.07, 0.10, 0.78)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)

            Column {
                id: notifCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 14
                }
                spacing: 5

                Row {
                    spacing: 8

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: root.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.latestNotif ? (root.latestNotif.appName || "Notification") : ""
                        color: root.dimColor
                        font.family: "Noto Sans"
                        font.pixelSize: 11
                    }
                }

                Text {
                    width: parent.width
                    text: root.latestNotif ? root.latestNotif.summary : ""
                    color: root.textColor
                    font.family: "Noto Sans"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    width: parent.width
                    text: root.latestNotif ? root.latestNotif.body : ""
                    color: root.dimColor
                    font.family: "Noto Sans"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ---- Chronoa tool-call cue ----------------------------------------
    PanelWindow {
        id: cueWin
        visible: root.cueText !== "" && root.chronoVisible
        screen: Quickshell.screens[0]

        anchors {
            top: true
            left: true
            right: true
        }
        margins {
            top: 64
        }
        implicitHeight: 34
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "shani-chronoa-cue"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        BackgroundEffect.blurRegion: root.blurEnabled ? cueRegion : null
        Region {
            id: cueRegion
            item: cuePill
            radius: 10
        }

        Rectangle {
            id: cuePill
            width: Math.min(cueRow.implicitWidth + 24, parent.width - 220)
            height: 30
            anchors.horizontalCenter: parent.horizontalCenter
            radius: 10
            color: Qt.rgba(0.05, 0.07, 0.10, 0.82)
            border.width: 1
            border.color: Qt.rgba(0.88, 0.69, 0.41, 0.28)

            Row {
                id: cueRow
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: "#e0af68"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.cueText
                    color: "#e8eef5"
                    font.family: "DejaVu Sans Mono"
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ---- Chronoa conversation -----------------------------------------
    ChronoaPanel {
        id: chronoa
        model: chronoModel
        open: root.chronoOpen
        busy: root.chronoBusy
        state: root.chronoState
        detail: root.chronoDetail

        onAsk: text => root.deliverAsk(text)
        onAction: name => root.chronoSend({ op: "action", name: name })
        onApprove: (id, decision) => root.chronoSend({ op: "approve", id: id, decision: decision })
        onDismiss: root.chronoOpen = false
    }
}
