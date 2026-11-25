// Settings > Updates: what release this slot runs, what the channel offers, and
// whether anything is waiting - the system update, a restart to finish one, or
// firmware. Services/Updates.qml reads `shani-deploy --status --check --json`
// (the same contract shani-deploy exposes); this page shows and installs it. Installing is
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

    // A panel, not an AppWindow: Ctrl+R checks for updates, while Ctrl+F
    // (search) and Ctrl+W (close) belong to the hosting Settings window.
    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
            Updates.check(); event.accepted = true;
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Updates")
        hint: Tr.t("ShaniOS keeps two systems, blue and green. An update writes the other one and the next boot starts from it, so a bad update leaves the one you know.")

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
    }

    // ---- the channel -------------------------------------------------------
    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Channel")

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
    }

    // ---- firmware ----------------------------------------------------------
    property bool confirmFirmware: false

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Firmware")
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
    // the cost named before it is written: PCR 0 changes, so a TPM2-sealed disk
    // will ask for its passphrase once after a firmware update
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.confirmFirmware && Updates.firmware.length > 0 && !Updates.firmwareInstalling
        spacing: Theme.px(6)
        Text {
            Layout.fillWidth: true
            text: Tr.t("Keep the computer plugged in. If your disk unlocks by itself at start-up, it will ask for its passphrase once after this — have it ready, then set up automatic unlock again on the Encryption page.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Item { Layout.fillWidth: true }
            Button { flat: true; text: Tr.t("Cancel"); onClicked: page.confirmFirmware = false }
            Button { kind: "primary"; text: Tr.t("Install firmware"); onClicked: { page.confirmFirmware = false; Updates.installFirmware(); } }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: Updates.firmwareInstalling || Updates.firmwareProgress.length > 0 || Updates.firmwareNote !== "" || Updates.firmwareError !== ""
        spacing: Theme.px(4)
        Text { Layout.fillWidth: true; visible: Updates.firmwareNote !== ""; text: Updates.firmwareNote; color: Theme.accent; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        Text { Layout.fillWidth: true; visible: Updates.firmwareError !== ""; text: Updates.firmwareError; color: Theme.danger; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(120, Updates.firmwareProgress.length * 16 + 8)
            visible: Updates.firmwareProgress.length > 0
            clip: true
            model: Updates.firmwareProgress
            delegate: Text { required property string modelData; width: ListView.view.width; text: modelData; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale; elide: Text.ElideLeft }
        }
    }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Button {
            text: Tr.t("Check now")
            enabled: !Updates.installing && !Updates.firmwareInstalling
            onClicked: Updates.check()
        }
        Button {
            visible: Updates.firmware.length > 0
            text: Updates.firmwareInstalling ? Tr.t("Installing firmware…") : Tr.t("Install firmware")
            enabled: !Updates.firmwareInstalling && !Updates.installing
            onClicked: page.confirmFirmware = true
        }
        Item { Layout.fillWidth: true }
        Button {
            text: Tr.t("Review with Chronoa")
            flat: true
            enabled: Updates.available || Updates.firmware.length > 0
            onClicked: Updates.reviewWithChronoa()
        }
        Button {
            text: Updates.installing ? Tr.t("Installing…") : Tr.t("Install now")
            kind: "primary"
            enabled: Updates.available && !Updates.installing && !Updates.firmwareInstalling
            onClicked: Updates.install()
        }
    }

    // ---- the system install itself, as it happens --------------------------
    ColumnLayout {
        Layout.fillWidth: true
        visible: Updates.installing || Updates.progress.length > 0 || Updates.note !== "" || Updates.installError !== ""
        spacing: Theme.px(4)
        Text { Layout.fillWidth: true; visible: Updates.note !== ""; text: Updates.note; color: Theme.accent; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        Text { Layout.fillWidth: true; visible: Updates.installError !== ""; text: Updates.installError; color: Theme.danger; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(160, Updates.progress.length * 16 + 8)
            visible: Updates.progress.length > 0
            clip: true
            model: Updates.progress
            delegate: Text { required property string modelData; width: ListView.view.width; text: modelData; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale; elide: Text.ElideLeft }
        }
    }

    Text {
        Layout.fillWidth: true
        text: Tr.t("Installing asks for authorisation, writes the other slot and leaves this one running until you restart.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
}
