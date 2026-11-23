// Settings > Security: what protects this machine, read as it is. Nothing here
// changes a policy; where a change needs a password or a reboot, it says so.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    onActiveChanged: if (active) SecurityInfo.refresh()
    Component.onCompleted: if (active) SecurityInfo.refresh()

    readonly property var r: SecurityInfo.report || ({})
    readonly property var aa: r.apparmor || ({})
    readonly property var pw: r.pwquality || ({})
    readonly property var au: r.audit || ({})

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Security") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("What the kernel, sign-in and audit subsystems report. This page reads; it does not change policies.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Kernel security (LSM)") }
    Text {
        Layout.fillWidth: true
        text: (r.lsm && r.lsm.length) ? r.lsm.join(", ") : Tr.t("Could not read /sys/kernel/security/lsm.")
        color: Theme.text
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("AppArmor") }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.px(2)
        ListRow { Layout.fillWidth: true; interactive: false; icon: "security-high"; title: Tr.t("Service"); subtitle: aa.active || Tr.t("unknown") }
        ListRow {
            Layout.fillWidth: true; interactive: false; icon: "security-high"
            title: Tr.t("Profiles")
            subtitle: aa.profiles ? Tr.t("%1 loaded, %2 enforcing", Object.keys(aa.profiles).length, aa.enforcing || 0)
                                 : (aa.note || Tr.t("No profile report available"))
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Password policy") }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.px(2)
        ListRow { Layout.fillWidth: true; interactive: false; icon: "dialog-password"; title: Tr.t("pwquality config"); subtitle: pw.present ? pw.file : Tr.t("No /etc/security/pwquality.conf") }
        ListRow { Layout.fillWidth: true; interactive: false; icon: "dialog-password"; title: Tr.t("PAM wired"); subtitle: pw.pam_wired ? Tr.t("pam_pwquality appears in PAM") : Tr.t("pam_pwquality not found in PAM — policy may not be enforced") }
    }
    Text {
        Layout.fillWidth: true
        visible: pw.settings && Object.keys(pw.settings).length > 0
        text: Object.keys(pw.settings || {}).map(k => k + " = " + pw.settings[k]).join("\n")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.mono
        font.pixelSize: Theme.px(10) * Theme.fontScale
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Audit") }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.px(2)
        ListRow { Layout.fillWidth: true; interactive: false; icon: "document-open-recent"; title: Tr.t("auditd"); subtitle: au.active || Tr.t("unknown") }
        ListRow { Layout.fillWidth: true; interactive: false; icon: "document-open-recent"; title: Tr.t("enabled"); subtitle: au.enabled || Tr.t("unknown") }
    }
}
