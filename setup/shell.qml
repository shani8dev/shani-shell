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
    readonly property string pageId: pages[page]
    // the wizard's words, in the language picked on the first page (strings.js)
    function t(key) { return Strings.tr(root.locale, key); }

    // what will be applied
    property string locale: ""
    property var keymap: ["us"]
    property string timezone: ""
    property string fullname: ""
    property string username: ""
    property bool usernameEdited: false
    property string password: ""
    property string password2: ""
    property string hostname: ""
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
    property var catalogue: []
    Process {
        running: true
        command: ["sh", "-c", 'localectl list-locales 2>/dev/null || locale -a | grep -i utf; echo "--current=$(localectl status 2>/dev/null | sed -n "s/.*System Locale: LANG=//p")"']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                const cur = (l.find(x => x.startsWith("--current=")) || "").slice(10);
                // C and POSIX are not languages anyone picks
                root.locales = l.filter(x => x && !x.startsWith("--") && !/^(C|POSIX)(\.|$)/i.test(x));
                root.locale = cur || (root.locales.indexOf("en_US.UTF-8") >= 0 ? "en_US.UTF-8" : root.locales[0] || "");
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
    function layoutName(id) {
        const c = catalogue.find(x => x.id === id);
        return c ? c.name : id;
    }
    // "Asha Patil" → "asha"; letters a–z only, as useradd wants
    function suggestUser(name) {
        const first = (name.trim().split(/\s+/)[0] || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9_-]/g, "");
        return /^[a-z_]/.test(first) ? first.slice(0, 32) : "";
    }
    onFullnameChanged: {
        if (!usernameEdited)
            username = suggestUser(fullname);
        if (!hostnameEdited)
            hostname = username ? username + "-shani" : "";
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

    function next() {
        if (pageId === "account") {
            if (accountProblem)
                return;
            finish();
            return;
        }
        if (page < pages.length - 1)
            page++;
    }
    function back() {
        if (page > 0 && status !== "working" && status !== "signing-in")
            page--;
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
            Row {
                visible: win.primary
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 20
                spacing: 6
                Icon { name: "preferences-desktop-accessibility"; size: 20; color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
                Choice { text: root.t("larger"); selected: Settings.data.largeText; onClicked: Settings.data.largeText = !Settings.data.largeText }
                Choice { text: root.t("contrast"); selected: Settings.data.highContrast; onClicked: Settings.data.highContrast = !Settings.data.highContrast }
                Choice { text: root.t("reader"); selected: root.screenReader; onClicked: root.screenReader = !root.screenReader }
            }

            Glass {
                visible: win.primary
                anchors.centerIn: parent
                width: Math.min(620, parent.width - 48)
                height: Math.min(640, parent.height - 48)
                strong: true
                radius: Theme.radiusLarge

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 32
                    spacing: 16

                    // progress: one dot per step
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8
                        Repeater {
                            model: root.pages.length
                            Rectangle {
                                required property int index
                                width: index === root.page ? 22 : 8
                                height: 8
                                radius: 4
                                color: index <= root.page ? Theme.accent : Theme.stroke
                                Behavior on width { NumberAnimation { duration: Theme.anim } }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: ({ welcome: root.t("welcome"), keyboard: root.t("keyboard"), network: root.t("network"),
                                 time: root.t("time"), account: root.t("account"), done: root.t("done") })[root.pageId]
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 26 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: ({ welcome: root.t("welcomeSub"),
                                 keyboard: root.t("keyboardSub"),
                                 network: root.t("networkSub"),
                                 time: root.t("timeSub"),
                                 account: root.t("accountSub"),
                                 done: root.status === "signing-in" ? root.t("signingIn") : "" })[root.pageId]
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 13 * Theme.fontScale
                    }

                    // ---- the pages ----
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // language
                        ColumnLayout {
                            anchors.fill: parent
                            visible: root.pageId === "welcome"
                            spacing: 8
                            TextField { id: langSearch; Layout.fillWidth: true; placeholder: root.t("searchLang") }
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 2
                                model: root.locales.filter(l => { const q = langSearch.text.trim().toLowerCase(); return q === "" || l.toLowerCase().indexOf(q) >= 0 || root.niceLocale(l).toLowerCase().indexOf(q) >= 0; })
                                delegate: ListRow {
                                    required property string modelData
                                    width: ListView.view.width
                                    icon: "preferences-desktop-locale"
                                    title: root.niceLocale(modelData)
                                    subtitle: modelData
                                    selected: modelData === root.locale
                                    onClicked: root.locale = modelData
                                }
                            }
                        }

                        // keyboard
                        ColumnLayout {
                            anchors.fill: parent
                            visible: root.pageId === "keyboard"
                            spacing: 8
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

                        // network
                        ColumnLayout {
                            id: netPage
                            anchors.fill: parent
                            visible: root.pageId === "network"
                            spacing: 8
                            readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
                            readonly property bool online: Networking.connectivity === NetworkConnectivity.Full
                            property string pending: ""
                            onVisibleChanged: if (wifi) wifi.scannerEnabled = visible
                            Text {
                                text: netPage.online ? root.t("online") : netPage.wifi ? root.t("chooseWifi") : root.t("noWifi")
                                color: netPage.online ? Theme.accent : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 13 * Theme.fontScale
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
                                        icon: "network-wireless"
                                        title: wRow.modelData.name
                                        subtitle: wRow.modelData.connected ? root.t("connected") : wRow.modelData.stateChanging ? root.t("connecting") : ""
                                        selected: wRow.modelData.connected
                                        onClicked: wRow.modelData.security === WifiSecurityType.Open ? wRow.modelData.connect() : netPage.pending = wRow.modelData.name
                                    }
                                    TextField {
                                        Layout.fillWidth: true
                                        visible: netPage.pending === wRow.modelData.name
                                        placeholder: root.t("passwordFor") + wRow.modelData.name
                                        secret: true
                                        onAccepted: { wRow.modelData.connectWithPsk(text); text = ""; netPage.pending = ""; }
                                    }
                                }
                            }
                        }

                        // time zone
                        ColumnLayout {
                            anchors.fill: parent
                            visible: root.pageId === "time"
                            spacing: 8
                            Text {
                                text: root.timezone.replace(/_/g, " ")
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 15 * Theme.fontScale
                            }
                            TextField { id: tzSearch; Layout.fillWidth: true; placeholder: root.t("searchZone") }
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 2
                                model: tzSearch.text.trim().length < 2 ? [] : root.zones.filter(z => z.toLowerCase().indexOf(tzSearch.text.trim().toLowerCase().replace(/ /g, "_")) >= 0).slice(0, 30)
                                delegate: ListRow {
                                    required property string modelData
                                    width: ListView.view.width
                                    icon: "preferences-system-time"
                                    title: modelData.replace(/_/g, " ")
                                    selected: modelData === root.timezone
                                    onClicked: { root.timezone = modelData; tzSearch.text = ""; }
                                }
                            }
                        }

                        // account
                        ColumnLayout {
                            anchors.fill: parent
                            visible: root.pageId === "account"
                            spacing: 10
                            TextField { id: nameField; Layout.fillWidth: true; placeholder: root.t("fullName"); onTextChanged: root.fullname = text }
                            TextField {
                                Layout.fillWidth: true
                                placeholder: root.t("userName")
                                text: root.username
                                onTextChanged: if (text !== root.username) { root.usernameEdited = true; root.username = text; }
                            }
                            TextField { Layout.fillWidth: true; placeholder: root.t("password"); secret: true; onTextChanged: root.password = text }
                            TextField { Layout.fillWidth: true; placeholder: root.t("passwordAgain"); secret: true; onTextChanged: root.password2 = text; onAccepted: root.next() }
                            Text {
                                visible: root.strength !== ""
                                text: root.t("passwordIs") + root.strength
                                color: root.strength === root.t("strong") ? Theme.accent : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 12 * Theme.fontScale
                            }
                            TextField {
                                Layout.fillWidth: true
                                placeholder: root.t("computerName")
                                text: root.hostname
                                onTextChanged: if (text !== root.hostname) { root.hostnameEdited = true; root.hostname = text; }
                            }
                            Item { Layout.fillHeight: true }
                        }

                        // done
                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: root.pageId === "done"
                            spacing: 10
                            Icon { Layout.alignment: Qt.AlignHCenter; name: "emblem-ok-symbolic"; size: 56; color: Theme.accent }
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
                        font.pixelSize: 12 * Theme.fontScale
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.pageId !== "done"
                        Button { visible: root.page > 0; text: root.t("back"); onClicked: root.back() }
                        Item { Layout.fillWidth: true }
                        Button { visible: root.pageId === "network"; text: root.t("skip"); onClicked: root.next() }
                        Button {
                            kind: "primary"
                            text: root.pageId === "account" ? (root.status === "working" ? root.t("working") : root.t("start")) : root.t("next")
                            enabled: root.pageId !== "account" || (root.accountProblem === "" && root.status !== "working")
                            onClicked: root.next()
                        }
                    }
                }
            }
        }
    }
}
