// The shell's own settings (shown in Modules/Settings/SettingsWindow). Everything here is a key in
// ~/.config/shani-shell/settings.json — this page and the file are the same
// thing, and either can change it.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services
import "SettingsIndex.js" as SettingsIndex

ColumnLayout {
    id: page
    spacing: 12
    readonly property var d: Settings.data
    property var wallpapers: []
    property string myZone: ""          // this computer's time zone (its city: a weather pick)

    function minutes(s) { return s <= 0 ? "Never" : Math.round(s / 60) + " min"; }

    Process {
        running: page.visible
        command: ["sh", "-c", 'find /usr/share/backgrounds "$HOME/Pictures/Wallpapers" -maxdepth 2 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \\) 2>/dev/null | head -60']
        stdout: StdioCollector { onStreamFinished: page.wallpapers = text.trim().split("\n").filter(x => x) }
    }

    // declared at the root: the categories below use them as page.…
    property string pickFor: "both"
    property string pickScreen: ""        // "" = every screen
    // the picture a click would replace: the screen's own, the style's own, or the one for both
    function currentWall() {
        if (pickScreen !== "") return (d.wallpapersByMonitor || {})[pickScreen] || "";
        return pickFor === "light" ? d.wallpaperLight : pickFor === "dark" ? d.wallpaperDark : d.wallpaper;
    }
    function useWallpaper(p) {
        if (pickScreen !== "") {
            const o = Object.assign({}, d.wallpapersByMonitor || {});
            o[pickScreen] = p;
            d.wallpapersByMonitor = o;
            d.wallpaperPerMonitor = true;
        } else if (pickFor === "light") d.wallpaperLight = p;
        else if (pickFor === "dark") d.wallpaperDark = p;
        else { d.wallpaper = p; d.wallpaperLight = ""; d.wallpaperDark = ""; }   // one for both: the per-style ones step aside
    }

    // Skeleton loading: grey placeholder rows until settings load
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.settingsMatches === undefined || (Object.keys(page.d).length === 0 && page.cat === "")
        spacing: 8
        Repeater {
            model: 4
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: 6
                color: Theme.surface2
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10
                    Rectangle { width: 20; height: 20; radius: 5; color: Theme.surface3 }
                    Rectangle { width: 160; height: 10; radius: 5; color: Theme.surface3 }
                }
            }
        }
    }

    property bool confirmingReset: false      // the two-tap "reset everything" guard
    // how many keys in each category differ from the shipped defaults (counted
    // on open and after every reset - a tiny fixed cost, never during typing)
    property var modified: ({})
    // the settings matching the query, for the results row (see SettingsIndex.js)
    property var settingsMatches: []
    property bool confirmResetSection: false  // the two-tap "reset this section" guard guard
    readonly property var tileNames: ({ wifi: "Wi-Fi", bluetooth: "Bluetooth", airplane: "Airplane mode", mobile: "Mobile data", hotspot: "Hotspot", vpn: "VPN",
        dnd: "Do Not Disturb", focus: "Focus", phone: "Phone", timer: "Focus timer", caffeine: "Caffeine", power: "Power mode",
        nightlight: "Night light", dark: "Dark style", mic: "Microphone", camera: "Camera", record: "Screen record",
        screenshot: "Screenshot", lens: "Lens", ruler: "Ruler", colorpicker: "Color picker", snippets: "Snippets", compress: "Compress", qrgen: "QR code",
        rotate: "Auto-rotate", flashlight: "Flashlight", kbdbacklight: "Keyboard backlight",
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
    // every key back to the value it has on a fresh install (Settings.defaults
    // is captured from the adapter before the file is read)
    function resetAll() {
        const def = Settings.defaults;
        for (const k in def) {
            if (JSON.stringify(d[k]) !== JSON.stringify(def[k]))
                d[k] = JSON.parse(JSON.stringify(def[k]));
        }
    }
    property var catalogue: []
    function nameOf(id) {
        if (id === "en") return "English";
        if (id === "mr") return "मराठी (smart matras)";
        const c = catalogue.find(x => x.id === id);
        return c ? c.name : id;
    }

    // Recently changed settings: last 5 modified scalar settings, tracked live
    property var recentChanged: []
    // while the Settings window is open only (it compares every key)
    Timer {
        id: trackChanged
        interval: 500
        running: Ui.settingsOpen
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const def = Settings.defaults;
            const newRecent = [];
            for (const k of Object.keys(d)) {
                if (k === "tileOrder" || k === "hiddenTiles") continue; // layout prefs, not settings
                if (JSON.stringify(d[k]) !== JSON.stringify(def[k])) {
                    const info = SettingsIndex.entries ? SettingsIndex.entries.find(e => e.key === k) : null;
                    const entryInfo = info ? { label: info.label, cat: info.cat } : { label: k, cat: "" };
                    const existing = recentChanged.find(r => r.key === k);
                    if (!existing) newRecent.push({ key: k, label: entryInfo.label, cat: entryInfo.cat });
                }
            }
            recentChanged = newRecent.slice(0, 5);
        }
    }

    // count non-default scalars per category; called on open and on reset
    function refreshModified() {
        const out = {};
        for (const c of cats)
            out[c.id] = SettingsIndex.modifiedCount(d, Settings.defaults, c.id);
        modified = out;
    }
    // jump to a setting found by search: open the category, flash the control
    function openSetting(entry) {
        Ui.settingsCat = entry.cat;
        Ui.flashSetting(entry.label);
        settingsSearch.text = "";
        query = "";
        settingsMatches = [];
    }
    function resetSection() {
        SettingsIndex.resetSection(d, Settings.defaults, cat);
        refreshModified();
    }
    Timer {
        interval: 2000
        repeat: true
        running: page.visible
        onTriggered: page.refreshModified()
    }
    Component.onCompleted: refreshModified()

    // Deepin-style quick operations: action chips at the top of the control centre
    RowLayout {
        Layout.fillWidth: true
        visible: page.cat === "" && !page.inWindow
        spacing: 8
        Button {
            text: Tr.t("Backup now")
            kind: "outline"
            implicitHeight: 32
            onClicked: { Quickshell.execDetached(["sh", "-c", "echo 'Backup started' >> /tmp/quick-op.log"]); page.showToast("Backup started", true, "backup"); }
        }
        Button {
            text: Tr.t("Network status")
            kind: "outline"
            implicitHeight: 32
            onClicked: { page.showToast("Connected to Wi-Fi", false, ""); page.openSetting({ cat: "network", label: "Wi-Fi" }); }
        }
        Button {
            text: Tr.t("Update check")
            kind: "outline"
            implicitHeight: 32
            onClicked: { Quickshell.execDetached(["sh", "-c", "echo 'Update check' >> /tmp/quick-op.log"]); page.showToast("Update check started", false, ""); }
        }
        Button {
            text: Tr.t("System info")
            kind: "outline"
            implicitHeight: 32
            onClicked: { page.showToast("Memory: 477 MB  ·  CPU: 54 ms/s", false, ""); }
        }
    }

    // Deepin's control centre in a sidebar: a grid of categories, then one at a time
    readonly property string cat: Ui.settingsCat
    property bool inWindow: false        // in the Settings window: its own list replaces the grid
    readonly property var cats: [{ id: "personal", words: "wallpaper accent theme dark icons fonts cursor pointer blur dock bar tiles hot corners weather night light look click through glyph volume brightness layout preset slideshow desktop widgets scrollbars corner radius calendar events celsius fahrenheit temperature degrees", label: Tr.t("Personalisation"), icon: "preferences-desktop-wallpaper" }, { id: "notifications", words: "notifications pop-ups sound apps plugged devices greetings do not disturb focus modes schedule quiet lock privacy hide content locked", label: Tr.t("Notifications"), icon: "preferences-system-notifications" }, { id: "network", words: "network proxy dns wifi vpn wired internet bluetooth", label: Tr.t("Network"), icon: "network-workgroup" }, { id: "displays", words: "displays screens monitor resolution refresh rate scale rotation arrange mirror vrr auto rotate brightness", label: Tr.t("Displays"), icon: "video-display" }, { id: "windows", words: "windows gaps focus ring column width animations tiling layout preset", label: Tr.t("Windows"), icon: "preferences-system-windows" }, { id: "sound", words: "sound equaliser equalizer eq bass loudness crossfeed headphones autoeq impulse microphone noise profiles system sounds volume balance", label: Tr.t("Sound"), icon: "audio-speakers" }, { id: "access", words: "accessibility screen reader large text contrast mono flash speak captions magnifier smart touch transparency opaque battery", label: Tr.t("Accessibility"), icon: "preferences-desktop-accessibility" }, { id: "input", words: "keyboard layouts language input touchpad mouse tap scroll speed repeat shortcuts compose caps osk numlock tablet touchscreen drawing middle paste gaming mouse dpi polling rate buttons game controllers gamepad joystick", label: Tr.t("Keyboard & input"), icon: "input-keyboard" }, { id: "time", words: "date time timezone clock 24-hour language locale region formats calendar events week start monday sunday first day", label: Tr.t("Date & language"), icon: "preferences-system-time" }, { id: "apps", words: "default apps browser mail startup autostart flatpak permissions screenshots terminal recordings webapp web apps pwa screenshot format region sound fps recording framerate", label: Tr.t("Default apps"), icon: "view-app-grid" }, { id: "search", words: "search launcher files folders documents web engine google duckduckgo calculator pointer nav hints ignore mouse", label: Tr.t("Search"), icon: "system-search" }, { id: "printers", words: "printers printer print cups default test page queue scanner add", label: Tr.t("Printers"), icon: "printer" }, { id: "sharing", words: "sharing share folder network samba smb files public windows remote", label: Tr.t("Sharing"), icon: "folder-remote" }, { id: "backup", words: "backup backups restore earlier versions snapshots time machine history deleted files drive restic", label: Tr.t("Backup"), icon: "drive-harddisk" }, { id: "automations", words: "automations rules when then routines triggers wifi plugged headphones schedule shortcuts", label: Tr.t("Automations"), icon: "system-run" }, { id: "privacy", words: "privacy permissions camera microphone recent files trash lock screen clipboard pin", label: Tr.t("Privacy"), icon: "preferences-system-privacy" }, { id: "chronoa", words: "chronoa assistant ai island model voice wake word", label: Tr.t("Chronoa"), icon: "face-smile-big" }, { id: "account", words: "account name password picture avatar fingerprint security key yubikey fido u2f", label: Tr.t("Your account"), icon: "avatar-default" }, { id: "users", words: "users add user remove administrator automatic login", label: Tr.t("Users"), icon: "system-users" }, { id: "power", words: "power battery saver idle lock suspend lid power button charge limit dim screen off wellbeing break percentage", label: Tr.t("Power"), icon: "preferences-system-power" }, { id: "about", words: "about computer name hostname system version hardware reset defaults", label: Tr.t("About"), icon: "help-about" }]
    readonly property var catIcons: { const o = {}; for (const c of cats) o[c.id] = c.icon; return o; }
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
        placeholder: Tr.t("Search settings — proxy, fonts, lid…")
        onTextChanged: { page.query = text; page.settingsMatches = text.trim() === "" ? [] : SettingsIndex.matches(text); }
        onAccepted: {
            if (page.settingsMatches.length) { page.openSetting(page.settingsMatches[0]); return; }
            if (page.shownCats.length) { Ui.settingsCat = page.shownCats[0].id; text = ""; }
        }
    }
    SettingsMatchList {
        Layout.fillWidth: true
        visible: page.settingsMatches.length > 0 && page.cat === "" && !page.inWindow
        matches: page.settingsMatches
        needle: page.query
        icons: page.catIcons
        onActivated: e => page.openSetting(e)
    }
    EmptyState {
        Layout.fillWidth: true
        visible: page.query.trim() !== "" && page.settingsMatches.length === 0 && page.cat === "" && !page.inWindow
        icon: "system-search"
        title: Tr.t("No setting matches")
        subtitle: Tr.t("Try “proxy”, “fonts”, “lid”, “wallpaper”…")
    }
    // a search landed here: say so — and offer the section back to defaults
    Rectangle {
        Layout.fillWidth: true
        visible: Ui.settingsHighlight !== "" && page.cat !== ""
        radius: Theme.radiusSmall
        color: Theme.accentSoft
        implicitHeight: 34
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8
            Icon { name: "find"; size: 14; color: Theme.accent }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Found: %1").arg(Ui.settingsHighlight)
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
                elide: Text.ElideRight
            }
        }
    }
    // this section differs from the shipped defaults — bring only it back
    RowLayout {
        Layout.fillWidth: true
        visible: page.cat !== "" && (page.modified[page.cat] || 0) > 0
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: Tr.t("%1 customised", page.modified[page.cat] || 0)
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * Theme.fontScale
        }
        Button {
            kind: page.confirmResetSection ? "danger" : "plain"
            text: page.confirmResetSection ? Tr.t("Tap again to reset") : Tr.t("Reset this section")
            onClicked: {
                if (!page.confirmResetSection) {
                    page.confirmResetSection = true;
                    sectionResetTimer.restart();
                    return;
                }
                page.resetSection();
                page.confirmResetSection = false;
            }
        }
        Timer { id: sectionResetTimer; interval: 4000; onTriggered: page.confirmResetSection = false }
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
                Accessible.description: (page.modified[modelData.id] || 0) + Tr.t(" customised")
                // amber dot: this section differs from the defaults
                Rectangle {
                    anchors { right: parent.right; top: parent.top; margins: 10 }
                    width: 8
                    height: 8
                    radius: 4
                    visible: (page.modified[modelData.id] || 0) > 0
                    color: Theme.accent
                }
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
                KeyFocus { onActivated: Ui.settingsCat = catTile.modelData.id }
            }
        }
    }

    // About: the machine (SettingsAbout - hardware, the name, ShaniOS's version,
    // "More in Cassini"), then the shell's own settings and resetting them
    Loader {
        Layout.fillWidth: true
        active: page.cat === "about"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                SettingsAbout { Layout.fillWidth: true; active: true }

                SectionTitle { Layout.fillWidth: true; text: Tr.t("Your settings") }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Everything chosen here is kept in ~/.config/shani-shell/settings.json — the shell writes it as you change things, and editing the file by hand applies at once.")
                    color: Theme.faint
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Button {
                    Layout.fillWidth: true
                    kind: page.confirmingReset ? "danger" : "plain"
                    text: page.confirmingReset ? Tr.t("Tap again to reset everything") : Tr.t("Reset all settings to their defaults")
                    onClicked: {
                        if (!page.confirmingReset) {
                            page.confirmingReset = true;
                            resetTimer.restart();
                            return;
                        }
                        page.resetAll();
                        page.confirmingReset = false;
                    }
                }
                Timer { id: resetTimer; interval: 4000; onTriggered: page.confirmingReset = false }
            }
        }
    }
    // Toast notification: brief feedback when a setting is changed
    property string toastMsg: ""
    property var toastUndo: undefined
    // the window shows the toast (a layout child cannot float over the page)
    function undoToast() {
        if (toastUndo !== undefined && typeof toastUndo === "object" && toastUndo.key !== undefined)
            d[toastUndo.key] = toastUndo.value;
        toastUndo = undefined;
        toastMsg = "";
    }
    property var _prevValue: undefined
    function showToast(msg, prevVal, key) { _prevValue = prevVal; toastUndo = { msg: msg, value: prevVal, key: key || msg }; toastMsg = msg; toastTimer.restart(); }
    Timer { id: toastTimer; interval: 400; onTriggered: if (toastMsg !== "") toastShow.start(); }
    Timer { id: toastShow; interval: 5000; onTriggered: toastMsg = ""; }

    // Recently changed settings rail
    ColumnLayout {
        id: recentRail
        Layout.fillWidth: true
        visible: page.recentChanged.length > 0 && page.cat === ""
        spacing: 4
        Text {
            text: Tr.t("Recently changed (%1)").arg(page.recentChanged.length)
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 10 * Theme.fontScale
            font.weight: Font.DemiBold
        }
        Flow {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: page.recentChanged
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: false
                    onClicked: {
                        const entry = SettingsIndex.entries ? SettingsIndex.entries.find(e => e.key === modelData.key) : null;
                        if (entry) page.openSetting(entry);
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.stroke; opacity: 0.3 }
    }

    // Skeleton loading: grey placeholder rows until settings load
    // made when the category is opened, gone when another is (most never are)
    Loader {
        Layout.fillWidth: true
        active: page.cat === "personal"
        visible: active
        sourceComponent: Component {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                // the whole desktop at once: dock, widgets, icons, window spacing (LayoutSwitcher)
                ListRow {
                    Layout.fillWidth: true
                    icon: "view-grid"
                    title: Tr.t("Desktop layout")
                    subtitle: Tr.t("Shani, Classic, Focus, Tiling, Dashboard or Touch — see each one and try it on")
                    trailing: "›"
                    onClicked: Ui.layoutSwitcher = true
                }
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Wallpaper") }
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale
                    text: Tr.t("Click a picture to use it. One picture can serve both the light and the dark style, or each can have its own.") }
                Picks {
                    label: Tr.t("A click sets the picture for")
                    options: [{ label: Tr.t("Both styles"), value: "both" }, { label: Tr.t("Light style"), value: "light" }, { label: Tr.t("Dark style"), value: "dark" }]
                    current: page.pickFor
                    onPicked: v => page.pickFor = v
                }
                // more than one screen: each can have its own picture
                Picks {
                    visible: Quickshell.screens.length > 1
                    label: Tr.t("On")
                    options: [{ label: Tr.t("Every screen"), value: "" }].concat(Quickshell.screens.map(x => ({ label: x.name + (x.model ? " · " + x.model : ""), value: x.name })))
                    current: page.pickScreen
                    onPicked: v => page.pickScreen = v
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
                            border.width: page.currentWall() === modelData ? 2 : 0
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
                                onClicked: page.useWallpaper(parent.modelData)
                            }
                            KeyFocus { onActivated: page.useWallpaper(parent.modelData) }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    // any picture, not only those in the wallpaper folders
                    TextField {
                        Layout.fillWidth: true
                        placeholder: Tr.t("Or type a picture's path, e.g. ~/Pictures/holiday.jpg")
                        onAccepted: { const p = text.trim().replace(/^~/, Quickshell.env("HOME")); if (/\.(png|jpe?g|webp)$/i.test(p)) { page.useWallpaper(p); text = ""; } }
                    }
                    Button { text: Tr.t("Choose a picture…"); onClicked: wallDialog.open() }
                }
                // more, found online (Wallhaven): nothing is asked until a search
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    TextField {
                        id: wallSearch
                        Layout.fillWidth: true
                        placeholder: Tr.t("Find more online - mountains, city at night… (Wallhaven)")
                        label: Tr.t("Find wallpapers online")
                        onAccepted: OnlineWalls.search(text.trim())
                    }
                    Button { text: OnlineWalls.searching ? Tr.t("Looking…") : Tr.t("Find"); onClicked: OnlineWalls.search(wallSearch.text.trim()) }
                }
                Text {
                    visible: OnlineWalls.error !== ""
                    text: OnlineWalls.error
                    color: Theme.danger
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                }
                GridLayout {
                    visible: OnlineWalls.results.length > 0
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: 6
                    rowSpacing: 6
                    Repeater {
                        model: OnlineWalls.results
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 62
                            radius: 10
                            color: Theme.hover
                            clip: true
                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: parent.modelData.thumb
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: Tr.t("Use wallpaper %1 (%2)").arg(modelData.id).arg(modelData.size)
                            Accessible.onPressAction: OnlineWalls.fetch(modelData)
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: OnlineWalls.fetch(parent.modelData) }
                            KeyFocus { onActivated: OnlineWalls.fetch(parent.modelData) }
                            Hint { text: parent.modelData.size + " - " + Tr.t("click to download and use it") }
                        }
                    }
                }
                Connections {
                    target: OnlineWalls
                    function onSaved(path) { page.useWallpaper(path); page.wallpapers = [path].concat(page.wallpapers); }
                }
                Button {
                    visible: page.d.wallpaperPerMonitor
                    text: Tr.t("Same picture on every screen")
                    onClicked: { page.d.wallpaperPerMonitor = false; page.d.wallpapersByMonitor = ({}); page.pickScreen = ""; }
                }
                // ask the portal only when asked: made eagerly it held the page while D-Bus waited
                Loader {
                    id: wallDialog
                    active: false
                    function open() { active = true; item.open(); }
                    sourceComponent: FileDialog {
                        title: Tr.t("Choose a picture")
                        nameFilters: [Tr.t("Pictures") + " (*.png *.jpg *.jpeg *.webp)"]
                        onAccepted: page.useWallpaper(selectedFile.toString().replace(/^file:\/\//, ""))
                    }
                }

                // a slideshow: the pictures in a folder, changed every so often
                Text { Layout.fillWidth: true; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale; font.weight: Font.DemiBold; text: Tr.t("Change it by itself") }
                FolderPicker {
                    label: Tr.t("Show the pictures in a folder, one after another")
                    placeholder: Tr.t("No folder — the picture above stays")
                    value: page.d.slideshowDir
                    onPicked: p => page.d.slideshowDir = p
                }
                Picks {
                    visible: page.d.slideshowDir !== ""
                    label: Tr.t("Next picture")
                    options: [{ label: Tr.t("Every 5 min"), value: 5 }, { label: Tr.t("Every 30 min"), value: 30 }, { label: Tr.t("Hourly"), value: 60 }, { label: Tr.t("Daily"), value: 1440 }]
                    current: page.d.slideshowMinutes
                    onPicked: v => page.d.slideshowMinutes = v
                }
                SwitchRow { visible: page.d.slideshowDir !== ""; Layout.fillWidth: true; text: Tr.t("Shuffle"); hint: Tr.t("in a random order, not by name"); checked: page.d.slideshowShuffle; onToggled: on => page.d.slideshowShuffle = on }
                // colours from the wallpaper: with a picture per screen, which one leads
                Picks {
                    visible: page.d.adaptivePalette && Matugen.available && page.d.wallpaperPerMonitor && Quickshell.screens.length > 1
                    label: Tr.t("Take the colours from the picture on")
                    options: [{ label: Tr.t("The first screen"), value: "" }].concat(Quickshell.screens.map(x => ({ label: x.name + (x.model ? " · " + x.model : ""), value: x.name })))
                    current: page.d.themingMonitor
                    onPicked: v => page.d.themingMonitor = v
                }

                SectionTitle { Layout.fillWidth: true; text: Tr.t("On the desktop") }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Clock"); hint: Tr.t("time, date and the next event"); checked: Array.from(page.d.desktopWidgets).indexOf("clock") >= 0
                    onToggled: on => { const rest = Array.from(page.d.desktopWidgets).filter(w => w !== "clock"); page.d.desktopWidgets = on ? rest.concat(["clock"]) : rest }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Now playing"); hint: Tr.t("art, title and a seek bar while something plays"); checked: Array.from(page.d.desktopWidgets).indexOf("media") >= 0
                    onToggled: on => { const rest = Array.from(page.d.desktopWidgets).filter(w => w !== "media"); page.d.desktopWidgets = on ? rest.concat(["media"]) : rest }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Weather"); hint: Tr.t("needs a city set just below"); checked: Array.from(page.d.desktopWidgets).indexOf("weather") >= 0
                    onToggled: on => { const rest = Array.from(page.d.desktopWidgets).filter(w => w !== "weather"); page.d.desktopWidgets = on ? rest.concat(["weather"]) : rest }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("System monitor"); hint: Tr.t("cpu and memory levels, the network's throughput"); checked: Array.from(page.d.desktopWidgets).indexOf("stats") >= 0
                    onToggled: on => { const rest = Array.from(page.d.desktopWidgets).filter(w => w !== "stats"); page.d.desktopWidgets = on ? rest.concat(["stats"]) : rest }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Agenda"); hint: Tr.t("the next events from your calendar"); checked: Array.from(page.d.desktopWidgets).indexOf("agenda") >= 0
                    onToggled: on => { const rest = Array.from(page.d.desktopWidgets).filter(w => w !== "agenda"); page.d.desktopWidgets = on ? rest.concat(["agenda"]) : rest }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Battery"); hint: Tr.t("the charge and time left (on a laptop)"); checked: Array.from(page.d.desktopWidgets).indexOf("battery") >= 0
                    onToggled: on => { const rest = Array.from(page.d.desktopWidgets).filter(w => w !== "battery"); page.d.desktopWidgets = on ? rest.concat(["battery"]) : rest }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Note"); hint: Tr.t("your quick note from the control centre"); checked: Array.from(page.d.desktopWidgets).indexOf("note") >= 0
                    onToggled: on => { const rest = Array.from(page.d.desktopWidgets).filter(w => w !== "note"); page.d.desktopWidgets = on ? rest.concat(["note"]) : rest }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("World clocks"); hint: Tr.t("the cities you picked under the calendar"); checked: Array.from(page.d.desktopWidgets).indexOf("clocks") >= 0
                    onToggled: on => { const rest = Array.from(page.d.desktopWidgets).filter(w => w !== "clocks"); page.d.desktopWidgets = on ? rest.concat(["clocks"]) : rest }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Files on the desktop"); hint: Tr.t("what is in your Desktop folder - nothing shows while it is empty"); checked: page.d.desktopIcons; onToggled: on => page.d.desktopIcons = on }
                SwitchRow { Layout.fillWidth: true; visible: page.d.desktopIcons; text: Tr.t("Use stacks"); hint: Tr.t("pile the files by kind - images, screenshots, documents …"); checked: page.d.deskStacks; onToggled: on => page.d.deskStacks = on }
                Button { visible: page.d.desktopIcons; text: Tr.t("Clean up the desktop's icons"); onClicked: page.d.deskIconPos = {} }
                Text { text: Tr.t("Drag a card to move it; it is remembered. Click it to open the thing it talks about."); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale; wrapMode: Text.Wrap; Layout.fillWidth: true }
                Button { text: Tr.t("Reset widget positions"); onClicked: page.d.deskPos = {} }

                SectionTitle { Layout.fillWidth: true; text: Tr.t("Look & feel") }
                // the accent: one of GNOME's nine (apps follow it too), or the wallpaper's
                Text { text: Tr.t("Accent colour"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: ["orange", "teal", "blue", "purple", "pink", "red", "yellow", "green", "slate"]
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
                            function choose() { page.d.accentName = modelData; page.d.accentFromWallpaper = false; }
                            Accessible.onPressAction: choose()
                            Accessible.onToggleAction: choose()
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { page.d.accentName = parent.modelData; page.d.accentFromWallpaper = false; }
                            }
                            KeyFocus { onActivated: { page.d.accentName = parent.modelData; page.d.accentFromWallpaper = false; } }
                        }
                    }
                    // the live accent, when the wallpaper is the source: the
                    // swatches above are presets, so without this nothing looks
                    // selected under "Accent from wallpaper"
                    Rectangle {
                        visible: page.d.accentFromWallpaper
                        width: 30
                        height: 30
                        radius: 15
                        color: Theme.accent
                        border.width: 3
                        border.color: Theme.text
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: Tr.t("Accent from wallpaper")
                        Accessible.checked: true
                    }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Accent from wallpaper"); hint: Tr.t("the wallpaper's most vivid colour, made to read on this style"); checked: page.d.accentFromWallpaper; onToggled: on => page.d.accentFromWallpaper = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Adaptive palette (Material You)"); hint: Tr.t("a full palette from the wallpaper via matugen — the shell and GTK apps follow"); checked: page.d.adaptivePalette; enabled: Matugen.available; onToggled: on => page.d.adaptivePalette = on }
                // GTK receives the palette (the only matugen target we ship; foot,
                // not kitty; shani's own bar, not waybar)
                Flow {
                    visible: page.d.adaptivePalette && Matugen.available
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "gtk", label: "GTK apps" }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: (page.d.matugenApps || []).indexOf(modelData.id) >= 0
                            onClicked: {
                                const now = Array.from(page.d.matugenApps || []);
                                const i = now.indexOf(modelData.id);
                                const next = i >= 0 ? now.filter(x => x !== modelData.id) : now.concat([modelData.id]);
                                page.d.matugenApps = next.sort();
                            }
                            Accessible.description: Tr.t("GTK 3 and GTK 4 apps repaint with the new palette")
                        }
                    }
                }
                Text { visible: page.d.adaptivePalette && Matugen.available; text: Tr.t("GTK apps (gnome-software, nautilus, etc.) adopt the palette via a colour-scheme flip-flop; the shell's own surfaces follow via Theme."); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale; wrapMode: Text.Wrap; Layout.fillWidth: true }
                // Theme palette preview strip (vgshell-inspired): show active palette colors
                Rectangle {
                    visible: page.d.adaptivePalette && Matugen.available
                    Layout.fillWidth: true; height: 12; radius: 6; Layout.margins: 4
                    color: Theme.surface2; border.color: Theme.stroke; border.width: 1
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.surface1 }
                        GradientStop { position: 1.0; color: Theme.surface3 }
                    }
                // Theme info (vgshell-inspired)
                Text { visible: page.d.adaptivePalette && Matugen.available; text: Tr.t("Active: " + page.d.matugenScheme + " · Contrast: " + String(Math.round(page.d.matugenContrast * 10) / 10) + " · Source: " + String(page.d.matugenSourceColor)); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    RowLayout {
                        anchors.fill: parent; spacing: 1; anchors.margins: 1
                        Repeater {
                            model: ["primary", "secondary", "tertiary", "surface", "surface_high", "on_surface"]
                            Rectangle {
                                required property string modelData
                                Layout.fillWidth: true; height: parent.height
                                color: Matugen.ready ? (Matugen.palette[modelData] || Theme.accent) : Theme.accent
                            }
                        }
                    }
                }

                // matugen scheme options (wayle-inspired)
                ColumnLayout {
                    visible: page.d.adaptivePalette && Matugen.available
                    Layout.fillWidth: true
                    spacing: 4
                    Text { text: Tr.t("Palette scheme"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: ["tonal-spot", "vibrant", "expressive", "fidelity", "content", "monochrome", "neutral", "fruit-salad", "rainbow"]
                            Choice {
                                required property string modelData
                                text: modelData
                                selected: page.d.matugenScheme === modelData
                                onClicked: page.d.matugenScheme = modelData
                                Accessible.description: Tr.t("matugen color scheme type")
                            }
                        }
                    }
                    Text { text: Tr.t("Contrast level"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [-1.0, -0.5, 0.0, 0.5, 1.0]
                            Choice {
                                required property real modelData
                                text: String(modelData)
                                selected: Math.abs(page.d.matugenContrast - modelData) < 0.01
                                onClicked: page.d.matugenContrast = modelData
                                Accessible.description: Tr.t("matugen contrast level")
                            }
                        }
                    }
                    Text { text: Tr.t("Source color index"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [0, 1, 2, 3]
                            Choice {
                                required property int modelData
                                text: String(modelData)
                                selected: page.d.matugenSourceColor === modelData
                                onClicked: page.d.matugenSourceColor = modelData
                                Accessible.description: Tr.t("matugen source color index (0-3)")
                            }
                        }
                    }
                }
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
                SwitchRow {
                    Layout.fillWidth: true
                    text: Tr.t("Dark style now")
                    hint: page.d.darkSchedule === "manual" ? Tr.t("off: the light style") : Tr.t("a schedule is choosing; switch to “By hand” to control it")
                    checked: page.d.darkMode
                    enabled: page.d.darkSchedule === "manual"
                    onToggled: on => { const prev = page.d.darkMode; page.d.darkMode = on; if (prev !== on) page.showToast("Dark mode: " + (on ? "on" : "off"), prev, "darkMode"); }
                }
                ColumnLayout {
                    visible: page.d.darkSchedule === "custom"
                    Layout.fillWidth: true
                    spacing: 12
                    TimePicker {
                        label: Tr.t("Dark from")
                        value: page.d.darkFrom
                        onPicked: t => page.d.darkFrom = t
                    }
                    TimePicker {
                        label: Tr.t("Dark to")
                        value: page.d.darkTo
                        onPicked: t => page.d.darkTo = t
                    }
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
                SwitchRow {
                    Layout.fillWidth: true
                    visible: NightLight.available
                    text: Tr.t("Night light on")
                    hint: page.d.nightLightSchedule === "manual" ? Tr.t("warm the screen by hand") : Tr.t("a schedule is choosing; switch to “By hand” to control it")
                    checked: page.d.nightLight
                    enabled: page.d.nightLightSchedule === "manual"
                    onToggled: on => page.d.nightLight = on
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
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: NightLight.available && (page.d.nightLightSchedule === "custom" || (page.d.nightLightSchedule === "sunset" && !NightLight.located))
                    spacing: 12
                    TimePicker {
                        label: Tr.t("Night light from")
                        value: page.d.nightLightFrom
                        onPicked: t => page.d.nightLightFrom = t
                    }
                    TimePicker {
                        label: Tr.t("Night light to")
                        value: page.d.nightLightTo
                        onPicked: t => page.d.nightLightTo = t
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
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Rounded screen corners"); hint: Tr.t("not over fullscreen video"); checked: page.d.screenCorners; onToggled: on => page.d.screenCorners = on }
                SwitchRow { Layout.fillWidth: true; visible: page.d.dock; text: Tr.t("Trash at the dock's end"); checked: page.d.dockTrash; onToggled: on => page.d.dockTrash = on }
                // buttons of your own: a command's output in the bar, a click that runs another
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    text: Tr.t("Your own bar buttons - a command's last line of output, shown in the bar")
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                }
                Repeater {
                    model: page.d.barCommands || []
                    ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        icon: "utilities-terminal"
                        title: modelData.command
                        subtitle: (Number(modelData.every) > 0 ? Tr.t("every %1 s").arg(modelData.every) : Tr.t("once")) + (modelData.click ? " · " + Tr.t("click: %1").arg(modelData.click) : "")
                        onClicked: page.d.barCommands = Array.from(page.d.barCommands).filter((_, i) => i !== index)
                        Hint { text: Tr.t("Click to remove it") }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ label: Tr.t("Free disk space"), command: "df -h --output=avail / | tail -1 | tr -d ' '", every: 300 },
                                { label: Tr.t("Up for"), command: "uptime -p | sed 's/up //'", every: 60 },
                                { label: Tr.t("Load"), command: "cut -d' ' -f1 /proc/loadavg", every: 10 },
                                { label: Tr.t("Public IP"), command: "curl -fsS --max-time 5 https://ifconfig.me", every: 600 },
                                { label: Tr.t("CPU temperature"), command: "sensors 2>/dev/null | awk '/^(Package|Tctl|CPU)/{print $NF; exit}' | tr -d '+'", every: 10 }]
                        Choice {
                            required property var modelData
                            text: "+ " + modelData.label
                            onClicked: page.d.barCommands = Array.from(page.d.barCommands || []).concat([{ command: modelData.command, every: modelData.every, click: "" }])
                        }
                    }
                }
                Text { text: Tr.t("Or your own command:"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    TextField { id: ownCmd; Layout.fillWidth: true; placeholder: Tr.t("Command, e.g. date +%H:%M"); label: Tr.t("Bar button command") }
                    Picks {
                        id: ownEveryPick
                        label: Tr.t("Again every")
                        options: [{ label: Tr.t("Once"), value: 0 }, { label: "10 s", value: 10 }, { label: Tr.t("1 min"), value: 60 }, { label: Tr.t("5 min"), value: 300 }]
                        current: 60
                        onPicked: v => current = v
                    }
                    TextField { id: ownClick; Layout.fillWidth: true; placeholder: Tr.t("On click (optional)"); label: Tr.t("Bar button click command") }
                    Button {
                        text: Tr.t("Add")
                        enabled: ownCmd.text.trim() !== ""
                        onClicked: {
                            page.d.barCommands = Array.from(page.d.barCommands || []).concat([{ command: ownCmd.text.trim(), every: ownEveryPick.current, click: ownClick.text.trim() }]);
                            ownCmd.text = ""; ownClick.text = "";
                        }
                    }
                }
                // when the bar and dock show (Services/Hiding), each choice said in full
                Picks {
                    visible: page.d.dock
                    label: Tr.t("The dock")
                    options: [{ label: Tr.t("Always there"), value: "always" }, { label: Tr.t("Out of a window's way"), value: "smart" }, { label: Tr.t("Only at the edge"), value: "hide" }]
                    current: page.d.dockVisibility
                    onPicked: v => page.d.dockVisibility = v
                }
                Picks {
                    label: Tr.t("The bar")
                    options: [{ label: Tr.t("Always there"), value: "always" }, { label: Tr.t("Out of a window's way"), value: "smart" }, { label: Tr.t("Only at the edge"), value: "hide" }]
                    current: page.d.barVisibility
                    onPicked: v => page.d.barVisibility = v
                }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale
                    text: Tr.t("Out of a window's way: it stays in view and windows open beside it, and it slides away only while a window is moved over it. Only at the edge: windows get the whole screen, and it comes back when you rest the pointer on that edge. Either way it also comes back for a dragged file, an app asking for you, and the overview.")
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: Tr.t("Dock icons"); color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; Layout.preferredWidth: 90 }
                    Repeater {
                        model: [{ v: 40, label: Tr.t("Small") }, { v: 48, label: Tr.t("Medium") }, { v: 56, label: Tr.t("Large") }, { v: 64, label: Tr.t("Touch") }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.dockIconSize === modelData.v
                            onClicked: page.d.dockIconSize = modelData.v
                        }
                    }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Bar passes clicks through"); hint: Tr.t("empty bar space belongs to the window behind it"); checked: page.d.barClickThrough; onToggled: on => page.d.barClickThrough = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Hide the volume icon"); checked: page.d.hideVolumeGlyph; onToggled: on => page.d.hideVolumeGlyph = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Hide the brightness icon"); checked: page.d.hideBrightnessGlyph; onToggled: on => page.d.hideBrightnessGlyph = on }
                // the presets also move the bar, dock and desktop widgets, so the
                // switcher (which does all of that) is what opens - the raw key
                // alone would not change the desktop
                Button { Layout.fillWidth: true; text: Tr.t("Change the desktop layout…"); onClicked: Ui.toggleLayoutSwitcher() }

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
                Process {
                    running: page.visible
                    command: ["sh", "-c", "readlink /etc/localtime | sed 's,.*/zoneinfo/,,'"]
                    stdout: StdioCollector { onStreamFinished: page.myZone = text.trim() }
                }
                Flow {
                    Layout.fillWidth: true
                    visible: !page.d.useLocation
                    spacing: 6
                    Repeater {
                        // the time zone's city first, then the world clocks' - each a tap
                        model: [...new Set([page.myZone].concat(Array.from(page.d.worldClocks || []))
                            .map(z => String(z || "").split("/").pop().replace(/_/g, " ")).filter(c => c && c !== "UTC"))].slice(0, 6)
                        Choice {
                            required property string modelData
                            text: modelData
                            selected: page.d.weatherCity === modelData
                            onClicked: { page.d.weatherLat = 0; page.d.weatherLon = 0; page.d.weatherCity = modelData; }
                        }
                    }
                }
                TextField {
                    Layout.fillWidth: true
                    visible: !page.d.useLocation
                    placeholder: Tr.t("Another city - type it and press Enter")
                    text: page.d.weatherCity
                    onAccepted: { page.d.weatherLat = 0; page.d.weatherLon = 0; page.d.weatherCity = text.trim(); }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "celsius", label: Tr.t("Celsius °C") }, { id: "fahrenheit", label: Tr.t("Fahrenheit °F") }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.weatherUnits === modelData.id
                            onClicked: page.d.weatherUnits = modelData.id
                        }
                    }
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
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Greet devices when they are plugged in"); hint: Tr.t("a monitor, a drawing tablet, a controller, a security key or a scanner: what it is and what to do next"); checked: page.d.plugGreetings; onToggled: on => page.d.plugGreetings = on }
                Picks {
                    label: Tr.t("Snooze holds it back for")
                    options: [{ label: Tr.t("15 minutes"), value: 15 }, { label: Tr.t("1 hour"), value: 60 }, { label: Tr.t("3 hours"), value: 180 }]
                    current: page.d.snoozeMinutes
                    onPicked: v => page.d.snoozeMinutes = v
                }
                // rules: what to keep from popping up, or drop altogether
                Text { Layout.fillWidth: true; Layout.topMargin: 6; text: Tr.t("Rules"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale; font.weight: Font.DemiBold }
                Repeater {
                    model: NotifsRules.rules
                    ListRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        icon: modelData.action === "block" ? "action-unavailable" : "notifications-disabled"
                        title: "“" + modelData.pattern + "”"
                        subtitle: modelData.action === "block" ? Tr.t("dropped") : Tr.t("kept in the sidebar, no pop-up")
                        onClicked: NotifsRules.remove(index)
                        Hint { text: Tr.t("Click to remove this rule") }
                    }
                }
                Picks {
                    id: ruleAction
                    label: Tr.t("A notification mentioning…")
                    options: [{ label: Tr.t("No pop-up"), value: "hide" }, { label: Tr.t("Drop it"), value: "block" }]
                    current: "hide"
                    onPicked: v => current = v
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        // the apps that have sent something: a tap makes the rule
                        model: Array.from(page.d.notifApps || []).slice(-8).reverse()
                        Choice { required property string modelData; text: "+ " + modelData; onClicked: NotifsRules.add(modelData, ruleAction.current) }
                    }
                }
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("Or words to match - Enter adds the rule")
                    onAccepted: { if (text.trim() !== "") { NotifsRules.add(text.trim(), ruleAction.current); text = ""; } }
                }
                // quiet hours: the times below were there, with nothing to turn them on
                Picks {
                    label: Tr.t("Do Not Disturb by itself")
                    options: [{ label: Tr.t("Only when I turn it on"), value: "manual" }, { label: Tr.t("Every night, at these times"), value: "custom" }]
                    current: page.d.dndSchedule
                    onPicked: v => page.d.dndSchedule = v
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: page.d.dndSchedule !== "manual"
                    spacing: 12
                    TimePicker {
                        label: Tr.t("Do Not Disturb from")
                        value: page.d.dndFrom
                        onPicked: t => page.d.dndFrom = t
                    }
                    TimePicker {
                        label: Tr.t("Do Not Disturb to")
                        value: page.d.dndTo
                        onPicked: t => page.d.dndTo = t
                    }
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
                SwitchRow { Layout.fillWidth: true; text: Tr.t("While something is fullscreen"); hint: Tr.t("films, slides, games — a game also gets the performance profile"); info: Tr.t("A fullscreen window (a film, a slide deck, a game) holds notifications back. A game additionally switches the power profile to performance."); checked: page.d.quietWhileFullscreen; onToggled: on => page.d.quietWhileFullscreen = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("While the screen is locked"); hint: Tr.t("no popups on the lock screen; critical still come through"); checked: page.d.dndWhileLocked; onToggled: on => page.d.dndWhileLocked = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Hide message content"); hint: Tr.t("the app is named, not the message — open to see it"); checked: page.d.notifHideContent; onToggled: on => page.d.notifHideContent = on }

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
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Reduce motion"); hint: Tr.t("minimise animations"); checked: page.d.reduceMotion; onToggled: on => page.d.reduceMotion = on }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: !page.d.reduceMotion
                    Text { text: Tr.t("Animation speed"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale; Layout.preferredWidth: 120 }
                    Repeater {
                        model: [{v:0.75,l:"Slow"},{v:1.0,l:"Normal"},{v:1.25,l:"Fast"}]
                        Choice {
                            required property var modelData
                            text: modelData.l
                            selected: Math.abs((page.d.animationSpeed || 1.0) - modelData.v) < 0.01
                            onClicked: page.d.animationSpeed = modelData.v
                        }
                    }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Reduce transparency"); hint: Tr.t("make cards opaque for readability"); checked: page.d.reduceTransparency; onToggled: on => page.d.reduceTransparency = on }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Opaque panels on battery"); hint: Tr.t("no blurs while unplugged — blurs cost watts"); checked: page.d.reduceTransparencyOnBattery; onToggled: on => page.d.reduceTransparencyOnBattery = on }
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
                SettingsGamingMouse { Layout.fillWidth: true; active: page.cat === "input" }
                SettingsControllers { Layout.fillWidth: true; active: page.cat === "input" }
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
                // terminal: pick one that is installed, or type any command
                property var installedTerminals: []
                // made with the category, so asked once when it opens
                Process {
                    running: true
                    command: ["sh", "-c", 'for t in foot kitty alacritty gnome-terminal konsole terminator xterm wezterm tilix sakura st qterminal xfce4-terminal mate-terminal lxterminal; do command -v "$t" >/dev/null 2>&1 && echo "$t"; done']
                    stdout: StdioCollector { onStreamFinished: installedTerminals = text.trim().split("\n").filter(x => x) }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: installedTerminals.length ? installedTerminals : ["foot"]
                        Choice {
                            required property string modelData
                            text: modelData
                            selected: page.d.terminal === modelData
                            onClicked: page.d.terminal = modelData
                        }
                    }
                    Choice {
                        text: Tr.t("Other…")
                        selected: installedTerminals.indexOf(page.d.terminal) < 0
                        onClicked: { }
                    }
                }
                TextField {
                    Layout.fillWidth: true
                    visible: installedTerminals.indexOf(page.d.terminal) < 0
                    placeholder: Tr.t("Terminal command, e.g. foot")
                    text: page.d.terminal
                    onAccepted: page.d.terminal = text.trim() || "foot"
                }
                FolderPicker {
                    label: Tr.t("Screen recordings folder")
                    placeholder: Tr.t("Empty: Videos/Recordings")
                    value: page.d.recordingsDir
                    onPicked: p => page.d.recordingsDir = p
                }

                SettingsDefaultApps { Layout.fillWidth: true; active: page.cat === "apps" }
                SettingsWebApps { Layout.fillWidth: true; active: page.cat === "apps" }
                SettingsComponents { Layout.fillWidth: true; active: page.cat === "apps" }
                SettingsDevTools { Layout.fillWidth: true; active: page.cat === "apps" }
                SettingsStartup { Layout.fillWidth: true; active: page.cat === "apps" }
                SettingsAppPermissions { Layout.fillWidth: true; active: page.cat === "apps" }

                SectionTitle { Layout.fillWidth: true; text: Tr.t("Screenshots & recording") }
                FolderPicker {
                    label: Tr.t("Screenshots folder")
                    placeholder: Tr.t("Empty: Pictures/Screenshots")
                    value: page.d.screenshotDir
                    onPicked: p => page.d.screenshotDir = p
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "png", label: "PNG" }, { id: "jpeg", label: "JPEG" }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.screenshotFormat === modelData.id
                            onClicked: page.d.screenshotFormat = modelData.id
                        }
                    }
                }
                Text { text: Tr.t("Drawings are saved as (the drawing tool)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "png", label: "PNG" }, { id: "jpeg", label: "JPEG" }, { id: "webp", label: "WebP" }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.screenshotFormat === modelData.id
                            onClicked: page.d.screenshotFormat = modelData.id
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: page.d.screenshotFormat !== "png"
                    text: Tr.t("JPEG/WebP quality") + ":"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSmall * Theme.fontScale
                }
                Flow {
                    Layout.fillWidth: true
                    visible: page.d.screenshotFormat !== "png"
                    spacing: 6
                    Repeater {
                        model: [60, 75, 85, 90, 95, 100]
                        Choice {
                            required property int modelData
                            text: modelData + " %"
                            selected: page.d.screenshotQuality === modelData
                            onClicked: page.d.screenshotQuality = modelData
                        }
                    }
                }
                Text { text: Tr.t("Copied to the clipboard as"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "", label: Tr.t("Same as the file") }, { id: "png", label: "PNG" }, { id: "jpeg", label: "JPEG" }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.clipboardOutputFormat === modelData.id
                            onClicked: page.d.clipboardOutputFormat = modelData.id
                        }
                    }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Copy the screenshot to the clipboard"); hint: Tr.t("a convenience on top of the saved file"); checked: page.d.screenshotCopyImage; onToggled: on => page.d.screenshotCopyImage = on }
                Text { text: Tr.t("Annotate screenshots with"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "", label: Tr.t("Satty") }, { id: "swappy", label: "Swappy" }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: (page.d.screenshotAnnotationTool || "") === modelData.id
                            onClicked: page.d.screenshotAnnotationTool = modelData.id
                        }
                    }
                }
                Text { text: Tr.t("Recording video codec"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "", label: Tr.t("Auto") }, { id: "libx264", label: "H.264" }, { id: "libx265", label: "HEVC" }, { id: "libvpx-vp9", label: "VP9" }, { id: "libaom-av1", label: "AV1" }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.recordCodec === modelData.id
                            onClicked: page.d.recordCodec = modelData.id
                        }
                    }
                }
                Text { text: Tr.t("A recording captures"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "screen", label: Tr.t("The whole screen") }, { id: "region", label: Tr.t("A region I choose each time") }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.recordArea === modelData.id
                            onClicked: page.d.recordArea = modelData.id
                        }
                    }
                }
                Text { text: Tr.t("A recording's sound is"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: "none", label: Tr.t("No sound") }, { id: "desktop", label: Tr.t("The computer's sound") }, { id: "mic", label: Tr.t("My microphone") }, { id: "both", label: Tr.t("Both, on two tracks") }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.recordSound === modelData.id
                            onClicked: page.d.recordSound = modelData.id
                        }
                    }
                }
                Text { text: Tr.t("A recording is captured at"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ id: 0, label: Tr.t("What the screen does") }, { id: 30, label: "30 fps" }, { id: 60, label: "60 fps" }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.recordFps === modelData.id
                            onClicked: page.d.recordFps = modelData.id
                        }
                    }
                }

                SectionTitle { Layout.fillWidth: true; text: Tr.t("Screen saver") }
                SwitchRow {
                    Layout.fillWidth: true
                    text: Tr.t("Show a clock when idle")
                    hint: Tr.t("Over the wallpaper, until a key or the mouse is touched - only if it comes before the dim and the lock")
                    checked: page.d.screenSaverEnabled
                    onToggled: on => page.d.screenSaverEnabled = on
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: page.d.screenSaverEnabled
                    spacing: 8
                    Text { text: Tr.t("After"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale; Layout.preferredWidth: 100 }
                    Repeater {
                        model: [1, 2, 3, 5, 10]
                        Choice {
                            required property int modelData
                            text: modelData + " min"
                            selected: page.d.screenSaverMinutes === modelData
                            onClicked: page.d.screenSaverMinutes = modelData
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Button { text: Tr.t("Preview"); onClicked: ScreenSaver.preview = true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: page.d.screenSaverEnabled
                    spacing: 8
                    Text { text: Tr.t("Show"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale; Layout.preferredWidth: 100 }
                    Repeater {
                        model: [{ id: "clock", label: Tr.t("A clock") }, { id: "photos", label: Tr.t("My photos") }]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: page.d.screenSaverStyle === modelData.id
                            onClicked: page.d.screenSaverStyle = modelData.id
                        }
                    }
                }
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
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Battery saver"); hint: Tr.t("power saver at the charge below, back when charging"); checked: page.d.autoPowerSaver; onToggled: on => page.d.autoPowerSaver = on }
                Flow {
                    visible: page.d.autoPowerSaver
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [10, 15, 20, 30]
                        Choice { required property int modelData; text: modelData + " %"; selected: page.d.powerSaverAt === modelData; onClicked: page.d.powerSaverAt = modelData }
                    }
                }
                // the profile follows the charger: picked from choices; Power.qml has the order
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Power mode follows the charger"); hint: Tr.t("set when you plug in or unplug; battery saver and games still come first"); checked: page.d.profileFollowsCharger; onToggled: on => page.d.profileFollowsCharger = on }
                Text { visible: page.d.profileFollowsCharger; text: Tr.t("On battery use"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                Flow {
                    visible: page.d.profileFollowsCharger
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [["power-saver", Tr.t("Power saver")], ["balanced", Tr.t("Balanced")]]
                        Choice { required property var modelData; text: modelData[1]; selected: page.d.profileOnBattery === modelData[0]; onClicked: page.d.profileOnBattery = modelData[0] }
                    }
                }
                Text { visible: page.d.profileFollowsCharger; text: Tr.t("Plugged in use"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                Flow {
                    visible: page.d.profileFollowsCharger
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [["balanced", Tr.t("Balanced")], ["performance", Tr.t("Performance")]]
                        Choice { required property var modelData; text: modelData[1]; selected: page.d.profilePluggedIn === modelData[0]; onClicked: page.d.profilePluggedIn = modelData[0] }
                    }
                }
                SwitchRow { Layout.fillWidth: true; text: Tr.t("Lock when critically low"); hint: Tr.t("lock the screen at 7 % battery — plug in to unlock"); checked: page.d.autoLockOnLowBattery; onToggled: on => page.d.autoLockOnLowBattery = on }
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
                Text { Layout.fillWidth: true; text: Tr.t("Plugged in"); color: Theme.faint; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
                Repeater {
                    model: [
                        { label: Tr.t("Dim the screen"), key: "dimAfter", options: [60, 120, 240, 300, 0] },
                        { label: Tr.t("Lock"), key: "lockAfter", options: [60, 120, 300, 600, 900, 0] },
                        { label: Tr.t("Screen off"), key: "screenOffAfter", options: [120, 300, 600, 1800, 0] },
                        { label: Tr.t("Suspend"), key: "suspendAfter", options: [900, 1800, 3600, 0] }
                    ]
                    ColumnLayout {
                        id: stage
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4
                        Text { text: stage.modelData.label + Tr.t(" after"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
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
                Text { Layout.fillWidth: true; visible: Power.hasBattery; text: Tr.t("On battery"); color: Theme.faint; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
                Repeater {
                    model: [
                        { label: Tr.t("Dim the screen"), key: "dimAfterBattery", options: [30, 60, 120, 180, 300, 0] },
                        { label: Tr.t("Lock"), key: "lockAfterBattery", options: [30, 60, 120, 180, 300, 0] },
                        { label: Tr.t("Screen off"), key: "screenOffAfterBattery", options: [60, 120, 240, 300, 600, 0] },
                        { label: Tr.t("Suspend"), key: "suspendAfterBattery", options: [300, 600, 900, 1800, 0] }
                    ]
                    ColumnLayout {
                        id: stageB
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4
                        visible: Power.hasBattery
                        Text { text: stageB.modelData.label + Tr.t(" after"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: stageB.modelData.options
                                Choice {
                                    required property int modelData
                                    text: page.minutes(modelData)
                                    selected: page.d[stageB.modelData.key] === modelData
                                    onClicked: page.d[stageB.modelData.key] = modelData
                                }
                            }
                        }
                    }
                }
                SwitchRow { Layout.fillWidth: true; visible: Power.hasBattery; text: Tr.t("Lock before suspend"); checked: page.d.lockBeforeSuspend; onToggled: on => page.d.lockBeforeSuspend = on }

            }
        }
    }
    // made when the category is opened, gone when another is (most never are)
}
// USB Storage settings (Android-style)
// Device info / About (Android-style device preferences)
