// Settings > Search: what the launcher looks at — file names (in which
// folders), inside documents, apps' own results (GNOME search providers),
// sums and conversions — and the web search the launcher and Lens hand off to.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    readonly property var d: Settings.data

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Search") }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("File names"); checked: page.d.searchFiles; onToggled: on => page.d.searchFiles = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Inside documents"); hint: Tr.t("words in Documents, Desktop and Downloads"); checked: page.d.searchInside; onToggled: on => page.d.searchInside = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Results from apps"); hint: Tr.t("what Files, Characters, Calculator … find themselves"); checked: page.d.searchProviders; onToggled: on => page.d.searchProviders = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Sums and conversions"); hint: Tr.t("12*12, 5 km in miles, 100 USD in INR"); checked: page.d.searchCalc; onToggled: on => page.d.searchCalc = on }

    Text { visible: page.d.searchFiles; text: Tr.t("Look for files in"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
    EmptyState {
        Layout.fillWidth: true
        visible: page.d.searchFiles && page.d.searchFolders.length === 0
        icon: "folder-open"
        title: Tr.t("No folders to search")
        subtitle: Tr.t("Add one below, or turn off “File names”.")
    }
    Repeater {
        model: page.d.searchFiles ? page.d.searchFolders : []
        ListRow {
            id: folderRow
            required property string modelData
            Layout.fillWidth: true
            icon: "folder"
            title: modelData
            IconButton {
                visible: page.d.searchFolders.length > 1
                icon: "edit-delete"
                size: 24
                Accessible.name: "Stop searching " + folderRow.modelData
                onClicked: page.d.searchFolders = Array.from(page.d.searchFolders).filter(x => x !== folderRow.modelData)
            }
        }
    }
    FolderPicker {
        visible: page.d.searchFiles
        label: Tr.t("Add a folder to search")
        onPicked: p => {
            if (p && Array.from(page.d.searchFolders).indexOf(p) < 0)
                page.d.searchFolders = Array.from(page.d.searchFolders).concat([p]);
        }
    }

    Text { text: Tr.t("Search the web with"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: Object.keys(Ui.webSearches)
            Choice {
                required property string modelData
                text: Ui.webSearches[modelData][0]
                selected: page.d.webSearch === modelData
                onClicked: page.d.webSearch = modelData
            }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Launcher") }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Ignore the pointer"); hint: Tr.t("the launcher takes only the keyboard — no hover highlight"); checked: page.d.launcherIgnoreMouse; onToggled: on => page.d.launcherIgnoreMouse = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Hide the navigation hints"); hint: Tr.t("the arrows and Enter/Tab hints along the bottom"); checked: page.d.launcherHideNavLabels; onToggled: on => page.d.launcherHideNavLabels = on }
}
