// The shell's own settings, in the sidebar. Everything here is a key in
// ~/.config/shani-shell/settings.json — this page and the file are the same
// thing, and either can change it.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    readonly property var d: Settings.data
    property var wallpapers: []

    function minutes(s) { return s <= 0 ? "Never" : Math.round(s / 60) + " min"; }

    Process {
        running: page.visible
        command: ["sh", "-c", 'find /usr/share/backgrounds "$HOME/Pictures/Wallpapers" -maxdepth 2 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \\) 2>/dev/null | head -60']
        stdout: StdioCollector { onStreamFinished: page.wallpapers = text.trim().split("\n").filter(x => x) }
    }

    // declared at the root: the categories below use them as page.…
    property string pickFor: "both"
    readonly property var tileNames: ({ wifi: "Wi-Fi", bluetooth: "Bluetooth", airplane: "Airplane mode", hotspot: "Hotspot", vpn: "VPN",
        dnd: "Do Not Disturb", focus: "Focus", phone: "Phone", timer: "Focus timer", caffeine: "Caffeine", power: "Power mode",
        nightlight: "Night light", dark: "Dark style", mic: "Microphone", camera: "Camera", record: "Screen record",
        screenshot: "Screenshot", lens: "Lens", colorpicker: "Color picker", rotate: "Auto-rotate", flashlight: "Flashlight",
        display: "Display", osk: "Screen keyboard", keyboard: "Keyboard", clipboard: "Clipboard", backup: "Backup", access: "Accessibility",
        captions: "Live captions", transcribe: "Live transcribe", speak: "Read aloud", magnifier: "Magnifier", callrecord: "Call record",
        cast: "Cast", touch: "Smart touch", photo: "Photo", chronoa: "Chronoa" })
    readonly property var tileOrder: {
        const known = Object.keys(tileNames);
        const o = Array.from(d.tileOrder).filter(t => known.indexOf(t) >= 0);
        return o.concat(known.filter(t => o.indexOf(t) < 0));
    }
    function moveTile(t, by) {
        const o = tileOrder.slice();
        const i = o.indexOf(t), j = i + by;
        if (j < 0 || j >= o.length)
            return;
        o.splice(i, 1);
        o.splice(j, 0, t);
        d.tileOrder = o;
    }
    property var catalogue: []
    function nameOf(id) {
        if (id === "en") return "English";
        if (id === "mr") return "मराठी (smart matras)";
        const c = catalogue.find(x => x.id === id);
        return c ? c.name : id;
    }

    // Deepin's control centre in a sidebar: a grid of categories, then one at a time
    readonly property string cat: Ui.settingsCat
    readonly property var cats: [{ id: "personal", words: "wallpaper accent theme dark icons fonts cursor pointer blur dock bar tiles hot corners weather night light look", label: "Personalisation", icon: "preferences-desktop-wallpaper" }, { id: "notifications", words: "notifications pop-ups sound apps do not disturb focus modes schedule quiet", label: "Notifications", icon: "preferences-system-notifications" }, { id: "network", words: "network proxy dns wifi vpn wired internet", label: "Network", icon: "network-workgroup" }, { id: "displays", words: "displays screens monitor resolution refresh rate scale rotation arrange mirror vrr", label: "Displays", icon: "video-display" }, { id: "windows", words: "windows gaps focus ring column width animations tiling", label: "Windows", icon: "preferences-system-windows" }, { id: "sound", words: "sound equaliser equalizer eq bass loudness crossfeed headphones autoeq impulse microphone noise profiles system sounds", label: "Sound", icon: "audio-speakers" }, { id: "access", words: "accessibility screen reader large text contrast mono flash speak captions magnifier smart touch", label: "Accessibility", icon: "preferences-desktop-accessibility" }, { id: "input", words: "keyboard layouts language input touchpad mouse tap scroll speed repeat shortcuts compose caps osk", label: "Keyboard & input", icon: "input-keyboard" }, { id: "time", words: "date time timezone clock 24-hour language locale region formats", label: "Date & language", icon: "preferences-system-time" }, { id: "apps", words: "default apps browser mail startup autostart flatpak permissions screenshots terminal recordings", label: "Default apps", icon: "preferences-desktop-default-applications" }, { id: "search", words: "search launcher files folders documents web engine google duckduckgo calculator", label: "Search", icon: "system-search" }, { id: "privacy", words: "privacy permissions camera microphone recent files trash lock screen clipboard", label: "Privacy", icon: "preferences-system-privacy" }, { id: "chronoa", words: "chronoa assistant ai island model voice wake word", label: "Chronoa", icon: "face-smile-big" }, { id: "account", words: "account name password picture avatar", label: "Your account", icon: "avatar-default" }, { id: "users", words: "users add user remove administrator automatic login", label: "Users", icon: "system-users" }, { id: "power", words: "power battery saver idle lock suspend lid power button charge limit", label: "Power", icon: "preferences-system-power" }, { id: "about", words: "about computer name hostname system version hardware", label: "About", icon: "help-about" }]
    readonly property string catTitle: (cats.find(c => c.id === cat) || { label: "Shell settings" }).label
    // find a setting by what is in it: "proxy" → Network, "lid" → Power
    property string query: ""
    readonly property var shownCats: query.trim() === "" ? cats : cats.filter(c => {
        const hay = (c.label + " " + c.words).toLowerCase();
        return query.trim().toLowerCase().split(/\s+/).every(t => hay.split(/[\s&]+/).some(w => w.startsWith(t)));
    })
    TextField {
        id: settingsSearch
        Layout.fillWidth: true
        visible: page.cat === ""
        // typed into as soon as Settings opens
        onVisibleChanged: if (visible) { text = ""; input.forceActiveFocus(); }
        placeholder: "Search settings — proxy, lid, fonts, password…"
        onTextChanged: page.query = text
        onAccepted: if (page.shownCats.length) { Ui.settingsCat = page.shownCats[0].id; text = ""; }
    }
    GridLayout {
        Layout.fillWidth: true
        visible: page.cat === ""
        columns: 2
        columnSpacing: 8
        rowSpacing: 8
        Repeater {
            model: page.shownCats
            Rectangle {
                id: catTile
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 64
                radius: Theme.radius
                color: catArea.containsMouse ? Theme.pressed : Theme.hover
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    Rectangle {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: 10
                        color: Theme.accentSoft
                        Icon { anchors.centerIn: parent; name: catTile.modelData.icon; size: 20; color: Theme.accent }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: catTile.modelData.label
                        color: Theme.text
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: 13 * Theme.fontScale
                        font.weight: Font.Medium
                    }
                }
                MouseArea { id: catArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Ui.settingsCat = catTile.modelData.id }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "personal"
        spacing: 12
        SectionTitle { Layout.fillWidth: true; text: "Wallpaper" }
        // a slideshow: the pictures in a folder, changed every so often
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            TextField {
                Layout.fillWidth: true
                placeholder: page.d.slideshowDir ? "Slideshow from " + page.d.slideshowDir : "Slideshow: a folder of pictures — ~/Pictures/Wallpapers"
                onAccepted: { page.d.slideshowDir = text.trim(); text = ""; }
            }
            Button { visible: page.d.slideshowDir !== ""; text: "Stop"; onClicked: page.d.slideshowDir = "" }
        }
        Flow {
            Layout.fillWidth: true
            visible: page.d.slideshowDir !== ""
            spacing: 6
            Repeater {
                model: [5, 30, 60, 1440]
                Choice {
                    required property int modelData
                    text: modelData === 1440 ? "Daily" : modelData >= 60 ? "Hourly" : "Every " + modelData + " min"
                    selected: page.d.slideshowMinutes === modelData
                    onClicked: page.d.slideshowMinutes = modelData
                }
            }
        }
        // any picture, not only those in the wallpaper folders
        TextField {
            Layout.fillWidth: true
            placeholder: "Use any picture — its path, e.g. ~/Pictures/holiday.jpg"
            onAccepted: {
                const p = text.trim().replace(/^~/, Quickshell.env("HOME"));
                if (!/\.(png|jpe?g|webp)$/i.test(p))
                    return;
                if (page.pickFor === "light") page.d.wallpaperLight = p;
                else if (page.pickFor === "dark") page.d.wallpaperDark = p;
                else { page.d.wallpaper = p; page.d.wallpaperLight = ""; page.d.wallpaperDark = ""; }
                text = "";
            }
        }
        // a click sets the one wallpaper, or the light / dark style's own
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [{ id: "both", label: "Both styles" }, { id: "light", label: "Light style" }, { id: "dark", label: "Dark style" }]
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.pickFor === modelData.id
                    onClicked: page.pickFor = modelData.id
                }
            }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 6
            rowSpacing: 6
            Repeater {
                model: page.wallpapers
                Rectangle {
                    required property string modelData
                    Layout.fillWidth: true
                    implicitHeight: 62
                    radius: 10
                    color: Theme.hover
                    border.width: (page.pickFor === "light" ? page.d.wallpaperLight : page.pickFor === "dark" ? page.d.wallpaperDark : page.d.wallpaper) === modelData ? 2 : 0
                    border.color: Theme.accent
                    clip: true
                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: "file://" + parent.modelData
                        sourceSize: Qt.size(240, 140)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (page.pickFor === "light")
                                page.d.wallpaperLight = parent.modelData;
                            else if (page.pickFor === "dark")
                                page.d.wallpaperDark = parent.modelData;
                            else {
                                // one for both styles: the per-style ones step aside
                                page.d.wallpaper = parent.modelData;
                                page.d.wallpaperLight = "";
                                page.d.wallpaperDark = "";
                                page.d.wallpaperLight = "";
                                page.d.wallpaperDark = "";
                            }
                        }
                    }
                }
            }
        }

        SectionTitle { Layout.fillWidth: true; text: "Look & feel" }
        // the accent: one of GNOME's nine (apps follow it too), or the wallpaper's
        Text { text: "Accent colour"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: ["teal", "blue", "purple", "pink", "red", "orange", "yellow", "green", "slate"]
                Rectangle {
                    required property string modelData
                    readonly property bool chosen: !page.d.accentFromWallpaper && page.d.accentName === modelData
                    width: 30
                    height: 30
                    radius: 15
                    color: Theme.accents[modelData][Theme.dark ? 1 : 0]
                    border.width: chosen ? 3 : 0
                    border.color: Theme.text
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData + " accent"
                    Accessible.checked: chosen
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { page.d.accentName = parent.modelData; page.d.accentFromWallpaper = false; }
                    }
                }
            }
        }
        SwitchRow { Layout.fillWidth: true; text: "Accent from wallpaper"; hint: "the wallpaper's most vivid colour"; checked: page.d.accentFromWallpaper; onToggled: on => page.d.accentFromWallpaper = on }
        Text { text: "Dark style"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [{ id: "manual", label: "By hand" }, { id: "sunset", label: "Sunset to sunrise" }, { id: "custom", label: "Set hours" }]
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.d.darkSchedule === modelData.id
                    onClicked: page.d.darkSchedule = modelData.id
                }
            }
        }
        RowLayout {
            visible: page.d.darkSchedule === "custom"
            spacing: 8
            Text { text: "From"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
            TextField { Layout.preferredWidth: 90; text: page.d.darkFrom; placeholder: "19:00"; onAccepted: if (/^\d\d?:\d\d$/.test(text.trim())) page.d.darkFrom = text.trim() }
            Text { text: "to"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
            TextField { Layout.preferredWidth: 90; text: page.d.darkTo; placeholder: "07:00"; onAccepted: if (/^\d\d?:\d\d$/.test(text.trim())) page.d.darkTo = text.trim() }
        }
        SwitchRow { Layout.fillWidth: true; text: "Always show scrollbars"; hint: "off: they appear while scrolling"; checked: page.d.showScrollbars; onToggled: on => page.d.showScrollbars = on }
        SwitchRow { Layout.fillWidth: true; text: "Blur"; checked: page.d.blur; onToggled: on => page.d.blur = on }
        SwitchRow { Layout.fillWidth: true; text: "Reduce motion"; hint: "no slides, fades or zoom"; checked: page.d.reduceMotion; onToggled: on => page.d.reduceMotion = on }
        SwitchRow { Layout.fillWidth: true; text: "Adaptive brightness"; hint: "adjust by time of day"; checked: page.d.adaptiveBrightness; onToggled: on => page.d.adaptiveBrightness = on; visible: Brightness.available }
        RowLayout {
            Layout.fillWidth: true
            visible: NightLight.available
            Text { text: "Night light"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; Layout.preferredWidth: 90 }
            Repeater {
                model: [2700, 3400, 4000, 5000]
                Choice {
                    required property int modelData
                    text: modelData + " K"
                    selected: page.d.nightLightTemp === modelData
                    onClicked: page.d.nightLightTemp = modelData
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: NightLight.available
            Text { text: "Turns on"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; Layout.preferredWidth: 90 }
            Repeater {
                model: [{ id: "manual", label: "By hand" }, { id: "sunset", label: "Sunset to sunrise" }, { id: "custom", label: "Set hours" }]
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.d.nightLightSchedule === modelData.id
                    onClicked: page.d.nightLightSchedule = modelData.id
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: NightLight.available && page.d.nightLightSchedule === "sunset" && !NightLight.located
            text: "Sunset needs your location: set a city under Weather. Until then, the hours below are used."
            color: Theme.faint
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: 11 * Theme.fontScale
        }
        RowLayout {
            Layout.fillWidth: true
            visible: NightLight.available && (page.d.nightLightSchedule === "custom" || (page.d.nightLightSchedule === "sunset" && !NightLight.located))
            spacing: 8
            Text { text: "From"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
            TextField {
                Layout.preferredWidth: 90
                text: page.d.nightLightFrom
                placeholder: "21:00"
                onAccepted: if (/^\d\d?:\d\d$/.test(text.trim())) page.d.nightLightFrom = text.trim()
            }
            Text { text: "to"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
            TextField {
                Layout.preferredWidth: 90
                text: page.d.nightLightTo
                placeholder: "07:00"
                onAccepted: if (/^\d\d?:\d\d$/.test(text.trim())) page.d.nightLightTo = text.trim()
            }
        }

        SettingsLook { Layout.fillWidth: true; active: page.cat === "personal" }

        // ---- the sidebar's tiles: which, and in what order (after Android) -----
        SectionTitle { Layout.fillWidth: true; text: "Bar & dock" }
        SwitchRow { Layout.fillWidth: true; text: "Network speed"; checked: page.d.showNetSpeed; onToggled: on => page.d.showNetSpeed = on }
        SwitchRow { Layout.fillWidth: true; text: "CPU and memory"; checked: page.d.showSysStats; onToggled: on => page.d.showSysStats = on }
        SwitchRow { Layout.fillWidth: true; text: "24-hour clock"; checked: page.d.use24h; onToggled: on => page.d.use24h = on }
        SwitchRow { Layout.fillWidth: true; text: "Seconds"; checked: page.d.showSeconds; onToggled: on => page.d.showSeconds = on }
        SwitchRow { Layout.fillWidth: true; text: "Date beside the clock"; checked: page.d.barDate; onToggled: on => page.d.barDate = on }
        SwitchRow { Layout.fillWidth: true; text: "Battery percentage"; checked: page.d.barBatteryPercent; onToggled: on => page.d.barBatteryPercent = on }
        SwitchRow { Layout.fillWidth: true; text: "Dock"; checked: page.d.dock; onToggled: on => page.d.dock = on }
        SwitchRow { Layout.fillWidth: true; text: "Hide the dock"; hint: "touch the bottom edge to show it"; checked: page.d.dockAutoHide; onToggled: on => page.d.dockAutoHide = on }
        RowLayout {
            Layout.fillWidth: true
            Text { text: "Dock icons"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; Layout.preferredWidth: 90 }
            Repeater {
                model: [{ v: 36, label: "Small" }, { v: 44, label: "Medium" }, { v: 56, label: "Large" }]
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.d.dockIconSize === modelData.v
                    onClicked: page.d.dockIconSize = modelData.v
                }
            }
        }

        SectionTitle { Layout.fillWidth: true; text: "Quick tiles" }
        Repeater {
            model: page.tileOrder
            RowLayout {
                required property string modelData
                required property int index
                Layout.fillWidth: true
                spacing: 4
                SwitchRow {
                    Layout.fillWidth: true
                    text: page.tileNames[modelData]
                    checked: Array.from(page.d.hiddenTiles).indexOf(modelData) < 0
                    onToggled: on => page.d.hiddenTiles = on ? Array.from(page.d.hiddenTiles).filter(x => x !== modelData)
                                                              : Array.from(page.d.hiddenTiles).concat([modelData])
                }
                IconButton { icon: "go-up"; size: 24; enabled: index > 0; onClicked: page.moveTile(modelData, -1) }
                IconButton { icon: "go-down"; size: 24; enabled: index < page.tileOrder.length - 1; onClicked: page.moveTile(modelData, 1) }
            }
        }

        SectionTitle { Layout.fillWidth: true; text: "Hot corners" }
        Repeater {
            model: [
                { label: "Top left", key: "hotCornerTopLeft" }, { label: "Top right", key: "hotCornerTopRight" },
                { label: "Bottom left", key: "hotCornerBottomLeft" }, { label: "Bottom right", key: "hotCornerBottomRight" }
            ]
            ColumnLayout {
                id: cornerRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 4
                Text { text: cornerRow.modelData.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: ["none", "overview", "launcher", "sidebar", "chronoa", "lock"]
                        Choice {
                            required property string modelData
                            text: modelData
                            selected: (page.d[cornerRow.modelData.key] || "none") === modelData
                            onClicked: page.d[cornerRow.modelData.key] = modelData
                        }
                    }
                }
            }
        }

        SectionTitle { Layout.fillWidth: true; text: "Weather" }
        TextField {
            Layout.fillWidth: true
            placeholder: "City for the weather — off when empty (asks open-meteo.com)"
            text: page.d.weatherCity
            onAccepted: { page.d.weatherLat = 0; page.d.weatherLon = 0; page.d.weatherCity = text.trim(); }
        }

    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "notifications"
        spacing: 12
        SectionTitle { Layout.fillWidth: true; text: "Notifications" }
        Text { text: "Pop-ups appear"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [{ id: "top-right", label: "Top right" }, { id: "top-center", label: "Top centre" }, { id: "bottom-right", label: "Bottom right" }]
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.d.popupPosition === modelData.id
                    onClicked: page.d.popupPosition = modelData.id
                }
            }
        }
        SwitchRow { Layout.fillWidth: true; text: "Sound"; hint: "a chime for each notification that pops up"; checked: page.d.notifSound; onToggled: on => page.d.notifSound = on }
        Text {
            Layout.fillWidth: true
            text: page.d.notifApps.length ? "Each app that has sent a notification:" : "Apps appear here once they send a notification."
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12 * Theme.fontScale
        }
        Repeater {
            model: page.d.notifApps
            ColumnLayout {
                id: appRow
                required property string modelData
                readonly property bool silent: Array.from(page.d.silentApps).indexOf(modelData) >= 0
                readonly property bool through: Array.from(page.d.dndAllowedApps).indexOf(modelData) >= 0
                Layout.fillWidth: true
                spacing: 2
                Text { text: appRow.modelData; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale; font.weight: Font.Medium }
                RowLayout {
                    spacing: 6
                    Choice {
                        text: "Pop-ups"
                        selected: !appRow.silent
                        onClicked: page.d.silentApps = appRow.silent ? Array.from(page.d.silentApps).filter(x => x !== appRow.modelData)
                                                                     : Array.from(page.d.silentApps).concat([appRow.modelData])
                    }
                    Choice {
                        text: "Through Do Not Disturb"
                        selected: appRow.through
                        onClicked: page.d.dndAllowedApps = appRow.through ? Array.from(page.d.dndAllowedApps).filter(x => x !== appRow.modelData)
                                                                          : Array.from(page.d.dndAllowedApps).concat([appRow.modelData])
                    }
                }
            }
        }
        Text { text: "Show pop-ups for"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [4, 6, 10, 20]
                Choice {
                    required property int modelData
                    text: modelData + " s"
                    selected: page.d.popupSeconds === modelData
                    onClicked: page.d.popupSeconds = modelData
                }
            }
        }

        SettingsFocus { Layout.fillWidth: true }
        SectionTitle { Layout.fillWidth: true; text: "Quiet automatically" }
        SwitchRow { Layout.fillWidth: true; text: "While presenting"; hint: "notifications wait while the screen is shared"; checked: page.d.quietWhileSharing; onToggled: on => page.d.quietWhileSharing = on }
        SwitchRow { Layout.fillWidth: true; text: "While something is fullscreen"; hint: "films, slides, games — a game also gets the performance profile"; checked: page.d.quietWhileFullscreen; onToggled: on => page.d.quietWhileFullscreen = on }

    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "access"
        spacing: 12
        SectionTitle { Layout.fillWidth: true; text: "Accessibility" }
        SwitchRow { Layout.fillWidth: true; text: "Screen reader"; hint: "Orca; the shell's own controls are labelled for it"; checked: page.d.screenReader; onToggled: on => page.d.screenReader = on }
        SwitchRow { Layout.fillWidth: true; text: "Large text"; hint: "the shell and apps, 125 %"; checked: page.d.largeText; onToggled: on => page.d.largeText = on }
        SwitchRow { Layout.fillWidth: true; text: "High contrast"; checked: page.d.highContrast; onToggled: on => page.d.highContrast = on }
        SwitchRow { Layout.fillWidth: true; text: "Mono audio"; checked: page.d.monoAudio; onToggled: on => page.d.monoAudio = on }
        SwitchRow { Layout.fillWidth: true; text: "Flash for alerts"; hint: "the screen edge flashes when a notification arrives"; checked: page.d.flashAlerts; onToggled: on => page.d.flashAlerts = on }
        SwitchRow { Layout.fillWidth: true; text: "Speak notifications"; hint: "the app and title, read aloud"; checked: page.d.speakNotifications; onToggled: on => page.d.speakNotifications = on }
        SwitchRow { Layout.fillWidth: true; text: "Smart touch"; hint: "a floating bubble that opens the Ring, for touchscreens"; checked: page.d.assistiveTouch; onToggled: on => page.d.assistiveTouch = on }

        Text { text: "Read aloud speed"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [{ id: "slow", label: "Slow" }, { id: "normal", label: "Normal" }, { id: "fast", label: "Fast" }]
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.d.speechRate === modelData.id
                    onClicked: page.d.speechRate = modelData.id
                }
            }
        }
        Text { text: "Captions and transcribe language"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [{ id: "auto", label: "Detect" }, { id: "en", label: "English" }, { id: "mr", label: "मराठी" }, { id: "hi", label: "हिन्दी" }]
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.d.captionLanguage === modelData.id
                    onClicked: page.d.captionLanguage = modelData.id
                }
            }
        }

    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "input"
        spacing: 12
        // ---- screen keyboard languages: any xkb layout, plus the hand-made two
        SectionTitle { Layout.fillWidth: true; text: "Screen keyboard" }
        Process {
            running: page.visible && page.catalogue.length === 0
            command: ["python3", Osk.script, "--list"]
            stdout: StdioCollector { onStreamFinished: { try { page.catalogue = JSON.parse(text); } catch (e) {} } }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: page.d.oskLanguages
                Choice {
                    required property string modelData
                    text: page.nameOf(modelData) + (page.d.oskLanguages.length > 1 ? "  ✕" : "")
                    selected: true
                    onClicked: if (page.d.oskLanguages.length > 1) page.d.oskLanguages = Array.from(page.d.oskLanguages).filter(x => x !== modelData)
                }
            }
        }
        TextField {
            id: layoutSearch
            Layout.fillWidth: true
            placeholder: "Add a layout — marathi, tamil, russian, arabic …"
        }
        Repeater {
            model: {
                const q = layoutSearch.text.trim().toLowerCase();
                if (q.length < 2)
                    return [];
                return page.catalogue.filter(x => x.name.toLowerCase().indexOf(q) >= 0 || x.id.indexOf(q) >= 0
                    || x.langs.some(l => l === q)).slice(0, 12);
            }
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: "input-keyboard"
                title: modelData.name
                subtitle: modelData.id
                onClicked: {
                    if (page.d.oskLanguages.indexOf(modelData.id) < 0)
                        page.d.oskLanguages = Array.from(page.d.oskLanguages).concat([modelData.id]);
                    layoutSearch.text = "";
                }
            }
        }

        SettingsInput { Layout.fillWidth: true }
        SettingsShortcuts { Layout.fillWidth: true; active: page.cat === "input" }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "time"
        spacing: 12
        SettingsDateLanguage { Layout.fillWidth: true; active: page.cat === "time" }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "apps"
        spacing: 12
        SectionTitle { Layout.fillWidth: true; text: "Apps & files" }
        TextField {
            Layout.fillWidth: true
            placeholder: "Terminal for “Run in terminal” (foot)"
            text: page.d.terminal
            onAccepted: page.d.terminal = text.trim() || "foot"
        }
        TextField {
            Layout.fillWidth: true
            placeholder: "Screen recordings folder (empty: Videos/Recordings)"
            text: page.d.recordingsDir
            onAccepted: page.d.recordingsDir = text.trim()
        }

        SettingsDefaultApps { Layout.fillWidth: true; active: page.cat === "apps" }
        SettingsStartup { Layout.fillWidth: true; active: page.cat === "apps" }
        SettingsAppPermissions { Layout.fillWidth: true; active: page.cat === "apps" }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "account"
        spacing: 12
        SettingsAccount { Layout.fillWidth: true; active: page.cat === "account" }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "network"
        spacing: 12
        SettingsNetwork { Layout.fillWidth: true; active: page.cat === "network" }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "windows"
        spacing: 12
        SettingsWindows { Layout.fillWidth: true }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "displays"
        spacing: 12
        SettingsDisplays { Layout.fillWidth: true; active: page.cat === "displays" }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "sound"
        spacing: 12
        SettingsSound { Layout.fillWidth: true }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "search"
        spacing: 12
        SettingsSearch { Layout.fillWidth: true }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "privacy"
        spacing: 12
        SettingsPrivacy { Layout.fillWidth: true; active: page.cat === "privacy" }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "chronoa"
        spacing: 12
        SettingsChronoa { Layout.fillWidth: true }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "users"
        spacing: 12
        SettingsUsers { Layout.fillWidth: true; active: page.cat === "users" }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "power"
        spacing: 12
        SectionTitle { Layout.fillWidth: true; text: "Battery & wellbeing" }
        SwitchRow { Layout.fillWidth: true; text: "Battery saver at 20 %"; hint: "power saver on battery, back when charging"; checked: page.d.autoPowerSaver; onToggled: on => page.d.autoPowerSaver = on }
        SwitchRow { Layout.fillWidth: true; text: "Screen time"; hint: "per-app focus time, kept on this machine"; checked: page.d.screenTime; onToggled: on => page.d.screenTime = on }

        SettingsPowerKeys { Layout.fillWidth: true; active: page.cat === "power" }
        SectionTitle { Layout.fillWidth: true; text: "When idle" }
        Repeater {
            model: [
                { label: "Lock after", key: "lockAfter", options: [60, 120, 300, 600, 900, 0] },
                { label: "Screen off after", key: "screenOffAfter", options: [120, 300, 600, 1800, 0] },
                { label: "Suspend after", key: "suspendAfter", options: [900, 1800, 3600, 0] }
            ]
            ColumnLayout {
                id: stage
                required property var modelData
                Layout.fillWidth: true
                spacing: 4
                Text { text: stage.modelData.label + " (on power)"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: stage.modelData.options
                        Choice {
                            required property int modelData
                            text: page.minutes(modelData)
                            selected: page.d[stage.modelData.key] === modelData
                            onClicked: page.d[stage.modelData.key] = modelData
                        }
                    }
                }
            }
        }
        SwitchRow { Layout.fillWidth: true; text: "Lock before suspend"; checked: page.d.lockBeforeSuspend; onToggled: on => page.d.lockBeforeSuspend = on }

    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cat === "about"
        spacing: 12
        SettingsAbout { Layout.fillWidth: true; active: page.cat === "about" }
    }
    Text {
        Layout.fillWidth: true
        text: "Saved to " + Settings.path
        color: Theme.faint
        elide: Text.ElideMiddle
        font.family: Theme.mono
        font.pixelSize: 10 * Theme.fontScale
    }
}
