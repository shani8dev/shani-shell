// ShaniOS first-boot setup (after GNOME Initial Setup): language, keyboard,
// network, time zone, the computer's name and the first account — then
// straight into that account. greetd's greeter niri runs this instead of the
// login screen while the machine has no account (shani-desktop-niri), so it
// comes back by itself after a factory reset, which wipes the accounts.
//
// It runs as the unprivileged `greeter` user. The one privileged step —
// creating the account and setting the machine's language, keymap, zone and
// name — is bridge/first-account.py through pkexec, which a polkit rule lets
// `greeter` run and which refuses once any account exists.
//
// Everything is clickable: a step rail on the left, chips for the common
// choices, the map for the time zone, and a search field where there are too
// many options for chips. Nothing has to be typed from memory.
//@ pragma IconTheme Adwaita
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Networking
import Quickshell.Services.Greetd
import QtQuick
import QtQuick.Layouts
import qs.Common
import "strings.js" as Strings

ShellRoot {
    id: root

    readonly property string wallpaper: Quickshell.env("SHANI_GREETER_WALLPAPER") || "/usr/share/backgrounds/shani/shani-dark.jpg"
    readonly property var sessionCmd: (Quickshell.env("SHANI_GREETER_SESSION") || "niri-session").split(" ")
    // pkexec in the image; the dev test runs the helper directly, as root
    readonly property var applyCmd: (Quickshell.env("SHANI_SETUP_APPLY") || "pkexec /usr/lib/shani-shell/first-account.py").split(" ")
    readonly property string layoutTool: Quickshell.env("SHANI_OSK_LAYOUT_TOOL") || "/usr/lib/shani-shell/osk-layout.py"

    readonly property var pages: ["welcome", "keyboard", "network", "time", "account", "done"]
    property int page: 0
    // the furthest step reached: the rail lets you go back to any of them
    property int furthest: 0
    readonly property string pageId: pages[page]
    // the wizard's words, in the language picked on the first page (strings.js)
    function t(key) { return Strings.tr(root.locale, key); }
    function stepIcon(id) {
        return ({ welcome: "preferences-desktop-locale", keyboard: "input-keyboard", network: "network-wireless",
                  time: "preferences-system-time", account: "avatar-default", done: "object-select" })[id] || "go-next";
    }

    // what will be applied
    property string locale: ""
    property var keymap: ["us"]
    property string timezone: ""
    property string fullname: ""
    property string username: ""
    property bool usernameEdited: false
    property string password: ""
    property string password2: ""
    property bool showPassword: false
    property string hostname: ""
    // the screen keyboard: open by itself with a touchscreen (a tablet's first boot)
    property bool kb: Quickshell.env("SHANI_SETUP_KEYBOARD") === "1"
    Process {
        running: Quickshell.env("SHANI_SETUP_KEYBOARD") === ""
        command: ["sh", "-c", "udevadm info --export-db 2>/dev/null | grep -q ID_INPUT_TOUCHSCREEN=1"]
        onExited: code => { if (code === 0) root.kb = true; }
    }
    property bool hostnameEdited: false

    property string status: ""            // "", "working", "error: …", "signing-in"
    // Orca for as long as it is on; the greeter niri runs this under its own
    // session bus (dbus-run-session), which Orca and AT-SPI need
    property bool screenReader: false
    Process {
        running: root.screenReader
        command: ["orca", "--replace"]
    }
    property var warnings: []

    // ---- choices from the system -------------------------------------------
    property var locales: []
    property var zones: []
    property string zoneTime: ""         // the time in the chosen zone
    property string zoneQuery: ""        // what was typed into the zone search
    readonly property var zoneMatches: {
        const q = root.zoneQuery.trim().toLowerCase().replace(/ /g, "_");
        if (q.length < 2)
            return [];
        return root.zones.filter(z => z.toLowerCase().indexOf(q) >= 0).slice(0, 30);
    }
    property var catalogue: []
    Process {
        running: true
        command: ["sh", "-c", 'localectl list-locales 2>/dev/null || locale -a | grep -i utf; echo "--current=$(localectl status 2>/dev/null | sed -n "s/.*System Locale: LANG=//p")"']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                // the machine's own locale first, then the environment's
                const cur = ((l.find(x => x.startsWith("--current=")) || "").slice(10).trim())
                    || (Quickshell.env("LANG") || "");
                // C and POSIX are not languages anyone picks
                root.locales = l.filter(x => x && !x.startsWith("--") && !/^(C|POSIX)(\.|$)/i.test(x));
                // match "en_US.UTF-8" against "en_US.utf8" and "en_US" alike
                const norm = s => s.toLowerCase().replace(/-/g, "_");
                const same = name => {
                    if (!name)
                        return "";
                    return root.locales.find(x => norm(x) === norm(name))
                        || root.locales.find(x => norm(x).split(".")[0] === norm(name).split(".")[0]) || "";
                };
                // never open on "aa_DJ.utf8" just because it sorts first: the
                // current locale, else US English, else any English, else the
                // first one this system has
                root.locale = same(cur)
                    || root.locales.find(x => /^en[_-]US[.@]/i.test(x))
                    || root.locales.find(x => /^en[_-]/i.test(x))
                    || root.locales[0] || "";
            }
        }
    }
    Process {
        running: true
        command: ["sh", "-c", 'timedatectl list-timezones 2>/dev/null || (cd /usr/share/zoneinfo && find . -type f | sed "s|^\\./||" | grep -E "^(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)/" | sort); echo "--current=$(timedatectl show -p Timezone --value 2>/dev/null || readlink /etc/localtime | sed "s,.*/zoneinfo/,,")"']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                root.zones = l.filter(x => x && !x.startsWith("--"));
                root.timezone = (l.find(x => x.startsWith("--current=")) || "").slice(10) || "UTC";
            }
        }
    }
    // the time where the chosen zone is — so the map answers "what time is it
    // there?", not just "which zone is this"
    Process {
        id: zoneClock
        command: ["sh", "-c", 'TZ="$1" date +"%H:%M"', "sh", root.timezone]
        stdout: StdioCollector { onStreamFinished: root.zoneTime = text.trim() }
    }
    Timer {
        interval: 20000
        repeat: true
        running: root.pageId === "time" && root.timezone !== ""
        triggeredOnStart: true
        onTriggered: zoneClock.running = true
    }
    Process {
        running: true
        command: ["python3", root.layoutTool, "--list"]
        stdout: StdioCollector { onStreamFinished: { try { root.catalogue = JSON.parse(text); } catch (e) {} } }
    }

    function niceLocale(name) {
        const l = Qt.locale(name.replace(/\..*$/, ""));
        const lang = l.nativeLanguageName || name;
        return lang.charAt(0).toUpperCase() + lang.slice(1) + (l.nativeTerritoryName ? " · " + l.nativeTerritoryName : "");
    }
    // just the language, for the chips on the first page
    function langName(name) {
        const l = Qt.locale(name.replace(/\..*$/, ""));
        const lang = l.nativeLanguageName || name;
        return lang.charAt(0).toUpperCase() + lang.slice(1);
    }
    // the languages the wizard itself speaks, when the system has them:
    // match "en_US.UTF-8" against "en_US.utf8" and "en_US" alike, so the
    // chips appear on real systems and in the dev container
    readonly property var quickLocales: {
        const wanted = ["en_US", "hi_IN", "mr_IN", "de_DE", "es_ES", "fr_FR"];
        const out = [];
        for (const w of wanted) {
            const hit = root.locales.find(x => {
                const b = x.toLowerCase().replace(/-/g, "_").split(".")[0];
                return b === w.toLowerCase();
            });
            if (hit && out.indexOf(hit) < 0)
                out.push(hit);
        }
        return out;
    }
    // layouts most people start from — a click adds or removes one
    readonly property var quickLayouts: [
        { id: "us", label: "English (US)" },
        { id: "gb", label: "English (UK)" },
        { id: "in+marathi", label: "मराठी" },
        { id: "in+bolnagri", label: "हिन्दी" },
        { id: "de", label: "Deutsch" },
        { id: "fr", label: "Français" },
        { id: "es", label: "Español" },
        { id: "ru", label: "Русский" },
        { id: "jp", label: "日本語" },
        { id: "us+dvorak", label: "Dvorak" }
    ]
    // places people look for first on the time page
    readonly property var quickZones: {
        const wanted = ["UTC", "Asia/Kolkata", "Asia/Dubai", "Europe/London", "Europe/Berlin", "Europe/Paris",
                        "America/New_York", "America/Chicago", "America/Los_Angeles", "America/Sao_Paulo",
                        "Africa/Nairobi", "Asia/Singapore", "Asia/Tokyo", "Australia/Sydney"];
        return wanted.filter(z => root.zones.indexOf(z) >= 0);
    }
    function zoneLabel(zone) {
        return zone === "UTC" ? "UTC" : zone.split("/").pop().replace(/_/g, " ");
    }
    function layoutName(id) {
        const c = catalogue.find(x => x.id === id);
        return c ? c.name : id;
    }
    function pickZoneName(name) {
        if (!name)
            return;
        root.timezone = name;
        tzSearch.text = "";
    }
    // "Asha Patil" → "asha"; letters a–z only, as useradd wants
    function suggestUser(name) {
        const first = (name.trim().split(/\s+/)[0] || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9_-]/g, "");
        return /^[a-z_]/.test(first) ? first.slice(0, 32) : "";
    }
    function initials(name) {
        const parts = name.trim().split(/\s+/).filter(x => x);
        return (parts.slice(0, 2).map(w => w.charAt(0).toUpperCase()).join("")) || "?";
    }
    function suggestHost(user) {
        return user ? user + "-shani" : "";
    }
    onFullnameChanged: {
        if (!usernameEdited)
            username = suggestUser(fullname);
        if (!hostnameEdited)
            hostname = suggestHost(username);
    }

    readonly property string accountProblem: {
        if (fullname.trim() === "") return root.t("needName");
        if (!/^[a-z_][a-z0-9_-]{0,31}$/.test(username)) return root.t("badUser");
        if (password.length < 1) return root.t("needPassword");
        if (password !== password2) return root.t("mismatch");
        if (hostname && !/^[A-Za-z0-9][A-Za-z0-9-]{0,62}$/.test(hostname)) return root.t("badHost");
        return "";
    }
    readonly property string strength: password.length === 0 ? "" : password.length < 8 ? root.t("weak")
        : (/[A-Z]/.test(password) + /[a-z]/.test(password) + /[0-9]/.test(password) + /[^A-Za-z0-9]/.test(password)) >= 3 && password.length >= 10 ? root.t("strong") : root.t("fair")
    // 0…3, for the little bar under the password
    readonly property int strengthLevel: {
        if (password.length === 0) return 0;
        let s = 0;
        if (password.length >= 8) s++;
        if (password.length >= 12) s++;
        if (/[A-Z]/.test(password) && /[a-z]/.test(password)) s++;
        if (/[0-9]/.test(password)) s++;
        if (/[^A-Za-z0-9]/.test(password)) s++;
        return Math.min(3, Math.floor(s * 3 / 5));
    }

    function next() {
        if (pageId === "account") {
            if (accountProblem)
                return;
            finish();
            return;
        }
        if (page < pages.length - 1) {
            page++;
            furthest = Math.max(furthest, page);
        }
    }
    function back() {
        if (page > 0 && status !== "working" && status !== "signing-in")
            page--;
    }
    // the step rail: only steps already reached are clickable
    function goTo(index) {
        if (index < 0 || index > furthest || index === page || status === "working" || status === "signing-in")
            return;
        page = index;
        if (status.startsWith("error"))
            status = "";
    }

    // ---- the privileged step, then sign in ----------------------------------
    Process {
        id: applyProc
        command: root.applyCmd
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { ok: false, error: text.trim() || "setup could not run" }; }
                if (!r.ok) {
                    root.status = "error: " + r.error;
                    return;
                }
                root.warnings = r.warnings || [];
                root.status = "signing-in";
                root.page = root.pages.indexOf("done");
                root.furthest = root.pages.length - 1;
                Greetd.createSession(root.username);
            }
        }
        onStarted: {
            write(JSON.stringify({
                username: root.username, fullname: root.fullname.trim(), password: root.password,
                locale: root.locale, keymap: root.keymap, keymapSwitch: "grp:win_space_toggle",
                timezone: root.timezone, hostname: root.hostname
            }) + "\n");
            stdinEnabled = false;          // EOF: the helper reads the whole object
        }
    }
    function finish() {
        status = "working";
        applyProc.stdinEnabled = true;
        applyProc.running = true;
    }
    Connections {
        target: Greetd
        function onAuthMessage(message, isError, responseRequired, echoResponse) {
            if (responseRequired)
                Greetd.respond(echoResponse ? root.username : root.password);
        }
        function onAuthFailure(message) { root.status = "error: signing in: " + message; }
        function onError(message) { Greetd.cancelSession(); root.status = "error: " + message; }
        function onReadyToLaunch() {
            root.password = "";
            root.password2 = "";
            Greetd.launch(root.sessionCmd, [], true);
        }
    }

    // the tests drive it the way a person would, through these
    IpcHandler {
        target: "setup"
        function state(): string {
            return JSON.stringify({ page: root.pageId, locale: root.locale, keymap: root.keymap, timezone: root.timezone,
                                    username: root.username, hostname: root.hostname, problem: root.accountProblem,
                                    status: root.status, warnings: root.warnings, greetd: String(Greetd.state),
                                    locales: root.locales.length, zones: root.zones.length, nextWord: root.t("next") });
        }
        function next() { root.next(); }
        function back() { root.back(); }
        function set(key: string, value: string) {
            if (key === "keymap") root.keymap = value.split(",");
            else if (key === "username") { root.usernameEdited = true; root.username = value; }
            else if (key === "hostname") { root.hostnameEdited = true; root.hostname = value; }
            else root[key] = value;
        }
    }

    // ---- the window ----------------------------------------------------------
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            readonly property bool primary: modelData === Quickshell.screens[0]
            readonly property bool wide: width >= 880
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.bg
            WlrLayershell.namespace: "shani-setup"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Image {
                anchors.fill: parent
                source: "file://" + root.wallpaper
                fillMode: Image.PreserveAspectCrop
                opacity: 0.45
            }

            // accessibility from the first screen (after GNOME Initial Setup):
            // larger text, higher contrast, a screen reader
            Glass {
                visible: win.primary
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 20
                implicitWidth: accessRow.implicitWidth + 20
                implicitHeight: 38
                radius: 19
                edge: "none"
                RowLayout {
                    id: accessRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { name: "preferences-desktop-accessibility"; size: 18; color: Theme.text; Layout.alignment: Qt.AlignVCenter }
                    Choice { text: root.t("larger"); selected: Settings.data.largeText; onClicked: Settings.data.largeText = !Settings.data.largeText }
                    Choice { text: root.t("contrast"); selected: Settings.data.highContrast; onClicked: Settings.data.highContrast = !Settings.data.highContrast }
                    Choice { text: root.t("reader"); selected: root.screenReader; onClicked: root.screenReader = !root.screenReader }
                    IconButton { icon: "input-keyboard"; size: 28; on: root.kb; Accessible.name: "Screen keyboard"; onClicked: root.kb = !root.kb }
                }
            }

            // the screen keyboard, into whichever field has focus; the card moves up for it
            ScreenKeyboard {
                visible: root.kb && win.primary
                z: 10
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 16
                width: Math.min(900, parent.width - 40)
                target: win.activeFocusItem && win.activeFocusItem.insert ? win.activeFocusItem : null
                onEntered: if (win.activeFocusItem && win.activeFocusItem.accepted) win.activeFocusItem.accepted()
            }

            Glass {
                visible: win.primary
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.kb ? -150 : 0
                width: Math.min(win.wide ? 940 : 620, parent.width - 48)
                height: Math.min(700, parent.height - 48 - (root.kb ? 300 : 0))
                strong: true
                radius: Theme.radiusLarge

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    // ---- the step rail ---------------------------------------
                    Rectangle {
                        visible: win.wide
                        Layout.preferredWidth: 224
                        Layout.fillHeight: true
                        radius: Theme.radiusLarge
                        color: Theme.alpha(Theme.text, 0.035)
                        border.width: 1
                        border.color: Theme.stroke

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Rectangle {
                                    width: 34; height: 34; radius: 10
                                    color: Theme.accentSoft
                                    border.width: 1
                                    border.color: Theme.accentLine
                                    Icon { anchors.centerIn: parent; name: "preferences-system"; size: 18; color: Theme.accent }
                                }
                                ColumnLayout {
                                    spacing: 0
                                    Text { text: "ShaniOS"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15 * Theme.fontScale; font.weight: Font.DemiBold }
                                    Text { text: root.t("firstSetup"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
                                }
                                Item { Layout.fillWidth: true }
                            }

                            Item { implicitHeight: 12 }

                            Repeater {
                                model: root.pages
                                Rectangle {
                                    required property string modelData
                                    required property int index
                                    readonly property bool current: index === root.page
                                    readonly property bool done: index < root.page
                                    readonly property bool reachable: index <= root.furthest
                                    Layout.fillWidth: true
                                    implicitHeight: 42
                                    radius: 10
                                    color: current ? Theme.accentSoft : (railHover.containsMouse && reachable ? Theme.hover : "transparent")
                                    border.width: current ? 1 : 0
                                    border.color: Theme.accentLine

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        Icon {
                                            name: root.stepIcon(modelData)
                                            size: 16
                                            color: current ? Theme.accent : (reachable ? Theme.text : Theme.faint)
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.t(modelData)
                                            color: current ? Theme.accent : (reachable ? Theme.text : Theme.faint)
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: 12 * Theme.fontScale
                                            font.weight: current ? Font.DemiBold : Font.Normal
                                        }
                                        Icon { visible: done; name: "object-select-symbolic"; size: 13; color: Theme.accent }
                                    }

                                    MouseArea {
                                        id: railHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: reachable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        enabled: reachable && index !== root.page && root.status !== "working" && root.status !== "signing-in"
                                        onClicked: root.goTo(index)
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }

                            Text {
                                Layout.fillWidth: true
                                text: root.t("step") + " " + (root.page + 1) + " / " + root.pages.length
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 10 * Theme.fontScale
                            }
                        }
                    }

                    // ---- the page --------------------------------------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: win.wide ? 18 : 22
                        Layout.rightMargin: win.wide ? 18 : 22
                        Layout.topMargin: 14
                        Layout.bottomMargin: 16
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    text: root.t("step") + " " + (root.page + 1) + " / " + root.pages.length
                                    color: Theme.accent
                                    font.family: Theme.font
                                    font.pixelSize: 10 * Theme.fontScale
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: ({ welcome: root.t("welcome"), keyboard: root.t("keyboard"), network: root.t("network"),
                                             time: root.t("time"), account: root.t("account"), done: root.t("done") })[root.pageId]
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: 24 * Theme.fontScale
                                    font.weight: Font.DemiBold
                                }
                            }
                            // on narrow screens the rail is hidden; dots do the job
                            Row {
                                visible: !win.wide
                                spacing: 6
                                Repeater {
                                    model: root.pages.length
                                    Rectangle {
                                        required property int index
                                        width: index === root.page ? 20 : 7
                                        height: 7
                                        radius: 4
                                        color: index <= root.page ? Theme.accent : Theme.stroke
                                    }
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: ({ welcome: root.t("welcomeSub"),
                                     keyboard: root.t("keyboardSub"),
                                     network: root.t("networkSub"),
                                     time: root.t("timeSub"),
                                     account: root.t("accountSub"),
                                     done: root.status === "signing-in" ? root.t("signingIn") : "" })[root.pageId]
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 12 * Theme.fontScale
                        }

                        // ---- the pages ----
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // language: the languages the wizard speaks first,
                            // then every language the system has
                            ColumnLayout {
                                anchors.fill: parent
                                visible: root.pageId === "welcome"
                                spacing: 8
                                Text { text: root.t("popular"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: root.quickLocales
                                        Choice {
                                            required property string modelData
                                            text: root.langName(modelData)
                                            selected: root.locale === modelData
                                            onClicked: root.locale = modelData
                                        }
                                    }
                                }
                                Text { text: root.t("allLanguages"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                                TextField { id: langSearch; Layout.fillWidth: true; placeholder: root.t("searchLang") }
                                ListView {
                                    id: langList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 2
                                    function revealSelected() {
                                        if (langSearch.text.trim() !== "")
                                            return;
                                        const i = root.locales.indexOf(root.locale);
                                        if (i >= 0)
                                            positionViewAtIndex(i, ListView.Beginning);
                                    }
                                    onCountChanged: Qt.callLater(revealSelected)
                                    onVisibleChanged: if (visible) Qt.callLater(revealSelected)
                                    model: root.locales.filter(l => { const q = langSearch.text.trim().toLowerCase(); return q === "" || l.toLowerCase().indexOf(q) >= 0 || root.niceLocale(l).toLowerCase().indexOf(q) >= 0; })
                                    delegate: ListRow {
                                        required property string modelData
                                        width: ListView.view.width
                                        icon: "preferences-desktop-locale"
                                        title: root.niceLocale(modelData)
                                        selected: modelData === root.locale
                                        onClicked: root.locale = modelData
                                    }
                                }
                            }

                            // keyboard: chips for the usual layouts, the chosen
                            // ones with ×, a field to try them, and a search
                            ColumnLayout {
                                anchors.fill: parent
                                visible: root.pageId === "keyboard"
                                spacing: 8
                                Text { text: root.t("commonLayouts"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: root.quickLayouts
                                        Choice {
                                            required property var modelData
                                            text: modelData.label
                                            selected: root.keymap.indexOf(modelData.id) >= 0
                                            onClicked: {
                                                const i = root.keymap.indexOf(modelData.id);
                                                if (i >= 0) {
                                                    if (root.keymap.length > 1)
                                                        root.keymap = root.keymap.filter(x => x !== modelData.id);
                                                } else {
                                                    root.keymap = root.keymap.concat([modelData.id]);
                                                }
                                            }
                                        }
                                    }
                                }
                                Repeater {
                                    model: root.keymap
                                    ListRow {
                                        id: kmRow
                                        required property string modelData
                                        Layout.fillWidth: true
                                        icon: "input-keyboard"
                                        title: root.layoutName(modelData)
                                        subtitle: modelData
                                        IconButton {
                                            visible: root.keymap.length > 1
                                            icon: "edit-delete"
                                            size: 24
                                            Accessible.name: root.t("remove") + kmRow.title
                                            onClicked: root.keymap = root.keymap.filter(x => x !== kmRow.modelData)
                                        }
                                    }
                                }
                                TextField {
                                    Layout.fillWidth: true
                                    placeholder: root.t("typeHere")
                                }
                                TextField { id: kmSearch; Layout.fillWidth: true; placeholder: root.t("addLayout") }
                                ListView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 2
                                    model: kmSearch.text.trim().length < 2 ? [] : root.catalogue.filter(c => c.name.toLowerCase().indexOf(kmSearch.text.trim().toLowerCase()) >= 0).slice(0, 30)
                                    delegate: ListRow {
                                        required property var modelData
                                        width: ListView.view.width
                                        icon: "list-add"
                                        title: modelData.name
                                        subtitle: modelData.id
                                        onClicked: {
                                            if (root.keymap.indexOf(modelData.id) < 0)
                                                root.keymap = root.keymap.concat([modelData.id]);
                                            kmSearch.text = "";
                                        }
                                    }
                                }
                            }

                            // network: what is in range, connected ones marked;
                            // a locked network asks for its password in place
                            ColumnLayout {
                                id: netPage
                                anchors.fill: parent
                                visible: root.pageId === "network"
                                spacing: 8
                                readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
                                readonly property bool online: Networking.connectivity === NetworkConnectivity.Full
                                property string pending: ""
                                property bool showPass: false
                                onVisibleChanged: if (wifi) wifi.scannerEnabled = visible
                                onPendingChanged: showPass = false
                                Timer {
                                    id: rescan
                                    interval: 350
                                    onTriggered: if (netPage.wifi) netPage.wifi.scannerEnabled = true
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Icon {
                                        name: netPage.online ? "object-select" : (netPage.wifi ? "network-wireless" : "network-wired")
                                        size: 16
                                        color: netPage.online ? Theme.accent : Theme.dim
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: netPage.online ? root.t("online") : netPage.wifi ? root.t("chooseWifi") : root.t("noWifi")
                                        color: netPage.online ? Theme.accent : Theme.dim
                                        wrapMode: Text.Wrap
                                        font.family: Theme.font
                                        font.pixelSize: 12 * Theme.fontScale
                                    }
                                    Button {
                                        visible: netPage.wifi !== null && !netPage.online
                                        text: root.t("refresh")
                                        onClicked: { netPage.wifi.scannerEnabled = false; rescan.start(); }
                                    }
                                }
                                ListView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 2
                                    model: netPage.wifi ? netPage.wifi.networks.values : []
                                    delegate: ColumnLayout {
                                        id: wRow
                                        required property var modelData
                                        width: ListView.view.width
                                        spacing: 2
                                        ListRow {
                                            Layout.fillWidth: true
                                            icon: wRow.modelData.connected ? "network-wireless-signal-excellent" : "network-wireless"
                                            title: wRow.modelData.name
                                            subtitle: wRow.modelData.connected ? root.t("connected") : wRow.modelData.stateChanging ? root.t("connecting") : ""
                                            selected: wRow.modelData.connected
                                            onClicked: wRow.modelData.security === WifiSecurityType.Open ? wRow.modelData.connect() : netPage.pending = wRow.modelData.name
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            visible: netPage.pending === wRow.modelData.name
                                            spacing: 6
                                            TextField {
                                                id: wifiPass
                                                Layout.fillWidth: true
                                                placeholder: root.t("passwordFor") + wRow.modelData.name
                                                secret: !netPage.showPass
                                                onAccepted: { wRow.modelData.connectWithPsk(text); text = ""; netPage.pending = ""; }
                                            }
                                            Button {
                                                text: root.t("connect")
                                                kind: "primary"
                                                enabled: wifiPass.text !== ""
                                                onClicked: { wRow.modelData.connectWithPsk(wifiPass.text); wifiPass.text = ""; netPage.pending = ""; }
                                            }
                                            Choice {
                                                text: netPage.showPass ? root.t("hidePassword") : root.t("showPassword")
                                                selected: netPage.showPass
                                                onClicked: netPage.showPass = !netPage.showPass
                                            }
                                        }
                                    }
                                }
                            }

                            // time zone: the map — click where you are — quick
                            // places for the usual ones, and a search
                            Item {
                                anchors.fill: parent
                                visible: root.pageId === "time"

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Icon { name: "preferences-system-time"; size: 18; color: Theme.accent }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.timezone.replace(/_/g, " ")
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: 16 * Theme.fontScale
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: tzMap.point !== null
                                            Layout.fillWidth: true
                                            text: tzMap.point ? tzMap.point.city + (root.zoneTime ? "  ·  " + root.zoneTime : "") : ""
                                            color: Theme.dim
                                            font.family: Theme.font
                                            font.pixelSize: 11 * Theme.fontScale
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: root.zoneTime !== ""
                                            text: root.zoneTime
                                            color: Theme.dim
                                            font.family: Theme.mono
                                            font.pixelSize: 14 * Theme.fontScale
                                        }
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Repeater {
                                            model: root.quickZones
                                            Choice {
                                                required property string modelData
                                                text: root.zoneLabel(modelData)
                                                selected: root.timezone === modelData
                                                onClicked: root.pickZoneName(modelData)
                                            }
                                        }
                                    }

                                    Item {
                                        id: mapSlot
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        WorldMap {
                                            id: tzMap
                                            anchors.centerIn: parent
                                            width: parent.width
                                            height: Math.min(parent.height, parent.width / 2)
                                            zone: root.timezone
                                            onZonePicked: z => root.pickZoneName(z)
                                        }

                                        // matches float over the map, just above the field
                                        Rectangle {
                                            id: zoneList
                                            visible: root.zoneQuery.trim().length >= 2 && root.zoneMatches.length > 0
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: Math.min(parent.height * 0.62, suggestions.contentHeight + 8)
                                            radius: Theme.radiusSmall
                                            color: Theme.glassStrong
                                            border.width: 1
                                            border.color: Theme.stroke
                                            clip: true

                                            ListView {
                                                id: suggestions
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                clip: true
                                                spacing: 2
                                                model: root.zoneMatches
                                                delegate: ListRow {
                                                    required property string modelData
                                                    width: ListView.view.width
                                                    icon: "preferences-system-time"
                                                    title: modelData.replace(/_/g, " ")
                                                    selected: modelData === root.timezone
                                                    onClicked: root.pickZoneName(modelData)
                                                }
                                            }
                                        }
                                    }

                                    TextField {
                                        id: tzSearch
                                        Layout.fillWidth: true
                                        placeholder: root.t("searchZone")
                                        onTextChanged: root.zoneQuery = text
                                        onAccepted: root.pickZoneName(root.zoneMatches.length > 0 ? root.zoneMatches[0] : "")
                                    }
                                }
                            }

                            // account: who you are, a password with a strength
                            // bar and a show toggle, the computer's name, and a
                            // summary of what the wizard will apply
                            ColumnLayout {
                                anchors.fill: parent
                                visible: root.pageId === "account"
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Rectangle {
                                        width: 44; height: 44; radius: 22
                                        color: Theme.accentSoft
                                        border.width: 1
                                        border.color: Theme.accentLine
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.initials(root.fullname)
                                            color: Theme.accent
                                            font.family: Theme.font
                                            font.pixelSize: 17 * Theme.fontScale
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                    ColumnLayout {
                                        spacing: 0
                                        Text {
                                            text: root.fullname.trim() !== "" ? root.fullname : root.t("fullName")
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: 13 * Theme.fontScale
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            text: (root.username ? root.username : "—") + (root.hostname ? " · " + root.hostname : "")
                                            color: Theme.dim
                                            font.family: Theme.mono
                                            font.pixelSize: 10 * Theme.fontScale
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                FieldLabel { text: root.t("fullName") }
                                TextField { id: nameField; Layout.fillWidth: true; placeholder: root.t("fullName"); onTextChanged: root.fullname = text; border.color: root.accountProblem === root.t("needName") ? Theme.danger : Theme.stroke }
                                FieldLabel { text: root.t("userName") }
                                TextField {
                                    Layout.fillWidth: true
                                    placeholder: root.t("userName")
                                    text: root.username
                                    border.color: root.accountProblem === root.t("badUser") ? Theme.danger : Theme.stroke
                                    onTextChanged: if (text !== root.username) { root.usernameEdited = true; root.username = text; }
                                }
                                FieldLabel { text: root.t("password") }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    TextField {
                                        Layout.fillWidth: true
                                        placeholder: root.t("password")
                                        secret: !root.showPassword
                                        onTextChanged: root.password = text
                                    }
                                    Choice {
                                        text: root.showPassword ? root.t("hidePassword") : root.t("showPassword")
                                        selected: root.showPassword
                                        onClicked: root.showPassword = !root.showPassword
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 4
                                    radius: 2
                                    visible: root.password !== ""
                                    color: Theme.alpha(Theme.text, 0.12)
                                    Rectangle {
                                        width: parent.width * (root.strengthLevel / 3)
                                        height: parent.height
                                        radius: 2
                                        color: root.strengthLevel >= 3 ? Theme.accent : root.strengthLevel === 2 ? Theme.amber : Theme.danger
                                        Behavior on width { NumberAnimation { duration: Theme.anim } }
                                    }
                                }
                                Text {
                                    visible: root.strength !== ""
                                    text: root.t("passwordIs") + root.strength
                                    color: root.strengthLevel >= 3 ? Theme.accent : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 11 * Theme.fontScale
                                }
                                FieldLabel { text: root.t("passwordAgain") }
                                TextField { Layout.fillWidth: true; placeholder: root.t("passwordAgain"); secret: !root.showPassword; onTextChanged: root.password2 = text; onAccepted: root.next() }
                                FieldLabel { text: root.t("computerName") }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    TextField {
                                        Layout.fillWidth: true
                                        placeholder: root.t("computerName")
                                        text: root.hostname
                                        border.color: root.accountProblem === root.t("badHost") ? Theme.danger : Theme.stroke
                                        onTextChanged: if (text !== root.hostname) { root.hostnameEdited = true; root.hostname = text; }
                                    }
                                    Choice {
                                        visible: root.username !== "" && root.hostname !== root.suggestHost(root.username)
                                        text: root.suggestHost(root.username)
                                        onClicked: { root.hostname = root.suggestHost(root.username); root.hostnameEdited = true; }
                                    }
                                }
                                Text {
                                    visible: root.fullname.trim() !== "" && root.username !== "" && root.hostname !== ""
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: root.t("adminNote")
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 11 * Theme.fontScale
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: summaryCol.implicitHeight + 20
                                    radius: Theme.radiusSmall
                                    color: Theme.alpha(Theme.text, 0.035)
                                    border.width: 1
                                    border.color: Theme.stroke
                                    ColumnLayout {
                                        id: summaryCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 10
                                        spacing: 2
                                        Text {
                                            text: root.t("summary")
                                            color: Theme.dim
                                            font.family: Theme.font
                                            font.pixelSize: 10 * Theme.fontScale
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            wrapMode: Text.Wrap
                                            text: root.t("language") + ": " + (root.locale ? root.niceLocale(root.locale) : "—")
                                                + "   ·   " + root.t("layouts") + ": " + root.keymap.map(root.layoutName).join(", ")
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: 10 * Theme.fontScale
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            wrapMode: Text.Wrap
                                            text: root.t("zone") + ": " + root.timezone.replace(/_/g, " ")
                                                + "   ·   " + root.t("computer") + ": " + (root.hostname || "—")
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: 10 * Theme.fontScale
                                        }
                                    }
                                }
                                Item { Layout.fillHeight: true }
                            }

                            // done
                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: root.pageId === "done"
                                spacing: 10
                                Icon { Layout.alignment: Qt.AlignHCenter; name: "object-select-symbolic"; size: 56; color: Theme.accent }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: root.fullname.trim() !== ""
                                    text: root.t("welcomeUser").replace("{name}", root.fullname.trim().split(/\s+/)[0])
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: 20 * Theme.fontScale
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.t("fasterTip")
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 12 * Theme.fontScale
                                }
                                Repeater {
                                    model: root.warnings
                                    Text { required property string modelData; text: root.t("note") + modelData; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: root.status.startsWith("error: ") ? root.status.slice(7)
                                : root.pageId === "account" && root.fullname !== "" ? root.accountProblem : ""
                            color: root.status.startsWith("error") ? Theme.danger : Theme.dim
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.pageId !== "done"
                            spacing: 8
                            Button { visible: root.page > 0; kind: "outline"; text: root.t("back"); onClicked: root.back() }
                            Item { Layout.fillWidth: true }
                            Button { visible: root.pageId === "network"; kind: "outline"; text: root.t("continueOffline"); onClicked: root.next() }
                            Button {
                                kind: "primary"
                                text: root.pageId === "account" ? (root.status === "working" ? root.t("working") : root.t("start")) : root.t("next")
                                enabled: (root.pageId !== "account" || (root.accountProblem === "" && root.status !== "working"))
                                    && (root.pageId !== "welcome" || root.locale !== "")
                                    && (root.pageId !== "time" || root.timezone !== "")
                                onClicked: root.next()
                            }
                        }
                    }
                }
            }
        }
    }

    // what a field is, above it: the placeholder goes once something is typed
    component FieldLabel: Text {
        Layout.fillWidth: true
        Layout.topMargin: 4
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
        font.weight: Font.Medium
    }
}
