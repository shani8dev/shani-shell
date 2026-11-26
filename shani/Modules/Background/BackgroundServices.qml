// Background work: the phone, watch and music that keeps going with every
// window closed. Services/PhoneTools owns the switches and their keys; this
// window only groups the same list and toggles it. Settings keeps a link here
// instead of a second copy of the switch rows.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Background"
    visible: Ui.backgroundServices
    onGone: Ui.backgroundServices = false
    implicitWidth: Theme.px(680)
    implicitHeight: Theme.px(620)

    readonly property var groups: [Tr.t("Phone"), Tr.t("Watch"), Tr.t("Music")]

    function groupOf(key) {
        const k = String(key || "");
        if (k === "watch-nowplaying-enabled" || k === "bluetooth-media-remote-enabled") return Tr.t("Music");
        if (k.startsWith("watch-")) return Tr.t("Watch");
        return Tr.t("Phone");
    }

    tools: [
        IconButton {
            icon: "view-refresh"
            tip: Tr.t("Read the switches again")
            size: Theme.px(26)
            on: PhoneTools.busy
            onClicked: PhoneTools.refresh()
        }
    ]

    onVisibleChanged: if (visible) PhoneTools.refresh()

    Flickable {
        anchors.fill: parent
        anchors.margins: Theme.px(12)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: col.implicitHeight

        ColumnLayout {
            id: col
            width: parent.width
            spacing: Theme.px(10)

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Tr.t("These keep working with no window open. Each one runs only while its switch is on.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("small")
                Accessible.role: Accessible.StatusBar
                Accessible.name: text
            }
            BusyNote {
                Layout.fillWidth: true
                visible: PhoneTools.busy
                note: Tr.t("Reading…")
                iconSize: Theme.px(16)
            }
            InfoBanner {
                Layout.fillWidth: true
                visible: PhoneTools.note !== ""
                tone: "info"
                text: PhoneTools.note
                accessibleRole: Accessible.StatusBar
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("%1 of %2 on", PhoneTools.switches.filter(s => s.on).length, PhoneTools.switches.length)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("body")
                Accessible.role: Accessible.StatusBar
                Accessible.name: text
            }

            Repeater {
                model: win.groups
                SettingsSection {
                    required property string modelData
                    Layout.fillWidth: true
                    title: modelData
                    hint: modelData === Tr.t("Phone")
                        ? Tr.t("Calls, messages and files with the paired phone")
                        : modelData === Tr.t("Watch")
                            ? Tr.t("What the paired watch keeps doing")
                            : Tr.t("Music controls from a paired phone or remote")
                    Repeater {
                        model: PhoneTools.switches.filter(s => win.groupOf(s.key) === modelData)
                        SwitchRow {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.label || ""
                            hint: modelData.detail || ""
                            checked: !!modelData.on
                            enabled: !PhoneTools.busy
                            onToggled: on => PhoneTools.backgroundSet(modelData.key, on)
                        }
                    }
                }
            }

            EmptyState {
                visible: !PhoneTools.busy && PhoneTools.switches.length === 0
                Layout.fillWidth: true
                icon: "preferences-system"
                title: Tr.t("No background work here yet")
                subtitle: Tr.t("The phone tools are not installed")
            }
        }
    }
}
