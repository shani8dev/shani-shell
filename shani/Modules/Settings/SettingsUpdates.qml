// Settings > Updates: what release this slot runs, what the channel offers, and
// whether anything is waiting - the system update, a restart to finish one, or
// firmware. Services/Updates.qml reads `shani-deploy --status --check --json`
// (the same contract Cassini reads); this page only shows it. Installing is
// shani-deploy's, with authorisation, so the button hands over rather than
// doing it here.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false

    onActiveChanged: if (active) Updates.check()
    Component.onCompleted: if (active) Updates.check()

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Updates") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("ShaniOS keeps two systems, blue and green. An update writes the other one and the next boot starts from it, so a bad update leaves the one you know.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }

    // ---- what is running, and what is offered -----------------------------
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.px(2)
        ListRow {
            Layout.fillWidth: true
            icon: "computer"
            title: Tr.t("This system")
            subtitle: [Updates.version, Updates.slot ? Tr.t("slot %1", Updates.slot) : ""].filter(x => x).join("  ·  ")
        }
        ListRow {
            Layout.fillWidth: true
            icon: "software-update-available"
            title: Updates.candidate || Tr.t("Unknown")
            subtitle: Updates.channel === "latest" ? Tr.t("latest channel") : Tr.t("stable channel")
        }
        ListRow {
            Layout.fillWidth: true
            icon: Updates.rebootNeeded ? "system-reboot" : (Updates.available ? "software-update-available" : "dialog-ok")
            title: Updates.summary || Tr.t("Checking…")
            subtitle: Updates.rebootNeeded ? Tr.t("A restart finishes it") : ""
        }
    }

    // ---- the channel -------------------------------------------------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Channel") }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Repeater {
            model: ["stable", "latest"]
            Choice {
                required property string modelData
                text: modelData === "latest" ? Tr.t("Latest") : Tr.t("Stable")
                selected: Updates.channel === modelData
                onClicked: Updates.setChannel(modelData)
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: Tr.t("Stable is the tested release; latest follows the newest build. Both keep the other slot untouched.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }

    // ---- firmware ----------------------------------------------------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Firmware") }
    Text {
        Layout.fillWidth: true
        visible: Updates.firmware.length === 0
        text: Tr.t("No firmware updates offered.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.px(2)
        Repeater {
            model: Updates.firmware
            ListRow {
                required property string modelData
                Layout.fillWidth: true
                icon: "firmware"
                title: modelData
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Button {
            text: Tr.t("Check now")
            onClicked: Updates.check()
        }
        Item { Layout.fillWidth: true }
        Button {
            text: Tr.t("Review with Chronoa")
            flat: true
            enabled: Updates.available || Updates.firmware.length > 0
            onClicked: Updates.reviewWithChronoa()
        }
        Button {
            text: Tr.t("Install…")
            kind: "primary"
            enabled: Updates.available
            onClicked: Updates.open()
        }
    }
    Text {
        Layout.fillWidth: true
        text: Tr.t("Installing asks for authorisation and keeps the other slot until the new one has booted well.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
}
