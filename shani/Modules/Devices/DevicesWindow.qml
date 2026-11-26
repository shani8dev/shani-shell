// Devices: the phones and small gadgets this computer can reach, in one app
// window. Every value is picked from a list; typing is only for a custom value
// (an address, a link, a file). Services/Devices and Services/Lines own the
// bridge calls, so this window never speaks to a tool by itself.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Devices"
    visible: Ui.devices
    onGone: Ui.devices = false
    implicitWidth: Theme.px(760)
    implicitHeight: Theme.px(640)

    tools: [
        IconButton {
            icon: "view-refresh"
            size: Theme.px(24)
            tip: Tr.t("Look again")
            onClicked: win.refreshAll()
        }
    ]

    property string tab: "phones"
    readonly property var tabs: [
        ["phones", Tr.t("Phones")],
        ["android", Tr.t("Android phone")],
        ["screen", Tr.t("This screen")],
        ["gadgets", Tr.t("Gadgets")],
        ["phone", Tr.t("Phone link")],
        ["lines", Tr.t("Lines")]
    ]

    // the connect form
    property string connectKind: "android"
    property string connectValue: ""

    // the Android tools
    property string phoneName: ""
    property string linkUrl: ""
    property string appId: ""
    property string sendPath: ""
    // the shell's picker keeps its last answer; a pick made from the keyboard
    // (or from the test harness) reaches this window the same way
    readonly property string pickedFile: Ui.filePicker && Ui.filePicker.lastPicked && Ui.filePicker.lastPicked.length
        ? Ui.filePicker.lastPicked[0] : ""
    readonly property string chosenFile: win.sendPath !== "" ? win.sendPath : win.pickedFile

    // this screen on the phone
    property string screenArea: "window"
    property string screenTransport: "auto"
    property bool screenTouch: true
    property bool screenTyping: true

    // gadgets: each tool's last result has its own row, never a shared note
    property string nfcWrite: ""
    property string irCode: ""
    property string nfcResult: ""
    property string irResult: ""

    // the phone link
    property string linkAddress: ""

    // lines
    property string accountAddress: ""
    property string accountName: ""
    property string landlineHost: ""
    property string landlineCode: ""

    function refreshAll() { Devices.refresh(); Lines.refresh(); Mirror.refresh(); PhoneTools.refresh(); }
    onVisibleChanged: if (visible) refreshAll()
    Component.onCompleted: refreshAll()

    // Paired phones, read from the two services that already know them. A phone
    // present in both lists is shown once; the link's battery fills the row.
    readonly property var pairedPhones: {
        const seen = {};
        const out = [];
        const add = d => {
            if (!d) return;
            const id = d.id || d.serial || d.name;
            if (!id || seen[id]) return;
            seen[id] = true;
            out.push({
                id: id,
                name: d.name || d.model || id,
                paired: d.paired !== undefined ? !!d.paired : true,
                reachable: d.reachable !== undefined ? !!d.reachable : true,
                battery: typeof d.battery === "number" ? d.battery : -1,
                charging: !!d.charging
            });
        };
        for (const d of Devices.devices) add(d);
        for (const d of Link.devices) add(d);
        for (const d of Phone.devices) add(d);
        const handset = win.androidHandset();
        if (handset) add({ id: handset.name, name: handset.name, paired: true, reachable: true });
        return out;
    }
    // `android info` names the USB handset in one sentence, e.g. "Pixel 7,
    // Android 16 …". The bridge picks the ready phone when the serial is empty.
    function androidHandset() {
        const i = Devices.androidInfo;
        if (i && Array.isArray(i.devices) && i.devices.length) {
            const d = i.devices[0];
            return { name: d.name || d.model || d.serial || "", serial: d.serial || "" };
        }
        const said = typeof i === "string" ? i
            : (i && ((i.info && i.info.text) || i.out)) || "";
        const m = /(?:^|[\s,])([A-Za-z][\w-]*\s+\d+[A-Za-z0-9]*)\s*,?\s*Android\b/.exec(said);
        return m ? { name: m[1], serial: "" } : null;
    }
    function batteryText(d) {
        if (!d || typeof d.battery !== "number" || d.battery < 0) return "";
        return Math.max(0, Math.min(100, d.battery)) + "%"
            + (d.charging ? " · " + Tr.t("charging") : "");
    }

    // The phones adb sees, plus the model the bridge's info line names. An
    // empty serial is honest: the bridge then picks the ready phone itself.
    readonly property var androidCandidates: {
        const out = [];
        const add = (name, serial) => {
            if (!name || out.some(d => d.name === name)) return;
            out.push({ name: name, serial: serial || "" });
        };
        for (const d of Mirror.devices) add(d.name || d.serial, d.serial);
        const handset = win.androidHandset();
        if (handset) add(handset.name, handset.serial);
        const i = Devices.androidInfo;
        if (Array.isArray(i)) for (const d of i) add(win.nameOf(d), win.serialOf(d));
        if (i && Array.isArray(i.devices)) for (const d of i.devices) add(win.nameOf(d), win.serialOf(d));
        for (const d of win.pairedPhones) add(d.name, "");
        return out;
    }
    function nameOf(d) {
        if (typeof d === "string") return d;
        return (d && (d.name || d.model || d.label || d.serial)) || Tr.t("Phone");
    }
    function serialOf(d) {
        if (typeof d === "string") return d;
        return (d && (d.serial || d.id)) || "";
    }
    readonly property string selectedSerial: {
        if (win.phoneName && win.androidCandidates.some(d => d.name === win.phoneName)) {
            const found = win.androidCandidates.find(d => d.name === win.phoneName);
            return found.serial;
        }
        return win.androidCandidates.length ? win.androidCandidates[0].serial : "";
    }
    readonly property var androidApps: Array.isArray(Devices.androidApps)
        ? Devices.androidApps.map(a => typeof a === "string" ? { label: a, value: a }
            : { label: a.name || a.id || "", value: a.id || a.name || "" })
            .filter(a => a.label !== "" && a.value !== "") : []

    function reading(obj, keys) {
        if (!obj || typeof obj !== "object") return "";
        for (const k of keys) if (obj[k] !== undefined && obj[k] !== null && obj[k] !== "") return String(obj[k]);
        return "";
    }
    function batteryLine() {
        const b = Devices.battery;
        if (b && typeof b.level === "number" && b.level >= 0)
            return b.level + "%" + (b.charging ? " · " + Tr.t("charging") : "");
        const v = reading(b, ["percent", "battery", "capacity", "text"]);
        return v !== "" ? v : Tr.t("Not read yet");
    }
    function storageLine() {
        const s = Devices.storage;
        if (s && typeof s === "object" && s.free)
            return Tr.t("%1 free of %2", s.free, s.total || Tr.t("internal storage"));
        const v = reading(s, ["text", "summary", "used", "free"]);
        return v !== "" ? v : Tr.t("Not read yet");
    }

    function stateText(s) {
        if (s === "on") return Tr.t("On");
        if (s === "off") return Tr.t("Off");
        if (!s) return Tr.t("Not read yet");
        return s;              // an honest message from the bridge
    }
    function castingOn() { return Devices.screenState === "on"; }
    // the phone link: a dot says ready or waiting, the row below says which phone
    function linkReady() { return !!(PhoneTools.link && PhoneTools.link.paired); }
    function linkStatusText() {
        const l = PhoneTools.link || {};
        if (l.paired) return Tr.t("Ready");
        if (l.status) return String(l.status);
        return Tr.t("Not connected");
    }
    function linkNote() {
        const l = PhoneTools.link || {};
        return l.note || PhoneTools.note || "";
    }
    function pairLink() {
        const addr = win.linkAddress.trim();
        if (addr === "") { PhoneTools.say(Tr.t("Enter the phone's address first")); return; }
        win.clearResults();
        PhoneTools.linkAction("pair", addr);
        win.linkAddress = "";
    }

    // a new action clears both result rows first: a tag can never sit under IR
    function clearResults() { win.nfcResult = ""; win.irResult = ""; }
    function readTag() { win.clearResults(); Devices.nfc("read"); }
    function writeTag() {
        const text = win.nfcWrite.trim();
        if (text === "") { Devices.say(Tr.t("Enter the text first")); return; }
        win.clearResults();
        Devices.nfc("write", text);
    }
    function sendIr() {
        if (win.irCode === "") { Devices.say(Tr.t("Pick a code first")); return; }
        win.clearResults();
        win.irResult = win.irCode;
        Devices.say("");       // an old note must not survive a new action
        Devices.ir("send", win.irCode);
    }
    Connections {
        target: Devices
        function onNfcTextChanged() { win.nfcResult = Devices.nfcText; }
    }
    function pickIr(value) {
        const v = String(value || "");
        if (v === "") return;
        if (v.indexOf(":") >= 0 || v.indexOf("/") >= 0) { win.irCode = v; return; }
        // a button of the open remote is already a sendable code; a lone remote
        // is sent as-is and its buttons are loaded for the next pick.
        win.irCode = Devices.irRemote !== "" ? Devices.irRemote + ":" + v : v;
        if (Devices.irRemote === "") Devices.ir("list", v);
    }
    function chooseFile() {
        if (!Ui.filePicker) return;
        Ui.filePicker.open({
            "mode": "open",
            "title": Tr.t("Choose a file to send"),
            "onPicked": paths => { if (paths && paths.length) win.sendPath = paths[0]; }
        });
    }
    readonly property var irChoices: Devices.irCodes
        .map(c => typeof c === "string" ? { label: c, value: c }
            : { label: (c.name || c.code || ""), value: String(c.code || c.id || c.name || "") })
        .filter(c => c.label !== "" && c.value !== "")
    function landlineText() {
        const l = Lines.landline;
        if (!l || typeof l !== "object") return "";
        if (l.error) return String(l.error);
        const st = l.state;
        let state = "";
        if (typeof st === "string") state = stateText(st);
        else if (st && typeof st === "object")
            state = st.set_up ? (st.ready ? Tr.t("Ready") : Tr.t("Not ready")) : Tr.t("Not set up");
        return [l.host || l.name || l.number || "", state].filter(x => x).join(" · ");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(10)
        spacing: Theme.px(8)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: win.tabs
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.tab === modelData[0]
                        onClicked: win.tab = modelData[0]
                    }
                }
            }
        }

        Text {
            visible: Devices.note !== "" || Lines.note !== ""
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Devices.note !== "" ? Devices.note : Lines.note
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        BusyNote {
            visible: Devices.busy || Lines.busy
            Layout.fillWidth: true
            note: Tr.t("Working…")
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: sections.implicitHeight
            ColumnLayout {
                id: sections
                width: parent.width
                spacing: Theme.px(12)

                // ---- paired phones and the connect form ----
                ColumnLayout {
                    visible: win.tab === "phones"
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Paired phones")
                        hint: Tr.t("Phones this computer already knows")
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(4)
                            Repeater {
                                model: win.pairedPhones
                                ListRow {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    icon: "phone"
                                    title: modelData.name
                                    subtitle: modelData.reachable ? Tr.t("Connected")
                                        : modelData.paired ? Tr.t("Paired, not nearby") : Tr.t("Nearby")
                                    trailing: win.batteryText(modelData)
                                    interactive: false
                                }
                            }
                            EmptyState {
                                visible: win.pairedPhones.length === 0
                                icon: "phone"
                                title: Tr.t("No paired phones")
                                subtitle: Tr.t("Connect one below")
                            }
                        }
                    }
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Connect a phone")
                        Picks {
                            label: Tr.t("How to connect")
                            options: [
                                { label: Tr.t("Android phone"), value: "android" },
                                { label: Tr.t("Bluetooth device"), value: "bluetooth" },
                                { label: Tr.t("Phone link"), value: "phone" }
                            ]
                            current: win.connectKind
                            onPicked: v => win.connectKind = v
                        }
                        TextField {
                            Layout.fillWidth: true
                            label: Tr.t("Address or code")
                            placeholder: Tr.t("Address or code, if needed")
                            text: win.connectValue
                            onTextChanged: win.connectValue = text
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Button {
                                kind: "primary"
                                text: Tr.t("Connect")
                                enabled: !Devices.busy
                                onClicked: Devices.connect(win.connectKind, win.connectValue)
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }

                // ---- Android tools for the chosen phone ----
                ColumnLayout {
                    visible: win.tab === "android"
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Android phone")
                        hint: Tr.t("Connect it with a cable or over Wi-Fi, then allow this computer")
                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Repeater {
                                model: win.androidCandidates
                                Choice {
                                    required property var modelData
                                    text: modelData.name
                                    selected: win.phoneName !== "" ? win.phoneName === modelData.name
                                        : win.androidCandidates[0] === modelData
                                    onClicked: win.phoneName = modelData.name
                                }
                            }
                        }
                        EmptyState {
                            visible: win.androidCandidates.length === 0
                            icon: "phone"
                            title: Tr.t("No Android phone found")
                            subtitle: Tr.t("Connect one, then look again")
                            actionText: Tr.t("Look again")
                            onAction: Devices.refresh()
                        }
                    }
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("On the phone")
                        hint: Tr.t("Read what the phone reports")
                        ListRow {
                            Layout.fillWidth: true
                            icon: "battery"
                            title: Tr.t("Battery")
                            subtitle: win.batteryLine()
                            interactive: false
                        }
                        ListRow {
                            Layout.fillWidth: true
                            icon: "drive-harddisk"
                            title: Tr.t("Storage")
                            subtitle: win.storageLine()
                            interactive: false
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Button {
                                text: Tr.t("Read battery")
                                enabled: win.androidCandidates.length > 0 && !Devices.busy
                                onClicked: Devices.android("battery", win.selectedSerial)
                            }
                            Button {
                                text: Tr.t("Read storage")
                                enabled: win.androidCandidates.length > 0 && !Devices.busy
                                onClicked: Devices.android("storage", win.selectedSerial)
                            }
                            Button {
                                text: Tr.t("Take a screenshot")
                                enabled: win.androidCandidates.length > 0 && !Devices.busy
                                onClicked: Devices.android("screenshot", win.selectedSerial)
                            }
                            Button {
                                text: Tr.t("Record the screen")
                                enabled: win.androidCandidates.length > 0 && !Devices.busy
                                onClicked: Devices.android("record", win.selectedSerial)
                            }
                        }
                    }
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Open something")
                        TextField {
                            Layout.fillWidth: true
                            label: Tr.t("Web address")
                            placeholder: Tr.t("Web address to open on the phone")
                            mode: "url"
                            text: win.linkUrl
                            onTextChanged: win.linkUrl = text
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Button {
                                text: Tr.t("Use the clipboard")
                                onClicked: win.linkUrl = Quickshell.clipboardText
                            }
                            Item { Layout.fillWidth: true }
                            Button {
                                kind: "primary"
                                text: Tr.t("Open link")
                                enabled: !Devices.busy
                                onClicked: {
                                    const url = win.linkUrl.trim();
                                    if (url === "") { Devices.say(Tr.t("Enter a web address first")); return; }
                                    Devices.android("link", win.selectedSerial, url);
                                }
                            }
                        }
                        Picks {
                            visible: win.androidApps.length > 0
                            label: Tr.t("Apps on the phone")
                            options: win.androidApps
                            current: win.appId
                            onPicked: v => win.appId = v
                        }
                        TextField {
                            Layout.fillWidth: true
                            label: Tr.t("App name or id")
                            placeholder: Tr.t("App name or id, if it is not listed")
                            text: win.appId
                            onTextChanged: win.appId = text
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Item { Layout.fillWidth: true }
                            Button {
                                kind: "primary"
                                text: Tr.t("Open app")
                                enabled: !Devices.busy
                                onClicked: {
                                    const app = win.appId.trim();
                                    if (app === "") { Devices.say(Tr.t("Enter an app name first")); return; }
                                    Devices.android("app", win.selectedSerial, app);
                                }
                            }
                        }
                    }
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Send a file")
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Button { text: Tr.t("Choose a file"); onClicked: win.chooseFile() }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                text: win.chosenFile !== "" ? win.chosenFile.split("/").pop() : Tr.t("No file chosen")
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(12) * Theme.fontScale
                            }
                            Button {
                                kind: "primary"
                                text: Tr.t("Send")
                                enabled: !Devices.busy
                                onClicked: {
                                    if (win.chosenFile === "") { Devices.say(Tr.t("Choose a file first")); return; }
                                    Devices.android("file", win.selectedSerial, win.chosenFile);
                                }
                            }
                        }
                    }
                }

                // ---- this screen on the phone ----
                ColumnLayout {
                    visible: win.tab === "screen"
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("This screen on the phone")
                        hint: Tr.t("The phone shows what you choose, and you work from it")
                        Picks {
                            label: Tr.t("What to show")
                            options: [
                                { label: Tr.t("One window"), value: "window" },
                                { label: Tr.t("The whole screen"), value: "screen" }
                            ]
                            current: win.screenArea
                            onPicked: v => win.screenArea = v
                        }
                        Picks {
                            label: Tr.t("How to reach the phone")
                            options: [
                                { label: Tr.t("Automatic"), value: "auto" },
                                { label: Tr.t("Cable"), value: "usb" },
                                { label: Tr.t("Wi-Fi"), value: "wifi" },
                                { label: Tr.t("Bluetooth"), value: "bluetooth" }
                            ]
                            current: win.screenTransport
                            onPicked: v => win.screenTransport = v
                        }
                        SwitchRow {
                            Layout.fillWidth: true
                            text: Tr.t("Allow touches")
                            hint: Tr.t("Tap on the phone to click here")
                            checked: win.screenTouch
                            onToggled: on => win.screenTouch = on
                        }
                        SwitchRow {
                            Layout.fillWidth: true
                            text: Tr.t("Allow typing")
                            hint: Tr.t("Type on the phone into the focused field")
                            checked: win.screenTyping
                            onToggled: on => win.screenTyping = on
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Button {
                                kind: win.castingOn() ? "danger" : "primary"
                                text: win.castingOn() ? Tr.t("Stop sharing") : Tr.t("Start sharing")
                                enabled: !Devices.busy
                                onClicked: Devices.screen(win.castingOn() ? "stop" : "start",
                                                          win.screenArea + ":" + win.screenTransport,
                                                          win.screenTouch, win.screenTyping)
                            }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: win.stateText(Devices.screenState)
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(12) * Theme.fontScale
                            }
                        }
                    }
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("The same actions from the launcher")
                        hint: Tr.t("Send this window or this whole screen, without a stream")
                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Button {
                                text: Tr.t("Cast this window to the phone")
                                onClicked: Niri.action("set-dynamic-cast-window")
                            }
                            Button {
                                text: Tr.t("Cast this screen to the phone")
                                onClicked: Niri.action("set-dynamic-cast-monitor")
                            }
                            Button {
                                text: Tr.t("Stop casting to the phone")
                                onClicked: Niri.action("clear-dynamic-cast-target")
                            }
                        }
                    }
                }

                // ---- small gadgets ----
                ColumnLayout {
                    visible: win.tab === "gadgets"
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Radio")
                        hint: Tr.t("Listen to FM radio in the media player")
                        Button {
                            Layout.fillWidth: true
                            text: Tr.t("Open FM radio")
                            onClicked: {
                                Radio.sourceChoice = "fm";
                                PlayQueue.open("");
                                PlayQueue.page = "radio";
                            }
                        }
                    }
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Tags")
                        hint: Tr.t("Read what is on a tag, or write a short note to one")
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Button { text: Tr.t("Read a tag"); enabled: !Devices.busy; onClicked: win.readTag() }
                            Item { Layout.fillWidth: true }
                        }
                        TextField {
                            Layout.fillWidth: true
                            label: Tr.t("Text to write")
                            placeholder: Tr.t("Short text to write to a tag")
                            text: win.nfcWrite
                            onTextChanged: win.nfcWrite = text
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Item { Layout.fillWidth: true }
                            Button {
                                kind: "primary"
                                text: Tr.t("Write to a tag")
                                enabled: win.nfcWrite.trim() !== "" && !Devices.busy
                                onClicked: win.writeTag()
                            }
                        }
                        ListRow {
                            Layout.fillWidth: true
                            interactive: false
                            icon: "preferences-system"
                            title: Tr.t("Last tag")
                            subtitle: win.nfcResult !== "" ? Tr.t("Read from a tag") : Tr.t("No tag read yet")
                            trailing: win.nfcResult
                        }
                    }
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Remote")
                        hint: Tr.t("Pick a code, then send it")
                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Repeater {
                                model: win.irChoices
                                Choice {
                                    required property var modelData
                                    text: modelData.label
                                    selected: win.irCode === modelData.value
                                    onClicked: win.pickIr(modelData.value)
                                }
                            }
                        }
                        EmptyState {
                            visible: win.irChoices.length === 0
                            icon: "input-keyboard"
                            title: Tr.t("No codes yet")
                            subtitle: Tr.t("Ask the remote for its list")
                            actionText: Tr.t("Look for codes")
                            onAction: { win.clearResults(); Devices.ir("list"); }
                        }
                        ListRow {
                            Layout.fillWidth: true
                            interactive: false
                            icon: "input-keyboard"
                            title: Tr.t("Last code")
                            subtitle: win.irResult !== "" ? Tr.t("Sent to the remote") : Tr.t("No code sent yet")
                            trailing: win.irResult
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Button { text: Tr.t("Look for codes"); onClicked: { win.clearResults(); Devices.ir("list"); } }
                            Item { Layout.fillWidth: true }
                            Button {
                                kind: "primary"
                                text: Tr.t("Send code")
                                enabled: !Devices.busy
                                onClicked: win.sendIr()
                            }
                        }
                    }
                }

                // ---- the phone link: pair, find, and the phones within reach ----
                ColumnLayout {
                    visible: win.tab === "phone"
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    onVisibleChanged: if (visible) { Phone.search(); PhoneTools.refresh(); }

                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Phone link")
                        hint: Tr.t("Send files to your phone over the same Wi-Fi, with its share settings open")
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(8)
                            Rectangle {
                                width: Theme.px(10)
                                height: Theme.px(10)
                                radius: Theme.px(5)
                                color: win.linkReady() ? Theme.success : Theme.faint
                                Accessible.name: win.linkStatusText()
                            }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: win.linkStatusText()
                                color: win.linkReady() ? Theme.success : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(12) * Theme.fontScale
                            }
                        }
                        ListRow {
                            Layout.fillWidth: true
                            interactive: false
                            icon: "phone"
                            title: (PhoneTools.link && PhoneTools.link.name) || Tr.t("No phone paired")
                            subtitle: (PhoneTools.link && PhoneTools.link.address) || ""
                            trailing: Phone.batteryText(Phone.phone)
                        }
                        BusyNote {
                            Layout.fillWidth: true
                            visible: PhoneTools.busy
                            note: Tr.t("Working…")
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: win.linkNote() !== ""
                            wrapMode: Text.Wrap
                            text: win.linkNote()
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                        }
                    }

                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Pair a phone")
                        hint: Tr.t("Open your phone's share settings, then pair it here")
                        TextField {
                            Layout.fillWidth: true
                            label: Tr.t("Phone address")
                            placeholder: Tr.t("Address shown on the phone, if asked for")
                            text: win.linkAddress
                            onTextChanged: win.linkAddress = text
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Button {
                                kind: "primary"
                                text: Tr.t("Pair another phone")
                                enabled: !PhoneTools.busy
                                onClicked: win.pairLink()
                            }
                            Item { Layout.fillWidth: true }
                        }
                        ConfirmButton {
                            value: "link"
                            implicitWidth: Math.max(Theme.touchTarget, Tr.t("Forget this phone").length * 8 + 28)
                            implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                            text: Tr.t("Forget this phone")
                            armedText: Tr.t("Tap again to forget")
                            kind: "danger"
                            Accessible.name: Tr.t("Forget this phone")
                            enabled: !PhoneTools.busy
                            onConfirmed: PhoneTools.linkAction("forget")
                        }
                    }

                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Find a phone")
                        hint: Tr.t("Let the phone see this computer, then look for it here")
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Button {
                                text: Tr.t("Look for phones")
                                enabled: !PhoneTools.busy
                                onClicked: { PhoneTools.linkAction("find"); Phone.search(); }
                            }
                            Item { Layout.fillWidth: true }
                        }
                        SwitchRow {
                            Layout.fillWidth: true
                            text: Tr.t("Make this computer findable")
                            hint: Tr.t("Announce this computer so a phone can pair with it")
                            checked: !!(PhoneTools.link && PhoneTools.link.findable)
                            enabled: !PhoneTools.busy
                            onToggled: on => PhoneTools.linkAction("findable", on ? "on" : "off")
                        }
                    }

                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Phones nearby")
                        hint: Tr.t("Phones this computer can reach right now")
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(4)
                            Repeater {
                                model: Phone.devices
                                ColumnLayout {
                                    id: nearPhone
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Theme.px(2)
                                    ListRow {
                                        Layout.fillWidth: true
                                        icon: "phone"
                                        title: nearPhone.modelData.name
                                        subtitle: nearPhone.modelData.paired
                                            ? (nearPhone.modelData.reachable ? Tr.t("Connected") : Tr.t("Paired, not nearby"))
                                            : Tr.t("Nearby")
                                        trailing: Phone.batteryText(nearPhone.modelData)
                                        selected: nearPhone.modelData.paired && nearPhone.modelData.reachable
                                        onClicked: if (!nearPhone.modelData.paired) Phone.pair(nearPhone.modelData.id)
                                        ConfirmButton {
                                            visible: nearPhone.modelData.paired
                                            icon: "edit-delete"
                                            size: Theme.px(22)
                                            tip: Tr.t("Unpair %1", nearPhone.modelData.name)
                                            Accessible.name: Tr.t("Unpair %1", nearPhone.modelData.name)
                                            kind: "danger"
                                            enabled: !PhoneTools.busy
                                            onConfirmed: Phone.unpair(nearPhone.modelData.id)
                                        }
                                    }
                                    RowLayout {
                                        visible: nearPhone.modelData.paired && nearPhone.modelData.reachable
                                        Layout.leftMargin: Theme.px(40)
                                        spacing: Theme.px(6)
                                        Button { text: Tr.t("Ring"); onClicked: Phone.ring(nearPhone.modelData.id) }
                                        Button { text: Tr.t("Ping"); onClicked: Phone.ping(nearPhone.modelData.id) }
                                        Button { text: Tr.t("Send clipboard"); onClicked: Phone.sendClipboard(nearPhone.modelData.id) }
                                    }
                                }
                            }
                            EmptyState {
                                visible: Phone.devices.length === 0
                                icon: "phone"
                                title: Tr.t("No phone found yet")
                                subtitle: Tr.t("Open the share settings on your phone, then look for phones")
                                actionText: Tr.t("Look for phones")
                                onAction: { PhoneTools.linkAction("find"); Phone.search(); }
                            }
                        }
                    }
                }

                // ---- phone lines and the desk phone ----
                ColumnLayout {
                    visible: win.tab === "lines"
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Phone lines")
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(4)
                            Repeater {
                                model: Lines.lines
                                ListRow {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    icon: "call-start"
                                    title: modelData.name || modelData.id || Tr.t("Line")
                                    subtitle: modelData.ready ? Tr.t("Ready") : Tr.t("Not ready")
                                    trailing: modelData.kind || ""
                                    interactive: false
                                }
                            }
                            EmptyState {
                                visible: Lines.lines.length === 0
                                icon: "call-start"
                                title: Tr.t("No phone lines")
                                subtitle: Tr.t("Add an account below")
                            }
                        }
                    }
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Accounts")
                        hint: Tr.t("Add the account your phone service gave you")
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(4)
                            Repeater {
                                model: Lines.accounts
                                ListRow {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    icon: "x-office-address-book"
                                    title: modelData.name || modelData.address || modelData.id || Tr.t("Account")
                                    subtitle: modelData.ready ? Tr.t("Ready") : ""
                                    ConfirmButton {
                                        value: String(modelData.id || modelData.address || "")
                                        implicitWidth: Math.max(Theme.touchTarget, Tr.t("Remove").length * 8 + 28)
                                        implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                                        text: Tr.t("Remove")
                                        armedText: Tr.t("Tap again to remove")
                                        kind: "danger"
                                        Accessible.name: Tr.t("Remove account %1", modelData.name || modelData.address || "")
                                        enabled: !Lines.busy
                                        onConfirmed: Lines.removeAccount(value)
                                    }
                                }
                            }
                        }
                        TextField {
                            Layout.fillWidth: true
                            label: Tr.t("Address")
                            placeholder: Tr.t("Account address")
                            text: win.accountAddress
                            onTextChanged: win.accountAddress = text
                        }
                        TextField {
                            Layout.fillWidth: true
                            label: Tr.t("Name")
                            placeholder: Tr.t("Name for this account, if you want one")
                            text: win.accountName
                            onTextChanged: win.accountName = text
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Item { Layout.fillWidth: true }
                            Button {
                                kind: "primary"
                                text: Tr.t("Add account")
                                enabled: win.accountAddress.trim() !== "" && !Lines.busy
                                onClicked: {
                                    Lines.addAccount({ address: win.accountAddress.trim(), name: win.accountName.trim() });
                                    win.accountAddress = "";
                                    win.accountName = "";
                                }
                            }
                        }
                    }
                    SettingsSection {
                        Layout.fillWidth: true
                        title: Tr.t("Desk phone")
                        hint: Tr.t("Connect it once, then it is ready for calls")
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            visible: win.landlineText() !== ""
                            text: win.landlineText()
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                        }
                        TextField {
                            Layout.fillWidth: true
                            label: Tr.t("Desk phone address")
                            placeholder: Tr.t("Address of the desk phone")
                            text: win.landlineHost
                            onTextChanged: win.landlineHost = text
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Item { Layout.fillWidth: true }
                            Button {
                                text: Tr.t("Connect desk phone")
                                enabled: win.landlineHost.trim() !== "" && !Lines.busy
                                onClicked: Lines.landlineSetup(win.landlineHost.trim())
                            }
                        }
                        TextField {
                            Layout.fillWidth: true
                            label: Tr.t("Code")
                            placeholder: Tr.t("Code shown on the desk phone")
                            text: win.landlineCode
                            onTextChanged: win.landlineCode = text
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Button {
                                text: Tr.t("Finish setup")
                                enabled: win.landlineCode.trim() !== "" && !Lines.busy
                                onClicked: { Lines.landlineFinish(win.landlineCode.trim()); win.landlineCode = ""; }
                            }
                            Item { Layout.fillWidth: true }
                            ConfirmButton {
                                value: "landline"
                                implicitWidth: Math.max(Theme.touchTarget, Tr.t("Forget desk phone").length * 8 + 28)
                                implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                                text: Tr.t("Forget desk phone")
                                armedText: Tr.t("Tap again to forget")
                                kind: "danger"
                                Accessible.name: Tr.t("Forget the desk phone")
                                enabled: !Lines.busy
                                onConfirmed: Lines.landlineForget()
                            }
                        }
                    }
                }
            }
        }
    }
}
