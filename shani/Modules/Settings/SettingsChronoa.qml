// Settings > Chronoa: the local engine's on/off switch, the shell's own
// read-only pages for the assistant's information, and the Island's part of
// it. Nothing here starts a window; the engine is one user service and the
// pages are drawn from its read-only inventory.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    readonly property var d: Settings.data
    property var inv: ({ ready: false, error: "", count: 0, sample: [] })

    // One merged state object for a live check. Other system pages publish
    // their own keys into Ui.systemState; this is Chronoa's own slot.
    function publish() {
        var o = Object.assign({}, Ui.chronoaState || {});
        Object.assign(o, {
            page: Ui.chronoaSettingsPage,
            ready: page.inv.ready === true,
            error: page.inv.error || ChronoaEngine.error || "",
            count: page.inv.count || 0,
            sample: page.inv.sample || [],
            running: ChronoaEngine.service === "active",
            service: ChronoaEngine.service,
            engineBusy: ChronoaEngine.busy,
            engineCall: ChronoaEngine.lastCall
        });
        Ui.chronoaState = o;
    }

    Component.onCompleted: page.publish()

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Chronoa")
        hint: ChronoaEngine.service === "active" ? Tr.t("The local engine is running.") : Tr.t("The local engine is not running.")

        SwitchRow {
            Layout.fillWidth: true
            text: Tr.t("Enable Chronoa")
            hint: Tr.t("The local engine starts when on. When off, the Island still shows what is going on but Chronoa does not answer.")
            checked: ChronoaEngine.service === "active"
            onToggled: on => {
                Settings.data.chronoaEnabled = on;
                ChronoaEngine.setEngine(on);
            }
        }

        BusyNote {
            visible: ChronoaEngine.busy
            Layout.fillWidth: true
            note: Tr.t("Changing the Chronoa service…")
        }

        InfoBanner {
            visible: ChronoaEngine.error !== ""
            Layout.fillWidth: true
            tone: "error"
            text: ChronoaEngine.error
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Chronoa's own pages")
        hint: Tr.t("What is saved on this machine. Click a section to read it; nothing here changes it.")

        Picks {
            Layout.fillWidth: true
            label: Tr.t("Sections")
            options: [
                { label: Tr.t("Status"), value: "status" },
                { label: Tr.t("Models"), value: "models" },
                { label: Tr.t("Skills"), value: "skills" },
                { label: Tr.t("Capabilities"), value: "capabilities" },
                { label: Tr.t("Routines"), value: "routines" },
                { label: Tr.t("Triggers"), value: "triggers" },
                { label: Tr.t("Memory"), value: "memory" },
                { label: Tr.t("Privacy"), value: "privacy" },
                { label: Tr.t("Senses"), value: "senses" },
                { label: Tr.t("Conversations"), value: "conversations" }
            ]
            current: Ui.chronoaSettingsPage
            onPicked: value => { Ui.chronoaSettingsPage = value; }
        }
    }

    ChronoaInventoryPage {
        id: inventory
        Layout.fillWidth: true
        section: Ui.chronoaSettingsPage
    }

    Connections {
        target: inventory
        function onReport(info) { page.inv = info; page.publish(); }
    }

    Connections {
        target: ChronoaEngine
        function onBusyChanged() { page.publish(); }
        function onServiceChanged() { page.publish(); }
        function onErrorChanged() { page.publish(); }
        function onLastCallChanged() { page.publish(); }
    }

    Connections {
        target: Chronoa
        function onStateChanged() { page.publish(); }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("The Island")

        SwitchRow {
            Layout.fillWidth: true
            text: Tr.t("Show what is going on")
            hint: Tr.t("a timer, music, a recording, a suggestion after copying — in the Island while Chronoa is idle")
            checked: page.d.islandActivities
            onToggled: on => page.d.islandActivities = on
        }
        Text {
            Layout.fillWidth: true
            text: Tr.t("Super+A opens Chronoa; Super+S reads part of the screen with Lens; Ctrl+Enter in the launcher asks it anything.")
            color: Theme.faint
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
    }
}
