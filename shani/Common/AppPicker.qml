// An app picker: a searchable list of installed applications.
// Replaces typing a desktop ID. Value is the app ID (e.g. "foot", "org.gnome.Calendar").
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: root
    property string value: ""
    property string label: ""
    property string placeholder: Tr.t("Pick an app — or search below")
    signal picked(string appId)

    Layout.fillWidth: true
    spacing: 6

    property string searchText: ""

    Text {
        visible: label !== ""
        text: label
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSmall * Theme.fontScale
    }

    // Current value display
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: 8
            color: Theme.surface1
            border.color: Theme.stroke
            border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8
                Icon {
                    visible: root.value !== ""
                    name: root.selectedApp ? (root.selectedApp.icon || "application-x-executable") : "application-x-executable"
                    size: 18
                    color: Theme.text
                }
                Text {
                    Layout.fillWidth: true
                    verticalAlignment: Text.AlignVCenter
                    text: root.selectedApp ? root.selectedApp.name : (root.value || root.placeholder)
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                    elide: Text.ElideRight
                }
            }
        }
        Button {
            visible: root.value !== ""
            text: Tr.t("Clear")
            onClicked: {
                root.value = "";
                root.picked("");
            }
        }
    }

    readonly property var selectedApp: DesktopEntries.applications.values.find(a => a.id === root.value) || null

    // Search field (only shown when picking)
    TextField {
        id: appSearch
        Layout.fillWidth: true
        placeholder: Tr.t("Search apps…")
        text: root.searchText
        onTextChanged: root.searchText = text
    }

    // App list
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Repeater {
            model: {
                const q = root.searchText.trim().toLowerCase();
                let apps = DesktopEntries.applications.values
                    .filter(a => !a.noDisplay);
                if (q.length >= 2) {
                    apps = apps.filter(a => 
                        a.name.toLowerCase().indexOf(q) >= 0 || 
                        a.id.toLowerCase().indexOf(q) >= 0 ||
                        (a.comment && a.comment.toLowerCase().indexOf(q) >= 0)
                    );
                }
                // Sort: selected first, then by name
                return apps.sort((a, b) => {
                    if (a.id === root.value) return -1;
                    if (b.id === root.value) return 1;
                    return a.name.localeCompare(b.name);
                }).slice(0, 12);
            }
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: modelData.icon || "application-x-executable"
                title: modelData.name
                subtitle: modelData.id
                selected: modelData.id === root.value
                onClicked: {
                    root.value = modelData.id;
                    root.picked(modelData.id);
                    root.searchText = "";
                    appSearch.text = "";
                }
            }
        }
    }

    // Custom: type any app ID (for apps not in the list)
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        TextField {
            id: customApp
            Layout.fillWidth: true
            placeholder: Tr.t("Custom app ID — dashed border (e.g. foot, org.gnome.Calendar)")
            border.color: Theme.accentLine
            onAccepted: {
                const id = customApp.text.trim();
                if (id !== "") {
                    root.value = id;
                    root.picked(id);
                    customApp.text = "";
                }
            }
        }
        Button {
            text: Tr.t("Use")
            onClicked: customApp.accepted()
        }
    }

    Text {
        visible: DesktopEntries.applications.values.length === 0
        text: Tr.t("No apps found.")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
