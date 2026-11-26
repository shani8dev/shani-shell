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
        Phone.search();
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
            onClicked: { Link.refresh(); Phone.search(); }
        }
        EmptyState {
            visible: Link.devices.length === 0 && Phone.devices.length === 0
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
            model: Phone.devices
            ListRow {
                id: phoneRow
                required property var modelData
                // the same device can be in both lists; show it once
                visible: !Link.devices.some(d => d.id === phoneRow.modelData.id)
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
        hint: Tr.t("Pick what you want to connect, then give its address if you know it.")
        Picks {
            label: Tr.t("What to connect")
            options: [
                { label: Tr.t("Phone by cable"), value: "android" },
                { label: Tr.t("Bluetooth device"), value: "bluetooth" },
                { label: Tr.t("Phone nearby"), value: "phone" }
            ]
            current: page.connectKind
            onPicked: v => page.connectKind = v
        }
        TextField {
            id: addressField
            Layout.fillWidth: true
            label: Tr.t("Address")
            placeholder: Tr.t("Optional — address or code, if needed")
        }
        Button {
            text: Tr.t("Connect")
            kind: "primary"
            enabled: !Devices.busy
            onClicked: Devices.connect(page.connectKind, addressField.text.trim())
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
}
