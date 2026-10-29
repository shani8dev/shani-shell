// The shell's own settings (shown in Modules/Settings/SettingsWindow). Everything here is a key in
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
    readonly property var tileNames: ({ wifi: "Wi-Fi", bluetooth: "Bluetooth", airplane: "Airplane mode", mobile: "Mobile data", hotspot: "Hotspot", vpn: "VPN",
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
    property bool inWindow: false        // in the Settings window: its own list replaces the grid
    readonly property var cats: [{ id: "personal", words: "wallpaper accent theme dark icons fonts cursor pointer blur dock bar tiles hot corners weather night light look", label: Tr.t("Personalisation"), icon: "preferences-desktop-wallpaper" }, { id: "notifications", words: "notifications pop-ups sound apps do not disturb focus modes schedule quiet", label: Tr.t("Notifications"), icon: "preferences-system-notifications" }, { id: "network", words: "network proxy dns wifi vpn wired internet", label: Tr.t("Network"), icon: "network-workgroup" }, { id: "displays", words: "displays screens monitor resolution refresh rate scale rotation arrange mirror vrr", label: Tr.t("Displays"), icon: "video-display" }, { id: "windows", words: "windows gaps focus ring column width animations tiling", label: Tr.t("Windows"), icon: "preferences-system-windows" }, { id: "sound", words: "sound equaliser equalizer eq bass loudness crossfeed headphones autoeq impulse microphone noise profiles system sounds", label: Tr.t("Sound"), icon: "audio-speakers" }, { id: "access", words: "accessibility screen reader large text contrast mono flash speak captions magnifier smart touch", label: Tr.t("Accessibility"), icon: "preferences-desktop-accessibility" }, { id: "input", words: "keyboard layouts language input touchpad mouse tap scroll speed repeat shortcuts compose caps osk", label: Tr.t("Keyboard & input"), icon: "input-keyboard" }, { id: "time", words: "date time timezone clock 24-hour language locale region formats", label: Tr.t("Date & language"), icon: "preferences-system-time" }, { id: "apps", words: "default apps browser mail startup autostart flatpak permissions screenshots terminal recordings", label: Tr.t("Default apps"), icon: "view-app-grid" }, { id: "search", words: "search launcher files folders documents web engine google duckduckgo calculator", label: Tr.t("Search"), icon: "system-search" }, { id: "printers", words: "printers printer print cups default test page queue scanner add", label: Tr.t("Printers"), icon: "printer" }, { id: "sharing", words: "sharing share folder network samba smb files public windows", label: Tr.t("Sharing"), icon: "folder-remote" }, { id: "backup", words: "backup backups restore earlier versions snapshots time machine history deleted files drive restic", label: Tr.t("Backup"), icon: "drive-harddisk" }, { id: "automations", words: "automations rules when then routines triggers wifi plugged headphones schedule shortcuts", label: Tr.t("Automations"), icon: "system-run" }, { id: "privacy", words: "privacy permissions camera microphone recent files trash lock screen clipboard", label: Tr.t("Privacy"), icon: "preferences-system-privacy" }, { id: "chronoa", words: "chronoa assistant ai island model voice wake word", label: Tr.t("Chronoa"), icon: "face-smile-big" }, { id: "account", words: "account name password picture avatar", label: Tr.t("Your account"), icon: "avatar-default" }, { id: "users", words: "users add user remove administrator automatic login", label: Tr.t("Users"), icon: "system-users" }, { id: "power", words: "power battery saver idle lock suspend lid power button charge limit", label: Tr.t("Power"), icon: "preferences-system-power" }, { id: "about", words: "about computer name hostname system version hardware", label: Tr.t("About"), icon: "help-about" }]
    readonly property string catTitle: (cats.find(c => c.id === cat) || { label: Tr.t("Settings") }).label
    // find a setting by what is in it: "proxy" → Network, "lid" → Power
    property string query: ""
    readonly property var shownCats: query.trim() === "" ? cats : cats.filter(c => {
        const hay = (c.label + " " + c.words).toLowerCase();
        return query.trim().toLowerCase().split(/\s+/).every(t => hay.split(/[\s&]+/).some(w => w.startsWith(t)));
    })
    TextField {
        id: settingsSearch
        Layout.fillWidth: true
        visible: page.cat === "" && !page.inWindow
        // typed into as soon as Settings opens
        onVisibleChanged: if (visible) { text = ""; input.forceActiveFocus(); }
        placeholder: Tr.t("Search settings — proxy, lid, fonts, password…")
        onTextChanged: page.query = text
        onAccepted: if (page.shownCats.length) { Ui.settingsCat = page.shownCats[0].id; text = ""; }
    }
    GridLayout {
        Layout.fillWidth: true
        visible: page.cat === "" && !page.inWindow
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
                color: catArea.containsMouse ? Theme.surface3 : Theme.surface2
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

    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "personal"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Wallpaper") }
                // a slideshow: the pictures in a folder, changed every so often
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    TextField {
                        Layout.fillWidth: true
                        placeholder: page.d.slideshowDir ? "Slideshow from " + page.d.slideshowDir : "Slideshow: a folder of pictures — ~/Pictures/Wallpapers"
                        onAccepted: { page.d.slideshowDir = text.trim(); text = ""; }
                    }
                    Button { visible: page.d.slideshowDir !== ""; text: Tr.t("Stop"); onClicked: page.d.slideshowDir = "" }
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
                    placeholder: Tr.t("Use any picture — its path, e.g. ~/Pictures/holiday.jpg")
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
                        model: [{ id: "both", label: Tr.t("Both styles") }, { id: "light", label: Tr.t("Light style") }, { id: "dark", label: Tr.t("Dark style") }]
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

                SectionTitle { Layout.fillWidth: true; text: Tr.t("Look & feel") }
                // the accent: one of GNOME's nine (apps follow it too), or the wallpaper's
                Text { text: Tr.t("Accent colour"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
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
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Accent from wallpaper"); hint: Tr.t("the wallpaper's most vivid colour"); checked: page.d.accentFromWallpaper; onToggled: on => page.d.accentFromWallpaper = on }
                Text { text: Tr.t("Dark style"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "manual", label: Tr.t("By hand") }, { id: "sunset", label: Tr.t("Sunset to sunrise") }, { id: "custom", label: Tr.t("Set hours") }]
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
                    Text { text: Tr.t("From"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                    TextField { Layout.preferredWidth: 90; text: page.d.darkFrom; placeholder: "19:00"; onAccepted: if (/^\d\d?:\d\d$/.test(text.trim())) page.d.darkFrom = text.trim() }
                    Text { text: Tr.t("to"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                    TextField { Layout.preferredWidth: 90; text: page.d.darkTo; placeholder: "07:00"; onAccepted: if (/^\d\d?:\d\d$/.test(text.trim())) page.d.darkTo = text.trim() }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Always show scrollbars"); hint: Tr.t("off: they appear while scrolling"); checked: page.d.showScrollbars; onToggled: on => page.d.showScrollbars = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Blur"); checked: page.d.blur; onToggled: on => page.d.blur = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Reduce motion"); hint: Tr.t("no slides, fades or zoom"); checked: page.d.reduceMotion; onToggled: on => page.d.reduceMotion = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Adaptive brightness"); hint: Tr.t("ambient sensor if present, else time of day"); checked: page.d.adaptiveBrightness; onToggled: on => page.d.adaptiveBrightness = on; visible: Brightness.available }
                RowLayout {
                    Layout.fillWidth: true
                    visible: NightLight.available
                    Text { text: Tr.t("Night light"); color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; Layout.preferredWidth: 90 }
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
                    Text { text: Tr.t("Turns on"); color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; Layout.preferredWidth: 90 }
                    Repeater {
                        model: [{ id: "manual", label: Tr.t("By hand") }, { id: "sunset", label: Tr.t("Sunset to sunrise") }, { id: "custom", label: Tr.t("Set hours") }]
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
                    text: Tr.t("Sunset needs your location: set a city under Weather. Until then, the hours below are used.")
                    color: Theme.faint
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: NightLight.available && (page.d.nightLightSchedule === "custom" || (page.d.nightLightSchedule === "sunset" && !NightLight.located))
                    spacing: 8
                    Text { text: Tr.t("From"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                    TextField {
                        Layout.preferredWidth: 90
                        text: page.d.nightLightFrom
                        placeholder: "21:00"
                        onAccepted: if (/^\d\d?:\d\d$/.test(text.trim())) page.d.nightLightFrom = text.trim()
                    }
                    Text { text: Tr.t("to"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                    TextField {
                        Layout.preferredWidth: 90
                        text: page.d.nightLightTo
                        placeholder: "07:00"
                        onAccepted: if (/^\d\d?:\d\d$/.test(text.trim())) page.d.nightLightTo = text.trim()
                    }
                }

                SettingsLook { Layout.fillWidth: true; active: page.cat === "personal" }

                // ---- the sidebar's tiles: which, and in what order (after Android) -----
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Bar & dock") }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Network speed"); checked: page.d.showNetSpeed; onToggled: on => page.d.showNetSpeed = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("CPU and memory"); checked: page.d.showSysStats; onToggled: on => page.d.showSysStats = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("24-hour clock"); checked: page.d.use24h; onToggled: on => page.d.use24h = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Seconds"); checked: page.d.showSeconds; onToggled: on => page.d.showSeconds = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Date beside the clock"); checked: page.d.barDate; onToggled: on => page.d.barDate = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Battery percentage"); checked: page.d.barBatteryPercent; onToggled: on => page.d.barBatteryPercent = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Dock"); checked: page.d.dock; onToggled: on => page.d.dock = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Hide the dock"); hint: Tr.t("touch the bottom edge to show it"); checked: page.d.dockAutoHide; onToggled: on => page.d.dockAutoHide = on }
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: Tr.t("Dock icons"); color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; Layout.preferredWidth: 90 }
                    Repeater {
                        model: [{ v: 36, label: Tr.t("Small") }, { v: 44, label: Tr.t("Medium") }, { v: 56, label: Tr.t("Large") }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.dockIconSize === modelData.v
                            onClicked: page.d.dockIconSize = modelData.v
                        }
                    }
                }

                SectionTitle { Layout.fillWidth: true; text: Tr.t("Quick tiles") }
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

                SectionTitle { Layout.fillWidth: true; text: Tr.t("Hot corners") }
                Repeater {
                    model: [
                        { label: Tr.t("Top left"), key: "hotCornerTopLeft" }, { label: Tr.t("Top right"), key: "hotCornerTopRight" },
                        { label: Tr.t("Bottom left"), key: "hotCornerBottomLeft" }, { label: Tr.t("Bottom right"), key: "hotCornerBottomRight" }
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

                SwitchRow {
                    Layout.fillWidth: true
                    text: Tr.t("Also over fullscreen apps")
                    checked: page.d.hotCornersInFullscreen
                    onToggled: on => page.d.hotCornersInFullscreen = on
                }

                SectionTitle { Layout.fillWidth: true; text: Tr.t("Weather") }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Use my location"); hint: Tr.t("GeoClue2 — fills the coordinates below; off: type a city"); checked: page.d.useLocation; onToggled: on => { page.d.useLocation = on; if (on && Location.refresh) Location.refresh(); } }
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("City for the weather — off when empty (asks open-meteo.com)")
                    text: page.d.weatherCity
                    onAccepted: { page.d.weatherLat = 0; page.d.weatherLon = 0; page.d.weatherCity = text.trim(); }
                }

            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "notifications"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Notifications") }
                Text { text: Tr.t("Pop-ups appear"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "top-right", label: Tr.t("Top right") }, { id: "top-center", label: Tr.t("Top centre") }, { id: "bottom-right", label: Tr.t("Bottom right") }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.popupPosition === modelData.id
                            onClicked: page.d.popupPosition = modelData.id
                        }
                    }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Sound"); hint: Tr.t("a chime for each notification that pops up"); checked: page.d.notifSound; onToggled: on => page.d.notifSound = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Quiet hours"); hint: Tr.t("Do Not Disturb on a schedule"); checked: page.d.dndSchedule !== "manual"; onToggled: on => page.d.dndSchedule = on ? "custom" : "manual" }
                RowLayout {
                    Layout.fillWidth: true
                    visible: page.d.dndSchedule !== "manual"
                    spacing: 8
                    Text { text: Tr.t("From"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                    TextField { id: dndFrom; Layout.preferredWidth: 70; text: page.d.dndFrom; onAccepted: page.d.dndFrom = text }
                    Text { text: Tr.t("to"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                    TextField { id: dndTo; Layout.preferredWidth: 70; text: page.d.dndTo; onAccepted: page.d.dndTo = text }
                }
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
                                text: Tr.t("Pop-ups")
                                selected: !appRow.silent
                                onClicked: page.d.silentApps = appRow.silent ? Array.from(page.d.silentApps).filter(x => x !== appRow.modelData)
                                                                             : Array.from(page.d.silentApps).concat([appRow.modelData])
                            }
                            Choice {
                                text: Tr.t("Through Do Not Disturb")
                                selected: appRow.through
                                onClicked: page.d.dndAllowedApps = appRow.through ? Array.from(page.d.dndAllowedApps).filter(x => x !== appRow.modelData)
                                                                                  : Array.from(page.d.dndAllowedApps).concat([appRow.modelData])
                            }
                        }
                    }
                }
                Text { text: Tr.t("Show pop-ups for"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
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
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Quiet automatically") }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("While presenting"); hint: Tr.t("notifications wait while the screen is shared"); checked: page.d.quietWhileSharing; onToggled: on => page.d.quietWhileSharing = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("While something is fullscreen"); hint: Tr.t("films, slides, games — a game also gets the performance profile"); checked: page.d.quietWhileFullscreen; onToggled: on => page.d.quietWhileFullscreen = on }

            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "access"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Accessibility") }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Screen reader"); hint: Tr.t("Orca; the shell's own controls are labelled for it"); checked: page.d.screenReader; onToggled: on => page.d.screenReader = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Large text"); hint: Tr.t("the shell and apps, 125 %"); checked: page.d.largeText; onToggled: on => page.d.largeText = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("High contrast"); checked: page.d.highContrast; onToggled: on => page.d.highContrast = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Reduce motion"); hint: Tr.t("no opening, closing or scrolling animations"); checked: page.d.reduceMotion; onToggled: on => page.d.reduceMotion = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Reduce transparency"); hint: Tr.t("make cards opaque for readability"); checked: page.d.reduceTransparency; onToggled: on => page.d.reduceTransparency = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Mono audio"); checked: page.d.monoAudio; onToggled: on => page.d.monoAudio = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Flash for alerts"); hint: Tr.t("the screen edge flashes when a notification arrives"); checked: page.d.flashAlerts; onToggled: on => page.d.flashAlerts = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Speak notifications"); hint: Tr.t("the app and title, read aloud"); checked: page.d.speakNotifications; onToggled: on => page.d.speakNotifications = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Smart touch"); hint: Tr.t("a floating bubble that opens the Ring, for touchscreens"); checked: page.d.assistiveTouch; onToggled: on => page.d.assistiveTouch = on }

                Text { text: Tr.t("Read aloud speed"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "slow", label: Tr.t("Slow") }, { id: "normal", label: Tr.t("Normal") }, { id: "fast", label: Tr.t("Fast") }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.speechRate === modelData.id
                            onClicked: page.d.speechRate = modelData.id
                        }
                    }
                }
                Text { text: Tr.t("Captions and transcribe language"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "auto", label: Tr.t("Detect") }, { id: "en", label: Tr.t("English") }, { id: "mr", label: "मराठी" }, { id: "hi", label: "हिन्दी" }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.captionLanguage === modelData.id
                            onClicked: page.d.captionLanguage = modelData.id
                        }
                    }
                }

            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "input"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                // ---- screen keyboard languages: any xkb layout, plus the hand-made two
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Screen keyboard") }
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
                    placeholder: Tr.t("Add a layout — marathi, tamil, russian, arabic …")
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
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "time"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsDateLanguage { Layout.fillWidth: true; active: page.cat === "time" }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "apps"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Apps & files") }
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("Terminal for “Run in terminal” (foot)")
                    text: page.d.terminal
                    onAccepted: page.d.terminal = text.trim() || "foot"
                }
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("Screen recordings folder (empty: Videos/Recordings)")
                    text: page.d.recordingsDir
                    onAccepted: page.d.recordingsDir = text.trim()
                }

                SettingsDefaultApps { Layout.fillWidth: true; active: page.cat === "apps" }
                SettingsStartup { Layout.fillWidth: true; active: page.cat === "apps" }
                SettingsAppPermissions { Layout.fillWidth: true; active: page.cat === "apps" }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "account"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsAccount { Layout.fillWidth: true; active: page.cat === "account" }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "network"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsNetwork { Layout.fillWidth: true; active: page.cat === "network" }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "windows"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsWindows { Layout.fillWidth: true }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "displays"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsDisplays { Layout.fillWidth: true; active: page.cat === "displays" }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "sound"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsSound { Layout.fillWidth: true }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "search"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsSearch { Layout.fillWidth: true }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "privacy"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsPrivacy { Layout.fillWidth: true; active: page.cat === "privacy" }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "sharing"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsSharing { Layout.fillWidth: true; active: page.cat === "sharing" }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "printers"
        visible: active
        sourceComponent: Component {
            SettingsPrinters { active: true }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "backup"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsBackup { Layout.fillWidth: true; active: page.cat === "backup" }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "automations"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsAutomations { Layout.fillWidth: true; active: page.cat === "automations" }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "chronoa"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsChronoa { Layout.fillWidth: true }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "users"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsUsers { Layout.fillWidth: true; active: page.cat === "users" }
            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "power"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Battery & wellbeing") }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Battery saver at 20 %"); hint: Tr.t("power saver on battery, back when charging"); checked: page.d.autoPowerSaver; onToggled: on => page.d.autoPowerSaver = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Screen time"); hint: Tr.t("per-app focus time, kept on this machine"); checked: page.d.screenTime; onToggled: on => page.d.screenTime = on }
                // wellbeing: reminders on top of screen time, never a lock-out
                Text { visible: page.d.screenTime; text: Tr.t("Remind me to take a break"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                Flow {
                    visible: page.d.screenTime
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [0, 20, 30, 45, 60, 90]
                        Choice { required property int modelData; text: modelData ? Tr.t("every %1 min", modelData) : Tr.t("Never"); selected: page.d.breakEveryMinutes === modelData; onClicked: page.d.breakEveryMinutes = modelData }
                    }
                }
                Text { visible: page.d.screenTime; text: Tr.t("Daily screen time reminder"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                Flow {
                    visible: page.d.screenTime
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [0, 120, 240, 360, 480, 600]
                        Choice { required property int modelData; text: modelData ? Tr.t("%1 h", modelData / 60) : Tr.t("Off"); selected: page.d.screenLimitMinutes === modelData; onClicked: page.d.screenLimitMinutes = modelData }
                    }
                }

                SettingsPowerKeys { Layout.fillWidth: true; active: page.cat === "power" }
                SectionTitle { Layout.fillWidth: true; text: Tr.t("When idle") }
                Repeater {
                    model: [
                        { label: Tr.t("Lock after"), key: "lockAfter", options: [60, 120, 300, 600, 900, 0] },
                        { label: Tr.t("Screen off after"), key: "screenOffAfter", options: [120, 300, 600, 1800, 0] },
                        { label: Tr.t("Suspend after"), key: "suspendAfter", options: [900, 1800, 3600, 0] }
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
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Lock before suspend"); checked: page.d.lockBeforeSuspend; onToggled: on => page.d.lockBeforeSuspend = on }

            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "about"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsAbout { Layout.fillWidth: true; active: page.cat === "about" }
            }
        }
    }
}
