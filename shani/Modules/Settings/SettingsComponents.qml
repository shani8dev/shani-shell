import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Components") }

    Text { Layout.fillWidth: true; text: Tr.t("UI component preview"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Button { text: Tr.t("Primary") }
        Button { text: Tr.t("Secondary") }
        IconButton { icon: "view-refresh" }
    }

    ListRow { Layout.fillWidth: true; icon: "folder"; title: Tr.t("List row"); subtitle: Tr.t("Subtitle") }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Switch row"); checked: true }
    Choice { text: Tr.t("Choice") }
}
