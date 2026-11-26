// Settings > Boot & Recovery: which slot this machine is running from, which is
// current, and what a boot left behind - the A/B slots, in plain words.
// bridge/bootinfo.py reads `shani-deploy --status --json`, which needs neither
// root nor the deploy lock. A rollback is shani-deploy's, with authorisation;
// this page only reads and says so.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false

    onActiveChanged: if (active) BootInfo.refresh()
    Component.onCompleted: if (active) BootInfo.refresh()

    // Codes and counts come from the bridge; the words are ours.
    function secureBootState() {
        const sb = BootInfo.secureboot || {};
        if (!("secure_boot" in sb))
            return Tr.t("Not read");
        if (sb.secure_boot === "on") return Tr.t("On");
        if (sb.secure_boot === "off") return Tr.t("Off");
        if (sb.secure_boot === "setup") return Tr.t("Setup mode");
        if (sb.secure_boot === "legacy") return Tr.t("Legacy");
        return Tr.t("Unknown");
    }

    function yesNo(v) {
        if (v === true || v === "yes" || v === "present" || v === "enabled") return Tr.t("Yes");
        if (v === false || v === "no" || v === "absent" || v === "disabled") return Tr.t("No");
        return Tr.t("Not read");
    }

    function keyCount(v) {
        return (typeof v === "number" && isFinite(v)) ? String(v) : Tr.t("Not read");
    }

    function checkIcon(severity) {
        if (severity === "ok") return "dialog-ok";
        if (severity === "bad") return "dialog-warning";
        return "dialog-information";
    }

    function secureBootMessage() {
        if (BootInfo.secureboot.error === "sbctl-no-answer")
            return Tr.t("The computer did not answer when asked about secure boot.");
        return BootInfo.secureboot.error || "";
    }

    function checkMessage() {
        switch (BootInfo.verifyNote) {
        case "cancelled":
            return Tr.t("The check was not allowed. Nothing was changed.");
        case "no-answer":
            return Tr.t("The check did not give an answer. Try again.");
        case "no-pkexec":
            return Tr.t("The tool that asks for administrator rights is not installed.");
        case "failed":
            return Tr.t("The check could not finish. Try again.");
        }
        return BootInfo.verifyNote;
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Boot & Recovery")
        hint: Tr.t("This computer keeps two systems, blue and green. An update writes the other one and the next boot starts from it, so a bad update leaves the one you know.")

        Text {
            Layout.fillWidth: true
            visible: !BootInfo.available && BootInfo.note !== ""
            text: BootInfo.note
            color: Theme.danger
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.px(2)
            Repeater {
                model: BootInfo.rows
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: modelData.status === "fail" ? "dialog-warning"
                        : modelData.status === "ok" ? "dialog-ok"
                        : modelData.status === "warn" ? "dialog-information" : "dialog-information"
                    title: modelData.label
                    subtitle: modelData.detail || ""
                    extra: modelData.status === "fail" ? Tr.t("Needs attention") : (modelData.status === "warn" ? Tr.t("Pending") : "")
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: BootInfo.available
            text: Tr.t("Rolling back is shani-deploy's job and asks for authorisation - the shell only reports what the last boot left behind.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Secure boot")
        hint: Tr.t("How this computer checks the software it starts. Read only.")

        InfoBanner {
            Layout.fillWidth: true
            visible: page.secureBootMessage() !== ""
            tone: "warn"
            text: page.secureBootMessage()
            accessibleRole: Accessible.AlertMessage
        }

        ListRow {
            Layout.fillWidth: true
            interactive: false
            icon: "preferences-system"
            title: Tr.t("State")
            trailing: page.secureBootState()
        }
        ListRow {
            Layout.fillWidth: true
            interactive: false
            icon: "preferences-system"
            title: Tr.t("Keys are enrolled")
            trailing: page.yesNo(BootInfo.secureboot.enrolled)
        }
        ListRow {
            Layout.fillWidth: true
            interactive: false
            icon: "preferences-system"
            title: Tr.t("Number of enrolled keys")
            trailing: page.keyCount(BootInfo.secureboot.enrolled_keys)
        }
        ListRow {
            Layout.fillWidth: true
            interactive: false
            icon: "preferences-system"
            title: Tr.t("Pre-installed keys")
            subtitle: Tr.t("The keys this computer came with")
            trailing: page.yesNo(BootInfo.secureboot.microsoft_keys)
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Check what is installed")
        hint: Tr.t("This compares the files this system started with to the files on the disk now. It needs administrator rights, so the system asks you to allow it.")

        Button {
            text: Tr.t("Check the installed files")
            Accessible.name: Tr.t("Check the installed files")
            kind: "outline"
            enabled: !BootInfo.verifyBusy
            onClicked: BootInfo.verify()
        }

        BusyNote {
            Layout.fillWidth: true
            visible: BootInfo.verifyBusy
            note: Tr.t("Checking the installed files…")
            iconSize: Theme.px(16)
        }

        InfoBanner {
            Layout.fillWidth: true
            visible: BootInfo.verifyNote !== ""
            tone: "error"
            text: page.checkMessage()
            accessibleRole: Accessible.AlertMessage
        }

        EmptyState {
            visible: BootInfo.verifyAvailable && !BootInfo.verifyBusy && BootInfo.verifyNote === ""
                     && BootInfo.verifyChecks.length === 0 && BootInfo.verifyAdvice.length === 0
                     && BootInfo.verifyUnread.length === 0
            icon: "preferences-system"
            title: Tr.t("Nothing to report")
            subtitle: Tr.t("The check finished and found nothing to list.")
        }

        Repeater {
            model: BootInfo.verifyChecks
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: page.checkIcon(modelData.severity)
                title: modelData.text || ""
            }
        }

        Text {
            Layout.fillWidth: true
            visible: BootInfo.verifyAdvice.length > 0
            text: Tr.t("What to do next")
            color: Theme.text
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
            font.weight: Font.DemiBold
        }
        Repeater {
            model: BootInfo.verifyAdvice
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: "dialog-information"
                title: String(modelData)
            }
        }

        Text {
            Layout.fillWidth: true
            visible: BootInfo.verifyUnread.length > 0
            text: Tr.t("Could not be read")
            color: Theme.text
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
            font.weight: Font.DemiBold
        }
        Repeater {
            model: BootInfo.verifyUnread
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: "dialog-information"
                title: String(modelData)
            }
        }
    }
}
