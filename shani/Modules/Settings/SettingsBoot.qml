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

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Boot & Recovery") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("This computer keeps two systems, blue and green. An update writes the other one and the next boot starts from it, so a bad update leaves the one you know.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
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
