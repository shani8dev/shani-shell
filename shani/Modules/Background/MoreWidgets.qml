// More desktop widgets, the same kind of card as DesktopWidgets.qml (glass on
// the layer above the wallpaper, under every window; drag to move - the place
// is remembered; a click opens what it shows):
//   agenda   - the next events, with their times; opens the calendar
//   battery  - the charge, charging or time left, the power mode (with a battery)
//   note     - the quick note, on the desktop; opens it to edit
//   clocks   - the world clocks chosen for the calendar
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Services

Variants {
    model: Quickshell.screens
    Scope {
        id: scr
        required property var modelData
        readonly property real sw: modelData ? modelData.width : 1920
        readonly property real sh: modelData ? modelData.height : 1080
        function on(id) { return Settings.loaded && Array.from(Settings.data.desktopWidgets).indexOf(id) >= 0; }
        function place(card, id, dx, dy) {
            const want = (Settings.data.deskPos || {})[id] || { x: dx, y: dy };
            card.x = Math.min(Math.max(12, want.x), Math.max(12, sw - card.width - 12));
            card.y = Math.min(Math.max(Theme.barHeight + 12, want.y), Math.max(Theme.barHeight + 12, sh - card.height - 96));
        }
        function save(card, id) {
            const keep = JSON.parse(JSON.stringify(Settings.data.deskPos || {}));
            keep[id] = { x: Math.round(card.x), y: Math.round(card.y) };
            Settings.data.deskPos = keep;
        }

        // one card: its surface (the whole screen, input only on the card), the
        // glass, the drag, the click
        component Card: PanelWindow {
            id: cw
            required property string key
            property real defaultX: 24
            property real defaultY: 200
            property real cardWidth: 220
            property real cardHeight: 120
            property string name: ""
            signal open()
            default property alias content: glass.data
            screen: scr.modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "shani-desk-" + key
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            visible: scr.on(key) && !Lock.locked && !Niri.overviewOpen && extraShow
            property bool extraShow: true
            mask: Region { item: glass }
            Glass {
                id: glass
                width: cw.cardWidth
                height: cw.cardHeight
                radius: Theme.radiusLarge
                elevation: "soft"
                Component.onCompleted: scr.place(glass, cw.key, cw.defaultX, cw.defaultY)
                Accessible.role: Accessible.Button
                Accessible.name: cw.name
                Accessible.onPressAction: cw.open()
                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    drag.target: glass
                    drag.threshold: 8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cw.open()
                    onReleased: if (dragArea.drag.active) scr.save(glass, cw.key)
                }
            }
        }
        component Label: Text {
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 12 * Theme.fontScale
            elide: Text.ElideRight
        }

        // ---- agenda
        Card {
            key: "agenda"
            name: Tr.t("Agenda, opens the calendar")
            defaultX: 24; defaultY: 230
            cardWidth: 260
            cardHeight: 48 + Math.max(1, Math.min(4, Agenda.upcoming.length)) * 34
            onOpen: Agenda.openCalendar()
            Column {
                id: agendaCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6
                Label { text: Tr.t("Coming up"); color: Theme.dim; font.pixelSize: 11 * Theme.fontScale; font.weight: Font.DemiBold }
                Label { visible: Agenda.upcoming.length === 0; text: Agenda.available ? Tr.t("Nothing in the calendar") : Tr.t("Add a calendar in Settings > Your account"); color: Theme.faint }
                Repeater {
                    model: Agenda.upcoming.slice(0, 4)
                    Column {
                        required property var modelData
                        width: agendaCol.width
                        Label { width: agendaCol.width; text: modelData.summary; font.weight: Font.Medium }
                        Label { width: agendaCol.width; text: Agenda.when(modelData) + (modelData.location ? " · " + modelData.location : ""); color: Theme.dim; font.pixelSize: 10.5 * Theme.fontScale }
                    }
                }
            }
        }

        // ---- battery
        Card {
            key: "battery"
            name: Tr.t("Battery %1%", Math.round(Power.percent * 100))
            extraShow: Power.hasBattery
            defaultX: scr.sw - 220; defaultY: 300
            cardWidth: 196; cardHeight: 92
            onOpen: Ui.openSettings("power")
            Row {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12
                Shape {
                    width: 60; height: 60
                    anchors.verticalCenter: parent.verticalCenter
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath { strokeColor: Theme.alpha(Theme.text, 0.12); strokeWidth: 6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: 30; centerY: 30; radiusX: 26; radiusY: 26; startAngle: -90; sweepAngle: 360 } }
                    ShapePath { strokeColor: Power.lowAndDischarging ? Theme.amber : Theme.accent; strokeWidth: 6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: 30; centerY: 30; radiusX: 26; radiusY: 26; startAngle: -90; sweepAngle: 360 * Power.percent } }
                    Label { anchors.centerIn: parent; text: Math.round(Power.percent * 100) + "%"; font.weight: Font.DemiBold }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Label { text: Power.charging ? Tr.t("Charging") : Power.full ? Tr.t("Full") : Tr.t("On battery"); font.weight: Font.Medium }
                    Label { text: Power.timeLeft; color: Theme.dim; font.pixelSize: 10.5 * Theme.fontScale; visible: text !== "" }
                    Label { text: Power.profileName; color: Theme.faint; font.pixelSize: 10.5 * Theme.fontScale }
                }
            }
        }

        // ---- the quick note
        Card {
            key: "note"
            name: Tr.t("Note, opens it to edit")
            defaultX: 300; defaultY: 64
            cardWidth: 240
            cardHeight: Math.min(220, Math.max(90, noteText.implicitHeight + 46))
            onOpen: Ui.toggleControlCenter()
            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6
                Label { text: Tr.t("Note"); color: Theme.dim; font.pixelSize: 11 * Theme.fontScale; font.weight: Font.DemiBold }
                Text {
                    id: noteText
                    width: parent.width
                    text: QuickNotes.text.trim() || Tr.t("Nothing yet - click to write one")
                    color: QuickNotes.text.trim() ? Theme.text : Theme.faint
                    wrapMode: Text.Wrap
                    maximumLineCount: 8
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                }
            }
        }

        // ---- world clocks
        Card {
            key: "clocks"
            name: Tr.t("World clocks")
            defaultX: scr.sw - 260; defaultY: 420
            cardWidth: 236
            cardHeight: 44 + Math.max(1, WorldClock.clocks.length) * 26
            onOpen: Ui.toggleControlCenter()
            Column {
                id: clocksCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 4
                Label { text: Tr.t("World clocks"); color: Theme.dim; font.pixelSize: 11 * Theme.fontScale; font.weight: Font.DemiBold }
                Label { visible: WorldClock.clocks.length === 0; text: Tr.t("Pick cities under the calendar"); color: Theme.faint }
                Repeater {
                    model: WorldClock.clocks
                    Row {
                        required property var modelData
                        width: clocksCol.width
                        Label { width: clocksCol.width - 70; text: modelData.city }
                        Label { width: 70; horizontalAlignment: Text.AlignRight; text: modelData.time; font.features: { "tnum": 1 } }
                    }
                }
            }
        }
    }
}
