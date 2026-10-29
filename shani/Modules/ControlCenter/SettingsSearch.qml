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

    SectionTitle { Layout.fillWidth: true; text: "Search" }
    SwitchRow { Layout.fillWidth: true; text: "File names"; checked: page.d.searchFiles; onToggled: on => page.d.searchFiles = on }
    SwitchRow { Layout.fillWidth: true; text: "Inside documents"; hint: "words in Documents, Desktop and Downloads"; checked: page.d.searchInside; onToggled: on => page.d.searchInside = on }
    SwitchRow { Layout.fillWidth: true; text: "Results from apps"; hint: "what Files, Characters, Calculator … find themselves"; checked: page.d.searchProviders; onToggled: on => page.d.searchProviders = on }
    SwitchRow { Layout.fillWidth: true; text: "Sums and conversions"; hint: "12*12, 5 km in miles, 100 USD in INR"; checked: page.d.searchCalc; onToggled: on => page.d.searchCalc = on }

    Text { visible: page.d.searchFiles; text: "Look for files in"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
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
    TextField {
        Layout.fillWidth: true
        visible: page.d.searchFiles
        placeholder: "Add a folder — ~/Projects, /mnt/data …"
        onAccepted: {
            const f = text.trim().replace(/\/$/, "");
            if (f && Array.from(page.d.searchFolders).indexOf(f) < 0)
                page.d.searchFolders = Array.from(page.d.searchFolders).concat([f]);
            text = "";
        }
    }

    Text { text: "Search the web with"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
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
}
