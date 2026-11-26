// Settings > Power: the UPS a desktop runs on (Services/Ups, NUT), when there is one -
// on mains or on its battery, its charge, how long it would last, how loaded it is.
// Below it: the shutdown policy read and written through the same bridge.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    property bool active: false
    spacing: Theme.px(6)
    onActiveChanged: if (active) { Ups.refresh(); Ups.loadPolicy(); }
    Component.onCompleted: if (active) { Ups.refresh(); Ups.loadPolicy(); page.syncPolicy(); }

    // The live view stays as it was; it only exists when a UPS answers.
    ColumnLayout {
        visible: Ups.present
        Layout.fillWidth: true
        spacing: Theme.px(6)
        SectionTitle { objectName: "ups"; Layout.fillWidth: true; text: Tr.t("UPS") }
        Text {
            Layout.fillWidth: true
            text: Ups.info.model || Ups.info.name || ""
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(13) * Theme.fontScale
            font.weight: Font.DemiBold
        }
        Text {
            Layout.fillWidth: true
            text: [Ups.low ? Tr.t("On its battery - low") : Ups.onBattery ? Tr.t("On its battery: the power is out") : Tr.t("On mains power"),
                   Ups.says(Ups.info),
                   Ups.info.load !== null && Ups.info.load !== undefined ? Tr.t("load %1%", Math.round(Ups.info.load)) : ""].filter(x => x).join("  ·  ")
            color: Ups.low ? Theme.danger : (Ups.onBattery ? Theme.accent : Theme.dim)
            wrapMode: Text.WordWrap
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        // the charge, as a bar
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            implicitHeight: Theme.px(6)
            radius: Theme.px(3)
            color: Theme.hover
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, (Ups.info.charge || 0) / 100))
                height: parent.height
                radius: Theme.px(3)
                color: Ups.low ? Theme.danger : Theme.accent
            }
        }
    }

    // ---- Shutdown policy: values from the bridge, words here ----------------
    readonly property var defaults: ({
        MINSUPPLIES: "1",
        SHUTDOWNCMD: '"/sbin/shutdown -h +0"',
        POWERDOWNFLAG: "/etc/killpower",
        DEADTIME: "15",
        FINALDELAY: "0",
        POLLFREQ: "5",
        POLLFREQALERT: "5"
    })
    readonly property var fields: [
        { key: "MINSUPPLIES", label: Tr.t("UPS units needed"), options: [1, 2, 3, 4], min: 1, max: 8, unit: "" },
        { key: "DEADTIME", label: Tr.t("Time without a UPS before shutdown"), options: [5, 15, 30, 60], min: 1, max: 600, unit: Tr.t("sec") },
        { key: "FINALDELAY", label: Tr.t("Wait before shutting down"), options: [0, 5, 15, 30], min: 0, max: 600, unit: Tr.t("sec") },
        { key: "POLLFREQ", label: Tr.t("Check interval on mains"), options: [2, 5, 10, 30], min: 1, max: 600, unit: Tr.t("sec") },
        { key: "POLLFREQALERT", label: Tr.t("Check interval on battery"), options: [2, 5, 10, 30], min: 1, max: 600, unit: Tr.t("sec") },
        { key: "SHUTDOWNCMD", label: Tr.t("Shutdown command"), hint: Tr.t("Put the command in quotes.") },
        { key: "POWERDOWNFLAG", label: Tr.t("Power-off flag file"), hint: Tr.t("Give a full path to a file.") }
    ]
    property var draft: ({})

    function syncPolicy() {
        const d = Object.assign({}, page.defaults);
        const keys = (Ups.policy && Ups.policy.keys) || {};
        for (const k of Object.keys(d)) if (keys[k]) d[k] = String(keys[k]);
        page.draft = d;
    }
    function setDraft(key, value) {
        const d = Object.assign({}, page.draft);
        d[key] = String(value);
        page.draft = d;
    }
    Connections { target: Ups; function onPolicyChanged() { page.syncPolicy(); } }

    function fieldError(f) {
        const v = String(page.draft[f.key] || "").trim();
        if (f.min !== undefined) {
            if (!/^\d+$/.test(v) || Number(v) < f.min || Number(v) > f.max)
                return Tr.t("Use a whole number between %1 and %2", f.min, f.max);
        } else if (v !== "") {
            if (f.key === "SHUTDOWNCMD" && !(v.startsWith('"') && v.endsWith('"')))
                return Tr.t("Put the command in quotes.");
            if (f.key === "POWERDOWNFLAG" && !v.startsWith("/"))
                return Tr.t("Start with / for a full path.");
        }
        return "";
    }
    property bool policyValid: page.fields.every(f => page.fieldError(f) === "")

    function policyPayload() {
        const out = {};
        for (const f of page.fields) out[f.key] = String(page.draft[f.key] || "").trim();
        return out;
    }

    SettingsSection {
        Layout.fillWidth: true
        Layout.topMargin: Theme.px(8)
        title: Tr.t("Shutdown policy")
        hint: Tr.t("Choose a common value, or type your own.")

        ListRow {
            Layout.fillWidth: true; interactive: false
            icon: "system-shutdown"
            title: Tr.t("Monitor service")
            subtitle: Ups.policy.service === "active" ? Tr.t("Running")
                    : Ups.policy.service === "inactive" ? Tr.t("Not running") : Tr.t("Unknown")
        }
        ListRow {
            Layout.fillWidth: true; interactive: false
            icon: "battery"
            title: Tr.t("UPS being watched")
            subtitle: Ups.policy.monitored || Tr.t("None")
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: Ups.policyLoaded && (!Ups.policy.present || !!Ups.policy.error)
            tone: "warn"
            title: Tr.t("The shutdown settings could not be read")
            text: Tr.t("You can still choose values and save them.")
        }

        Repeater {
            model: page.fields
            ColumnLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text {
                    Layout.fillWidth: true
                    text: row.modelData.label
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                Picks {
                    visible: row.modelData.options !== undefined
                    label: ""
                    options: row.modelData.options
                        ? row.modelData.options.map(v => ({ label: row.modelData.unit ? String(v) + " " + row.modelData.unit : String(v), value: String(v) }))
                                               .concat([{ label: Tr.t("Other"), value: "__other" }])
                        : []
                    current: row.modelData.options && row.modelData.options.map(String).indexOf(String(page.draft[row.modelData.key])) >= 0
                             ? String(page.draft[row.modelData.key]) : "__other"
                    onPicked: v => {
                        if (v === "__other") custom.forceActiveFocus();
                        else page.setDraft(row.modelData.key, v);
                    }
                }
                TextField {
                    id: custom
                    Layout.fillWidth: true
                    label: row.modelData.label + " " + Tr.t("custom value")
                    placeholder: row.modelData.options ? Tr.t("Or type a value") : row.modelData.label
                    mode: row.modelData.options ? "digits" : ""
                    text: String(page.draft[row.modelData.key] || "")
                    error: page.fieldError(row.modelData)
                    onTextChanged: page.setDraft(row.modelData.key, text)
                }
                Text {
                    Layout.fillWidth: true
                    visible: !!row.modelData.hint
                    text: row.modelData.hint || ""
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: Tr.t("This software has no battery-percentage threshold. The policy decides when shutdown starts. A scanner can help find a UPS that is not set up yet.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        Text {
            Layout.fillWidth: true
            text: Tr.t("Saving needs administrator rights: this computer must know when to shut down safely.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(8)
            ConfirmButton {
                implicitWidth: Theme.px(190)
                implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                text: Tr.t("Save shutdown policy")
                armedText: Tr.t("Tap again to save the policy")
                Accessible.name: Tr.t("Save shutdown policy; needs administrator rights")
                enabled: !Ups.policyBusy && page.policyValid
                onConfirmed: Ups.savePolicy(page.policyPayload())
            }
            Button {
                text: Tr.t("Reload")
                Accessible.name: Tr.t("Reload the shutdown policy")
                enabled: !Ups.policyBusy
                onClicked: Ups.loadPolicy()
            }
            Item { Layout.fillWidth: true }
        }
        BusyNote {
            visible: Ups.policyBusy
            Layout.fillWidth: true
            note: Tr.t("Saving the shutdown policy...")
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: Ups.policyNote !== ""
            tone: Ups.policyNoteOk ? "ok" : "error"
            text: Ups.policyNote
        }
    }
}
