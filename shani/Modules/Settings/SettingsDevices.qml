// Settings > Devices: phones and other devices this computer knows, connecting
// a new one, showing this screen on a phone, and the small radio gadgets.
// Services/Devices owns the actual work; every value here is picked with a
// tap, with typing only for a custom address, station or code.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    property string connectKind: "phone"
    property string screenMode: "window"
    property bool screenTouch: true
    property bool screenTyping: false
    property real fmFrequency: 98.5
    property bool fmCustom: false
    property string irSelected: ""
    readonly property var irChoices: Devices.irCodes.map(c => typeof c === "string"
        ? { label: c, value: c }
        : { label: String((c && (c.name || c.code)) || ""), value: String((c && (c.code || c.id || c.name)) || "") })
        .filter(c => c.label !== "" && c.value !== "")

    onActiveChanged: if (active) page.load()
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) page.load()
    function load() {
        Devices.refresh();
        Devices.ir("list", "");        // the refresh does not ask the remote for its codes
        Link.refresh();
        AndroidTools.refresh();
        AndroidTools.run("find", []);
    }

    // A phone the native tools can reach: cable or Wi-Fi debugging, with adb's
    // battery line split into a number and its charging flag.
    readonly property var androidRows: {
        const s = AndroidTools.result.state || ({});
        if (!s.paired) return [];
        const match = /^(\d+)%/.exec(String(s.battery || ""));
        return [{
            id: String(s.serial || s.name || "phone"),
            name: String(s.name || ""),
            paired: true,
            reachable: true,
            battery: match ? parseInt(match[1], 10) : -1,
            charging: /charging/i.test(String(s.battery || ""))
        }];
    }
    readonly property var nearbyPhones: {
        const r = AndroidTools.result.find || ({});
        return Array.isArray(r.devices) ? r.devices : [];
    }

    function deviceSubtitle(d) {
        const state = d.paired ? (d.reachable ? Tr.t("Connected") : Tr.t("Paired · not nearby")) : Tr.t("Nearby");
        const battery = (typeof d.battery === "number" && d.battery >= 0) ? " · " + d.battery + "%" : "";
        return state + battery;
    }
    function stateText(s) {
        if (s === "running" || s === "on") return Tr.t("On");
        if (s === "stopped" || s === "off") return Tr.t("Off");
        if (!s) return Tr.t("Not read yet");
        return String(s);              // an honest answer from the bridge
    }
    function screenActive() {
        return Devices.screenState === "running" || Devices.screenState === "on";
    }
    function screenText() { return page.stateText(Devices.screenState); }
    // the bridge takes the area plus the touch and typing switches separately
    function screenModeValue() { return page.screenMode; }
    function fmActive() {
        return Devices.fmState === "running" || Devices.fmState === "on";
    }
    function fmText() {
        return fmActive() ? Tr.t("Playing at %1", Devices.fmFrequency)
                          : page.stateText(Devices.fmState);
    }
    function nfcText() {
        const t = Devices.nfcText || "";
        return String(t) !== "" ? Tr.t("Last read: %1", String(t)) : Tr.t("Nothing has been read from a tag yet");
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Paired devices")
        hint: Tr.t("Phones and other devices this computer knows about.")
        Button {
            text: Tr.t("Open Devices")
            onClicked: Ui.openTool("devices")
        }
        Button {
            text: Tr.t("Look again")
            onClicked: { Link.refresh(); Devices.refresh(); AndroidTools.refresh(); AndroidTools.run("find", []); }
        }
        EmptyState {
            visible: Link.devices.length === 0 && page.androidRows.length === 0
            icon: "phone"
            title: Tr.t("No devices found")
            subtitle: Tr.t("Wake the device, make sure it is on the same network, then choose Look again.")
        }
        Repeater {
            model: Link.devices
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: "phone"
                title: modelData.name || modelData.id || Tr.t("Unnamed device")
                subtitle: page.deviceSubtitle(modelData)
            }
        }
        Repeater {
            model: page.androidRows
            ListRow {
                id: phoneRow
                required property var modelData
                // the same phone can be in both lists; show it once
                visible: !Link.devices.some(d => d.name === phoneRow.modelData.name && phoneRow.modelData.name !== "")
                Layout.fillWidth: true
                interactive: false
                icon: "phone"
                title: modelData.name || modelData.id || Tr.t("Unnamed device")
                subtitle: page.deviceSubtitle(modelData)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Connect a device")
        hint: Tr.t("Pair one below with Bluetooth or Wi-Fi debugging")
        Picks {
            label: Tr.t("What to connect")
            options: [
                { label: Tr.t("Phone by cable"), value: "cable" },
                { label: Tr.t("Bluetooth device"), value: "bluetooth" },
                { label: Tr.t("Wi-Fi debugging"), value: "wifi" }
            ]
            current: page.connectKind
            onPicked: v => page.connectKind = v
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: page.connectKind === "cable"
            text: Tr.t("Connect an Android phone by USB or Wi-Fi debugging (Developer options), then allow this computer on the phone.")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        // phones the native tools found; typing a custom address stays possible
        Flow {
            Layout.fillWidth: true
            visible: page.connectKind === "bluetooth"
            spacing: Theme.px(6)
            Repeater {
                model: page.nearbyPhones.filter(d => d.kind === "bluetooth")
                Choice {
                    required property var modelData
                    text: modelData.name || modelData.address
                    selected: addressField.text === modelData.address
                    onClicked: addressField.text = modelData.address
                }
            }
        }
        TextField {
            id: addressField
            Layout.fillWidth: true
            visible: page.connectKind !== "cable"
            label: Tr.t("Address")
            placeholder: Tr.t("Address or code, if needed")
        }
        TextField {
            id: codeField
            Layout.fillWidth: true
            visible: page.connectKind === "wifi"
            label: Tr.t("Pairing code")
            placeholder: Tr.t("The six-digit code shown on the phone")
        }
        Button {
            text: page.connectKind === "cable" ? Tr.t("Look again") : Tr.t("Connect")
            kind: "primary"
            enabled: !Devices.busy && (page.connectKind === "cable" || (addressField.text.trim() !== ""
                && (page.connectKind !== "wifi" || codeField.text.trim() !== "")))
            onClicked: {
                const addr = addressField.text.trim();
                if (page.connectKind === "cable") {
                    Devices.refresh(); Link.refresh(); AndroidTools.refresh();
                } else if (page.connectKind === "wifi") {
                    Devices.connect("android", addr, codeField.text.trim());
                } else {
                    Devices.connect("bluetooth", addr);
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("This screen on the phone")
        hint: Tr.t("Show the whole screen, or just one window. Touch and typing can be turned off if you only want to watch.")
        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: page.screenText()
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        Picks {
            label: Tr.t("Show")
            options: [
                { label: Tr.t("One window"), value: "window" },
                { label: Tr.t("Whole screen"), value: "screen" }
            ]
            current: page.screenMode
            onPicked: v => page.screenMode = v
        }
        SwitchRow {
            Layout.fillWidth: true
            text: Tr.t("Touch from the phone")
            hint: Tr.t("A tap on the phone acts like a tap here")
            checked: page.screenTouch
            onToggled: on => page.screenTouch = on
        }
        SwitchRow {
            Layout.fillWidth: true
            text: Tr.t("Typing from the phone")
            hint: Tr.t("The phone's keyboard can type here")
            checked: page.screenTyping
            onToggled: on => page.screenTyping = on
        }
        Button {
            text: page.screenActive() ? Tr.t("Stop showing") : Tr.t("Start showing")
            kind: page.screenActive() ? "plain" : "primary"
            enabled: !Devices.busy
            onClicked: Devices.screen(page.screenActive() ? "stop" : "start", page.screenModeValue(), page.screenTouch, page.screenTyping)
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Radio gadgets")
        hint: Tr.t("A radio station, a tag you can tap, and codes for a remote.")
        SectionTitle { Layout.fillWidth: true; text: Tr.t("FM radio") }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: page.fmText()
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        Picks {
            label: Tr.t("Station")
            options: [
                { label: "88.5", value: 88.5 },
                { label: "91.5", value: 91.5 },
                { label: "94.5", value: 94.5 },
                { label: "98.5", value: 98.5 },
                { label: "101.5", value: 101.5 },
                { label: "104.5", value: 104.5 },
                { label: "107.5", value: 107.5 },
                { label: Tr.t("Other…"), value: "" }
            ]
            current: page.fmCustom ? "" : page.fmFrequency
            onPicked: v => {
                page.fmCustom = (v === "");
                if (!page.fmCustom) { page.fmFrequency = v; fmField.text = ""; }
            }
        }
        TextField {
            id: fmField
            Layout.fillWidth: true
            visible: page.fmCustom
            label: Tr.t("Frequency")
            placeholder: Tr.t("Type a frequency")
            onAccepted: {
                const n = parseFloat(text.trim().replace(",", "."));
                if (!isNaN(n) && n > 0) { page.fmFrequency = n; page.fmCustom = false; text = ""; }
            }
        }
        Button {
            text: page.fmActive() ? Tr.t("Stop FM") : Tr.t("Start FM")
            enabled: !Devices.busy
            onClicked: Devices.fm(page.fmActive() ? "stop" : "start", String(page.fmFrequency))
        }

        SectionTitle { Layout.fillWidth: true; text: Tr.t("Tags you can tap") }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: page.nfcText()
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        TextField {
            id: nfcField
            Layout.fillWidth: true
            label: Tr.t("Text for a tag")
            placeholder: Tr.t("What to write when you put a tag on the reader")
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Button {
                text: Tr.t("Read a tag")
                onClicked: Devices.nfc("read", "")
            }
            Button {
                text: Tr.t("Write to a tag")
                enabled: nfcField.text.trim() !== ""
                onClicked: Devices.nfc("write", nfcField.text.trim())
            }
        }

        SectionTitle { Layout.fillWidth: true; text: Tr.t("Remote codes") }
        EmptyState {
            visible: page.irChoices.length === 0
            icon: "input-keyboard"
            title: Tr.t("No codes yet")
            subtitle: Tr.t("Ask the remote for its list, or type one below.")
            actionText: Tr.t("Look for codes")
            onAction: Devices.ir("list", "")
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: page.irChoices
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: page.irSelected === modelData.value
                    onClicked: page.irSelected = modelData.value
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Button { text: Tr.t("Look for codes"); enabled: !Devices.busy; onClicked: Devices.ir("list", "") }
            Item { Layout.fillWidth: true }
        }
        TextField {
            id: irField
            Layout.fillWidth: true
            label: Tr.t("Code")
            placeholder: Tr.t("Or type one, like lamp:on")
            onTextChanged: if (text !== "") page.irSelected = ""
        }
        Button {
            text: Tr.t("Send")
            kind: "primary"
            enabled: (page.irSelected !== "" || irField.text.trim() !== "") && !Devices.busy
            onClicked: Devices.ir("send", page.irSelected !== "" ? page.irSelected : irField.text.trim())
        }
    }

    BusyNote {
        Layout.fillWidth: true
        visible: Devices.busy
        note: Tr.t("Asking the devices…")
    }
    InfoBanner {
        Layout.fillWidth: true
        visible: Devices.note !== ""
        tone: "info"
        text: Devices.note
    }
    InfoBanner {
        Layout.fillWidth: true
        visible: AndroidTools.note !== ""
        tone: "info"
        text: AndroidTools.note
    }
}
