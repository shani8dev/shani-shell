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
import "../../Common/Time.js" as Time

Variants {
    model: Quickshell.screens
    Scope {
        id: scr
        required property var modelData
        // shortcut: Settings.qml's adapter is outside this change's file ownership, so
        // the lock flag is read defensively here; declare widgetsLocked in Settings.qml
        // (plus a SettingsPage toggle) to persist it and make it settable from the UI.
        property bool widgetsLocked: Settings.data.widgetsLocked === true

        // positions: remembered, or the sensible default, then clamped so a card
        // stays on the screen, clear of the bar above and the dock below
        function loadPos(id, w, h) {
            const sw = scr.modelData ? scr.modelData.width : 1920;
            const sh = scr.modelData ? scr.modelData.height : 1080;
            // how far a card stays above the bottom edge: the dock, or the bar
            // when the bar is down there (a classroom board)
            const bottomGap = bottomBar ? Theme.barHeight + 56 : 104;
            const defaults = {
                "clock": { x: 24, y: 64 },
                "weather": { x: Math.max(12, sw - w - 24), y: 64 },
                "media": { x: 24, y: Math.max(12, sh - h - bottomGap) },
                "stats": { x: Math.max(12, sw - w - 24), y: Math.max(12, sh - h - bottomGap) }
            };
            return scr.clampPos(id, (Settings.data.deskPos || {})[id] || defaults[id], w, h, sw, sh);
        }
        // clear of the bar, whichever edge it is on: a bar at the bottom (a
        // board) is a floor for a card, one at the top a ceiling
        readonly property bool bottomBar: FormFactor.barEdge(modelData ? modelData.name : "") === "bottom"
        function clampPos(id, want, w, h, sw, sh) {
            const x = Math.min(Math.max(12, want.x), Math.max(12, sw - w - 12));
            const ceil = bottomBar ? 12 : Theme.barHeight + 12;
            const floor = bottomBar ? Theme.barHeight + 16 : 96;
            const y = Math.min(Math.max(ceil, want.y), Math.max(ceil, sh - h - floor));
            return { x: x, y: y };
        }
        function savePos(id, x, y) {
            const keep = JSON.parse(JSON.stringify(Settings.data.deskPos || {}));
            keep[id] = { x: Math.round(x), y: Math.round(y) };
            Settings.data.deskPos = keep;
        }
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
                width: Theme.px(216)
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
                    drag.target: widgetsLocked ? null : clockCard
                    drag.threshold: 8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Ui.openClocks("")
                    onReleased: if (clockDrag.drag.active) scr.savePos("clock", clockCard.x, clockCard.y)
                }

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.px(14) }
                    spacing: Theme.px(3)
                    Text {
                        text: Settings.data.use24h ? Qt.formatTime(deskClock.date, "HH:mm") : Qt.formatTime(deskClock.date, "h:mm AP")
                        color: Theme.text
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(30)
                        font.weight: Font.Medium
                    }
                    Text {
                        text: Qt.formatDate(deskClock.date, "dddd d MMMM")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
                Text {
                    id: agendaText
                    visible: Agenda.available && Agenda.upcoming.length > 0
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.px(14) }
                    text: visible ? Agenda.when(Agenda.upcoming[0]) + "  ·  " + Agenda.upcoming[0].summary : ""
                    color: Theme.faint
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                Accessible.role: Accessible.Button
                Accessible.name: Tr.t("Clock, opens the control centre")
                Accessible.onPressAction: Ui.openClocks("")
            }
        }

        // ---- what is playing ------------------------------------------------

        DeskWindow {
            id: mediaWin
            winNs: "shani-desk-media"
            show: Array.from(Settings.data.desktopWidgets).indexOf("media") >= 0
                && player !== null
            readonly property var player: Media.current
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
                width: Theme.px(252)
                height: Theme.px(80)
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
                    drag.target: widgetsLocked ? null : mediaCard
                    drag.threshold: 8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Ui.toggleControlCenter()
                    onReleased: if (mediaDrag.drag.active) scr.savePos("media", mediaCard.x, mediaCard.y)
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.px(12)
                    spacing: Theme.px(10)
                    ClippingRectangle {
                        width: Theme.px(56); height: Theme.px(56)
                        radius: Theme.px(12)
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
                        spacing: Theme.px(3)
                        Text {
                            width: parent.width
                            text: mediaWin.player ? (mediaWin.player.trackTitle || mediaWin.player.identity) : ""
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: mediaWin.player ? mediaWin.player.trackArtist : ""
                            color: Theme.dim
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        // seek by clicking along the track (only players that allow it)
                        Rectangle {
                            width: parent.width
                            height: Theme.px(12)
                            color: "transparent"
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                height: Theme.px(3)
                                radius: 1.5
                                color: Theme.hover
                            }
                            Rectangle {
                                width: Math.max(3, parent.width * Math.min(1,
                                    mediaWin.player && mediaWin.player.length > 0 ? mediaWin.shown / mediaWin.player.length : 0))
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                height: Theme.px(3)
                                radius: 1.5
                                color: Theme.accent
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: mediaWin.player && mediaWin.player.canSeek && mediaWin.player.length > 0
                                cursorShape: Qt.PointingHandCursor
                                onClicked: me => {
                                if (mediaWin.player && mediaWin.player.length > 0)
                                    mediaWin.player.position = mediaWin.player.length * (me.x / parent.width);
                            }
                            }
                        }
                        // elapsed and total, tucked over the seek bar's ends
                        Rectangle {
                            width: parent.width
                            height: Theme.px(11)
                            color: "transparent"
                            Text {
                                anchors.left: parent.left
                                text: Time.clock(mediaWin.player ? mediaWin.shown : 0)
                                color: Theme.faint
                                font.family: Theme.mono
                                font.pixelSize: Theme.px(9) * Theme.fontScale
                                Accessible.name: Tr.t("Elapsed %1").arg(text)
                            }
                            Text {
                                anchors.right: parent.right
                                text: Time.clock(mediaWin.player ? mediaWin.player.length : 0)
                                color: Theme.faint
                                font.family: Theme.mono
                                font.pixelSize: Theme.px(9) * Theme.fontScale
                                Accessible.name: Tr.t("Total %1").arg(text)
                            }
                        }
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: mediaWin.player && mediaWin.player.isPlaying ? "media-playback-pause" : "media-playback-start"
                        size: Theme.px(30)
                        onClicked: if (mediaWin.player) mediaWin.player.togglePlaying()
                        Accessible.name: Tr.t("Play or pause")
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: Tr.t("Now playing, opens the control centre")
                Accessible.onPressAction: Ui.toggleControlCenter()
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
                width: Theme.px(196)
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
                    drag.target: widgetsLocked ? null : weatherCard
                    drag.threshold: 8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Weather.enabled ? Ui.openWeather() : Ui.openSettings("personal")
                    onReleased: if (weatherDrag.drag.active) scr.savePos("weather", weatherCard.x, weatherCard.y)
                }

                Text {
                    visible: !Weather.enabled
                    anchors.centerIn: parent
                    text: Tr.t("Weather — set a city →")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                Row {
                    visible: Weather.enabled
                    anchors.fill: parent
                    anchors.margins: Theme.px(14)
                    spacing: Theme.px(12)
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: Weather.icon
                        size: Theme.px(30)
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
                            font.pixelSize: Theme.px(20) * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: Weather.summary.split("°  ")[1] || ""
                            color: Theme.dim
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        Text {
                            width: parent.width
                            text: Settings.data.weatherCity
                            color: Theme.faint
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: Weather.enabled ? Tr.t("Weather, opens the weather app") : Tr.t("Weather, opens personalisation settings")
                Accessible.onPressAction: Weather.enabled ? Ui.openWeather() : Ui.openSettings("personal")
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
                width: Theme.px(212)
                height: Theme.px(176)
                radius: Theme.radiusLarge
                elevation: "soft"
                readonly property real rootUsedPct: SysStats.rootTotal > 0
                    ? Math.min(1, SysStats.rootUsed / SysStats.rootTotal) : 0

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
                    drag.target: widgetsLocked ? null : statsCard
                    drag.threshold: 8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { const was = Ui.processes; Ui.closeAll(); Ui.processes = !was; }
                    onReleased: if (statsDrag.drag.active) scr.savePos("stats", statsCard.x, statsCard.y)
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.px(14)
                    spacing: Theme.px(6)
                    Repeater {
                        // severity tint matches the bar chip (cpu > .85, mem > .9):
                        // a glance tells you a resource is high, not just its number
                        model: [
                            { label: "cpu", value: SysStats.cpu, tint: SysStats.cpu > 0.85 ? Theme.amber : Theme.accent },
                            { label: "mem", value: SysStats.mem, tint: SysStats.mem > 0.9 ? Theme.amber : Theme.blue },
                            { label: "disk", value: statsCard.rootUsedPct,
                              tint: statsCard.rootUsedPct > 0.9 ? Theme.amber : Theme.accent }
                        ]
                        Row {
                            required property var modelData
                            width: parent.width
                            height: Theme.px(14)
                            spacing: Theme.px(8)
                            Text {
                                text: modelData.label
                                color: Theme.dim
                                width: Theme.px(30)
                                font.family: Theme.mono
                                font.pixelSize: Theme.px(10) * Theme.fontScale
                            }
                            Rectangle {
                                width: Theme.px(116)
                                anchors.verticalCenter: parent.verticalCenter
                                height: Theme.px(4)
                                radius: 2
                                color: Theme.hover
                                Rectangle {
                                    width: Math.max(2, parent.width * modelData.value)
                                    height: Theme.px(4)
                                    radius: 2
                                    color: modelData.tint
                                }
                            }
                            Text {
                                width: parent.width - 30 - 8 - 116 - 8
                                text: Math.round(modelData.value * 100) + "%"
                                color: Theme.faint
                                font.family: Theme.mono
                                font.pixelSize: Theme.px(10) * Theme.fontScale
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                    // the System Monitor keeps 60 CPU samples; draw that history here
                    // instead of letting it go unused in this small card
                    Sparkline {
                        width: parent.width
                        height: Theme.px(28)
                        values: SysStats.cpuHistory
                        color: Theme.accent
                    }
                    Text {
                        visible: SysStats.temp > 0
                        text: Tr.t("CPU %1°C", Math.round(SysStats.temp))
                        color: Theme.dim
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                    Text {
                        text: "↓ " + SysStats.rate(SysStats.rxRate) + "  ↑ " + SysStats.rate(SysStats.txRate)
                        color: Theme.dim
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: Tr.t("System monitor, opens processes")
                Accessible.onPressAction: { const was = Ui.processes; Ui.closeAll(); Ui.processes = !was; }
            }
        }
    }
}
