// Desktop widgets (Noctalia's idea, shani's look): glass cards that float on
// the wallpaper — a clock with the next event, what is playing, the weather,
// the system monitor. They live on the layer-shell's Bottom layer, so open
// windows cover them the way windows cover the desktop. Drag to move (the
// place is remembered), click to open the thing they talk about; toggled in
// Settings > Personalisation > "On the desktop".
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick
import qs.Common
import qs.Services

Variants {
    model: Quickshell.screens
    Scope {
        id: scr
        required property var modelData

        // positions: remembered, or the sensible default, then clamped so a card
        // stays on the screen, clear of the bar above and the dock below
        function loadPos(id, w, h) {
            const sw = scr.modelData ? scr.modelData.width : 1920;
            const sh = scr.modelData ? scr.modelData.height : 1080;
            const defaults = {
                "clock": { x: 24, y: 64 },
                "weather": { x: Math.max(12, sw - w - 24), y: 64 },
                "media": { x: 24, y: Math.max(12, sh - h - 104) },
                "stats": { x: Math.max(12, sw - w - 24), y: Math.max(12, sh - h - 104) }
            };
            return scr.clampPos(id, Settings.data.deskPos[id] || defaults[id], w, h, sw, sh);
        }
        function clampPos(id, want, w, h, sw, sh) {
            const x = Math.min(Math.max(12, want.x), Math.max(12, sw - w - 12));
            const y = Math.min(Math.max(Theme.barHeight + 12, want.y), Math.max(Theme.barHeight + 12, sh - h - 96));
            return { x: x, y: y };
        }
        function savePos(id, x, y) {
            const keep = JSON.parse(JSON.stringify(Settings.data.deskPos || {}));
            keep[id] = { x: Math.round(x), y: Math.round(y) };
            Settings.data.deskPos = keep;
        }
        // m:ss
        function fmt(s) { return Math.floor(s / 60) + ":" + String(Math.floor(s % 60)).padStart(2, "0"); }

        // a card over the desktop: glass, soft shadow, draggable, with the click
        // doing the sensible thing behind. `area` is its MouseArea, for telling a
        // drag from a plain click
        component DeskWindow: PanelWindow {
            screen: scr.modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: winNs
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            visible: Settings.loaded && !Lock.locked && !Niri.overviewOpen && show
            property string winNs: "shani-desk"
            property bool show: false
        }

        // ---- the clock ------------------------------------------------------

        DeskWindow {
            id: clockWin
            winNs: "shani-desk-clock"
            show: Array.from(Settings.data.desktopWidgets).indexOf("clock") >= 0
            mask: Region { item: clockCard }

            SystemClock { id: deskClock; precision: SystemClock.Minutes }

            Glass {
                id: clockCard
                x: 24; y: 64
                width: 216
                height: agendaText.visible ? 108 : 90
                radius: Theme.radiusLarge
                elevation: "soft"

                Component.onCompleted: {
                    const p = scr.loadPos("clock", width, height);
                    x = p.x; y = p.y;
                }
                onVisibleChanged: if (visible) {
                    const p = scr.loadPos("clock", width, height);
                    x = p.x; y = p.y;
                }

                MouseArea {
                    id: clockDrag
                    anchors.fill: parent
                    drag.target: clockCard
                    drag.threshold: 8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Ui.toggleControlCenter()
                    onReleased: if (clockDrag.drag.active) scr.savePos("clock", clockCard.x, clockCard.y)
                }

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                    spacing: 3
                    Text {
                        text: Settings.data.use24h ? Qt.formatTime(deskClock.date, "HH:mm") : Qt.formatTime(deskClock.date, "h:mm AP")
                        color: Theme.text
                        font.family: Theme.mono
                        font.pixelSize: 30
                        font.weight: Font.Medium
                    }
                    Text {
                        text: Qt.formatDate(deskClock.date, "dddd d MMMM")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                    }
                }
                Text {
                    id: agendaText
                    visible: Agenda.available && Agenda.upcoming.length > 0
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                    text: visible ? Agenda.when(Agenda.upcoming[0]) + "  ·  " + Agenda.upcoming[0].summary : ""
                    color: Theme.faint
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 10 * Theme.fontScale
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Clock, opens the control centre"
            }
        }

        // ---- what is playing ------------------------------------------------

        DeskWindow {
            id: mediaWin
            winNs: "shani-desk-media"
            show: Array.from(Settings.data.desktopWidgets).indexOf("media") >= 0
                && player !== null
            readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
            // the track's position, sampled while it plays (the thin bar moves)
            property real shown: player ? player.position : 0
            onPlayerChanged: shown = player ? player.position : 0
            Timer {
                interval: 900
                running: mediaWin.visible && mediaWin.player && mediaWin.player.isPlaying
                repeat: true
                onTriggered: mediaWin.shown = mediaWin.player.position
            }
            mask: Region { item: mediaCard }

            Glass {
                id: mediaCard
                x: 24; y: 900
                width: 252
                height: 80
                radius: Theme.radiusLarge
                elevation: "soft"

                Component.onCompleted: {
                    const p = scr.loadPos("media", width, height);
                    x = p.x; y = p.y;
                }
                onVisibleChanged: if (visible) {
                    const p = scr.loadPos("media", width, height);
                    x = p.x; y = p.y;
                }

                MouseArea {
                    id: mediaDrag
                    anchors.fill: parent
                    drag.target: mediaCard
                    drag.threshold: 8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Ui.toggleControlCenter()
                    onReleased: if (mediaDrag.drag.active) scr.savePos("media", mediaCard.x, mediaCard.y)
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    ClippingRectangle {
                        width: 56; height: 56
                        radius: 12
                        color: Theme.accentSoft
                        Image {
                            anchors.fill: parent
                            source: mediaWin.player ? mediaWin.player.trackArtUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Accessible.name: "Album art"
                    }
                    Column {
                        width: parent.width - 56 - 10 - 30 - 4
                        spacing: 3
                        Text {
                            width: parent.width
                            text: mediaWin.player ? (mediaWin.player.trackTitle || mediaWin.player.identity) : ""
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 12 * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: mediaWin.player ? mediaWin.player.trackArtist : ""
                            color: Theme.dim
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 10 * Theme.fontScale
                        }
                        // seek by clicking along the track (only players that allow it)
                        Rectangle {
                            width: parent.width
                            height: 12
                            color: "transparent"
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                height: 3
                                radius: 1.5
                                color: Theme.hover
                            }
                            Rectangle {
                                width: Math.max(3, parent.width * Math.min(1,
                                    mediaWin.player && mediaWin.player.length > 0 ? mediaWin.shown / mediaWin.player.length : 0))
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                height: 3
                                radius: 1.5
                                color: Theme.accent
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: mediaWin.player && mediaWin.player.canSeek && mediaWin.player.length > 0
                                cursorShape: Qt.PointingHandCursor
                                onClicked: me => mediaWin.player.position = mediaWin.player.length * (me.x / parent.width)
                            }
                        }
                        // elapsed and total, tucked over the seek bar's ends
                        Rectangle {
                            width: parent.width
                            height: 11
                            color: "transparent"
                            Text {
                                anchors.left: parent.left
                                text: scr.fmt(mediaWin.player ? mediaWin.shown : 0)
                                color: Theme.faint
                                font.family: Theme.mono
                                font.pixelSize: 9 * Theme.fontScale
                            }
                            Text {
                                anchors.right: parent.right
                                text: scr.fmt(mediaWin.player ? mediaWin.player.length : 0)
                                color: Theme.faint
                                font.family: Theme.mono
                                font.pixelSize: 9 * Theme.fontScale
                            }
                        }
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: mediaWin.player && mediaWin.player.isPlaying ? "media-playback-pause" : "media-playback-start"
                        size: 30
                        onClicked: mediaWin.player.togglePlaying()
                        Accessible.name: "Play or pause"
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Now playing, opens the control centre"
            }
        }

        // ---- weather ----------------------------------------------------------

        DeskWindow {
            id: weatherWin
            winNs: "shani-desk-weather"
            show: Array.from(Settings.data.desktopWidgets).indexOf("weather") >= 0
            mask: Region { item: weatherCard }

            Glass {
                id: weatherCard
                x: 1650; y: 64
                width: 196
                height: Weather.enabled ? 92 : 84
                radius: Theme.radiusLarge
                elevation: "soft"

                Component.onCompleted: {
                    const p = scr.loadPos("weather", width, height);
                    x = p.x; y = p.y;
                }
                onVisibleChanged: if (visible) {
                    const p = scr.loadPos("weather", width, height);
                    x = p.x; y = p.y;
                }

                MouseArea {
                    id: weatherDrag
                    anchors.fill: parent
                    drag.target: weatherCard
                    drag.threshold: 8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Ui.openSettings("personal")
                    onReleased: if (weatherDrag.drag.active) scr.savePos("weather", weatherCard.x, weatherCard.y)
                }

                Text {
                    visible: !Weather.enabled
                    anchors.centerIn: parent
                    text: Tr.t("Weather — set a city")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Row {
                    visible: Weather.enabled
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: Weather.icon
                        size: 30
                        color: Theme.accent
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.parent.width - 28 - 30 - 12
                        spacing: 2
                        Text {
                            text: isNaN(Weather.temp) ? "" : Math.round(Weather.temp) + "°"
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 20 * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: Weather.summary.split("°  ")[1] || ""
                            color: Theme.dim
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 10 * Theme.fontScale
                        }
                        Text {
                            width: parent.width
                            text: Settings.data.weatherCity
                            color: Theme.faint
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 10 * Theme.fontScale
                        }
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Weather, opens personalisation settings"
            }
        }

        // ---- system monitor ---------------------------------------------------

        DeskWindow {
            id: statsWin
            winNs: "shani-desk-stats"
            show: Array.from(Settings.data.desktopWidgets).indexOf("stats") >= 0
            mask: Region { item: statsCard }

            Glass {
                id: statsCard
                x: 1650; y: 900
                width: 212
                height: 104
                radius: Theme.radiusLarge
                elevation: "soft"

                Component.onCompleted: {
                    const p = scr.loadPos("stats", width, height);
                    x = p.x; y = p.y;
                }
                onVisibleChanged: if (visible) {
                    const p = scr.loadPos("stats", width, height);
                    x = p.x; y = p.y;
                }

                MouseArea {
                    id: statsDrag
                    anchors.fill: parent
                    drag.target: statsCard
                    drag.threshold: 8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { const was = Ui.processes; Ui.closeAll(); Ui.processes = !was; }
                    onReleased: if (statsDrag.drag.active) scr.savePos("stats", statsCard.x, statsCard.y)
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10
                    Repeater {
                        model: [
                            { label: "cpu", value: SysStats.cpu, tint: Theme.accent },
                            { label: "mem", value: SysStats.mem, tint: Theme.blue }
                        ]
                        Row {
                            required property var modelData
                            width: parent.width
                            height: 14
                            spacing: 8
                            Text {
                                text: modelData.label
                                color: Theme.dim
                                width: 30
                                font.family: Theme.mono
                                font.pixelSize: 10 * Theme.fontScale
                            }
                            Rectangle {
                                width: 116
                                anchors.verticalCenter: parent.verticalCenter
                                height: 4
                                radius: 2
                                color: Theme.hover
                                Rectangle {
                                    width: Math.max(2, parent.width * modelData.value)
                                    height: 4
                                    radius: 2
                                    color: modelData.tint
                                }
                            }
                            Text {
                                width: parent.width - 30 - 8 - 116 - 8
                                text: Math.round(modelData.value * 100) + "%"
                                color: Theme.faint
                                font.family: Theme.mono
                                font.pixelSize: 10 * Theme.fontScale
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                    Text {
                        text: "↓ " + SysStats.rate(SysStats.rxRate) + "  ↑ " + SysStats.rate(SysStats.txRate)
                        color: Theme.dim
                        font.family: Theme.mono
                        font.pixelSize: 10 * Theme.fontScale
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: "System monitor, opens processes"
            }
        }
    }
}
