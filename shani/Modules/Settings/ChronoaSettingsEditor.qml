// Settings > Chronoa: the engine's own settings, drawn from SettingsList.
// Rows are picked by click; typing is only for a key or a custom value. A
// change the engine would refuse without consent asks before it is sent.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services
import "ChronoaSettings.js" as Words

ColumnLayout {
    id: root
    property bool active: true
    onActiveChanged: if (active) ChronoaSettings.refresh()
    Component.onCompleted: if (active) ChronoaSettings.refresh()

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Settings on this machine")
        hint: Tr.t("Read from the local engine. Nothing typed here is shown back to you.")
        BusyNote { Layout.fillWidth: true; visible: ChronoaSettings.busy; note: Tr.t("Reading…"); iconSize: Theme.px(16) }
        InfoBanner {
            Layout.fillWidth: true
            visible: ChronoaSettings.error !== ""
            tone: "error"
            text: ChronoaSettings.error
            Accessible.role: Accessible.AlertMessage
        }
        EmptyState {
            visible: !ChronoaSettings.busy && ChronoaSettings.ready && ChronoaSettings.described.length === 0
            icon: "preferences-system"
            title: Tr.t("Nothing to show")
            subtitle: Tr.t("The engine did not report any settings.")
        }
    }

    Repeater {
        model: Words.groups()
        ColumnLayout {
            id: groupBox
            required property var modelData
            Layout.fillWidth: true
            visible: ChronoaSettings.described.some(d => d.group === groupBox.modelData.id)
            SectionTitle { Layout.fillWidth: true; text: Tr.t(groupBox.modelData.label) }
            Repeater {
                model: ChronoaSettings.described.filter(d => d.group === groupBox.modelData.id)
                ColumnLayout {
                    id: settingRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.px(2)

                    SwitchRow {
                        Layout.fillWidth: true
                        visible: settingRow.modelData.kind === "bool"
                        text: Tr.t(settingRow.modelData.label)
                        hint: settingRow.modelData.consent ? Tr.t("Asks before it is turned on") : ""
                        checked: Words.isOn(settingRow.modelData.value)
                        onToggled: on => ChronoaSettings.ask(settingRow.modelData.name, on)
                    }

                    Picks {
                        Layout.fillWidth: true
                        visible: !!settingRow.modelData.choices
                        label: Tr.t(settingRow.modelData.label)
                        options: settingRow.modelData.choices
                            ? settingRow.modelData.choices.map(o => ({ label: Tr.t(o.label), value: o.value })) : []
                        current: settingRow.modelData.value
                        onPicked: v => ChronoaSettings.ask(settingRow.modelData.name, v)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: settingRow.modelData.kind !== "bool" && !settingRow.modelData.choices
                        spacing: Theme.px(6)
                        TextField {
                            id: customValue
                            Layout.fillWidth: true
                            label: Tr.t(settingRow.modelData.label)
                            placeholder: settingRow.modelData.secret ? Tr.t("Type a key to save")
                                                                     : Tr.t("Type a value to save")
                            // A secret's stored value is never shown, not even masked.
                            text: settingRow.modelData.secret ? "" : String(settingRow.modelData.value === undefined ? "" : settingRow.modelData.value)
                            secret: settingRow.modelData.secret
                        }
                        Button {
                            text: Tr.t("Save")
                            enabled: customValue.text.trim() !== ""
                            onClicked: {
                                ChronoaSettings.ask(settingRow.modelData.name, customValue.text.trim());
                                if (settingRow.modelData.secret) customValue.text = "";
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Ways of working")
        hint: Tr.t("Each one changes several of the switches above, so it asks first.")
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: Words.presets()
                Button {
                    required property var modelData
                    text: Tr.t(modelData.label)
                    onClicked: ChronoaSettings.askPreset(modelData.value)
                }
            }
        }
    }

    Dialog {
        id: confirmDialog
        title: Tr.t("Are you sure?")
        visible: ChronoaSettings.pending !== null
        modal: true
        standardButtons: Dialog.No | Dialog.Yes
        onAccepted: ChronoaSettings.confirm()
        onRejected: ChronoaSettings.cancel()
        contentItem: Text {
            wrapMode: Text.Wrap
            text: ChronoaSettings.pending && ChronoaSettings.pending.kind === "preset"
                ? Tr.t("Apply this set of permissions? Some switches will be turned on.")
                : Tr.t("Save this change? The engine will store it and may grant access.")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(13) * Theme.fontScale
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
    }
}
