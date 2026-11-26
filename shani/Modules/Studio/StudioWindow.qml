// Studio: the AI app builder — describe what you want and Chronoa generates
// a QML app. Each generated app is saved to ~/Developer/<name>/ with a
// .desktop file in ~/.local/share/applications/ so it appears in the launcher.
// Open the generated code in TextEditor, run it, or delete it.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Studio"
    visible: Ui.studio
    onGone: Ui.studio = false
    implicitWidth: Theme.px(760)
    implicitHeight: Theme.px(580)

    // the description input
    property string description: ""
    // delete confirmation: two taps, the second within 4 s
    property string confirmDelete: ""
    Timer { id: deleteTimer; interval: 4000; onTriggered: win.confirmDelete = "" }

    // the app list is Studio's search + sort view of the apps
    property var shownApps: Studio.search()
    property var selectedApp: null

    onVisibleChanged: if (visible) Studio.refresh()

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Ui.studio = false
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(16)
        spacing: Theme.px(8)

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            // the title is the window's own (AppWindow's header), not repeated here
            Item { Layout.fillWidth: true }
            IconButton {
                size: Theme.px(26)
                icon: "edit-undo"
                tip: Tr.t("Undo last action")
                visible: Studio.actionIndex >= 0
                onClicked: Studio.undoLast()
            }
            IconButton {
                size: Theme.px(26)
                icon: "go-next"
                tip: Tr.t("Redo last action")
                visible: Studio.undone.length > 0
                onClicked: Studio.redoLast()
            }
            Button { text: Tr.t("Refresh"); flat: true; onClicked: Studio.refresh() }
        }

        // ---- description input ----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Tr.t("Describe the app you want. Chronoa will generate the QML code, save it to your Developer folder, and add it to the launcher.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                TextField {
                    id: descField
                    Layout.fillWidth: true
                    placeholder: Tr.t("A pomodoro timer that sits in the bar")
                    label: Tr.t("App description")
                    text: win.description
                    onTextChanged: win.description = text
                    onAccepted: { if (Studio.busy) return; Studio.generate(win.description); win.description = ""; }
                }
                Button {
                    text: Studio.busy ? Tr.t("Working…") : Tr.t("Generate")
                    kind: "primary"
                    enabled: win.description.trim() !== "" && !Studio.busy
                    onClicked: { Studio.generate(win.description); win.description = ""; }
                }
            }
            BusyNote {
                visible: Studio.busy
                note: Tr.t("Chronoa is generating your app… check the Chronoa panel for progress")
            }

            // ---- template pickers: four starting points ----
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text {
                    text: Tr.t("Start from")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    height: Math.max(Theme.px(28), Theme.touchTarget)
                    verticalAlignment: Text.AlignVCenter
                }
                Repeater {
                    model: Studio.templates
                    delegate: Button {
                        text: modelData.name
                        onClicked: Studio.generateFromTemplate(modelData.id)
                    }
                }
            }
        }

        // ---- search and sorting ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholder: Tr.t("Search apps")
                onTextChanged: Studio.searchText = text
            }
            Button {
                text: Tr.t("Name")
                checked: Studio.sortBy === "name"
                onClicked: { Studio.sortApps("name"); win.shownApps = Studio.search(); }
            }
            Button {
                text: Tr.t("Newest")
                checked: Studio.sortBy === "createdAt"
                onClicked: { Studio.sortApps("createdAt"); win.shownApps = Studio.search(); }
            }
        }

        // ---- generated apps list ----
        Text {
            text: Tr.t("Your apps")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
            font.weight: Font.DemiBold
        }
        ListView {
            id: appList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            reuseItems: true
            cacheBuffer: 400
            model: win.shownApps
            onCurrentIndexChanged: win.selectedApp = win.shownApps[currentIndex] ? win.shownApps[currentIndex] : null
            Accessible.role: Accessible.List
            Accessible.name: Tr.t("Your apps")
            delegate: Rectangle {
                required property var modelData
                width: appList.width
                // the actions wrap below the name on a phone instead of shrinking it
                height: Math.max(Theme.px(52), rowFlow.implicitHeight + Theme.px(20))
                radius: Theme.radiusSmall
                // the row says it is waiting for the second click, not only its tooltip
                color: win.confirmDelete === modelData.name ? Theme.alpha(Theme.danger, 0.14)
                     : rowArea.containsMouse ? Theme.hover : "transparent"
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.name + (win.confirmDelete === modelData.name ? ", " + Tr.t("Click again to delete") : "")
                Flow {
                    id: rowFlow
                    anchors { fill: parent; margins: Theme.px(10) }
                    spacing: Theme.px(8)
                    Icon { name: AppIconPath.nameFor(modelData, "application-x-executable"); size: Theme.px(22); color: Theme.dim }
                    ColumnLayout {
                        width: Math.min(Theme.px(260), rowFlow.width - Theme.px(40))
                        spacing: 0
                        Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text {
                            text: win.confirmDelete === modelData.name ? Tr.t("Click again to delete") : modelData.path
                            color: win.confirmDelete === modelData.name ? Theme.danger : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }
                    IconButton {
                        size: Theme.px(26)
                        icon: "document-edit"
                        tip: Tr.t("Edit code")
                        onClicked: Studio.openCode(modelData)
                    }
                    IconButton {
                        size: Theme.px(26)
                        icon: "system-run"
                        tip: Tr.t("Run")
                        onClicked: Studio.runApp(modelData)
                    }
                    IconButton {
                        size: Theme.px(26)
                        icon: "user-trash"
                        tip: win.confirmDelete === modelData.name
                            ? Tr.t("Click again to delete")
                            : Tr.t("Delete %1", modelData.name)
                        onClicked: {
                            if (win.confirmDelete === modelData.name) { Studio.deleteApp(modelData); win.confirmDelete = ""; }
                            else { win.confirmDelete = modelData.name; deleteTimer.restart(); }
                        }
                    }
                    IconButton {
                        size: Theme.px(26)
                        icon: "utilities-terminal"
                        tip: Tr.t("Generate run script")
                        onClicked: Studio.generateScript(modelData)
                    }
                    IconButton {
                        size: Theme.px(26)
                        icon: "folder-publicshare"
                        tip: Tr.t("Export")
                        onClicked: Studio.exportApp(modelData, Studio.devDir + "/" + modelData.name + "-export")
                    }
                    IconButton {
                        size: Theme.px(26)
                        icon: "document-open"
                        tip: Tr.t("Preview code")
                        onClicked: Studio.preview(modelData)
                    }
                    IconButton {
                        size: Theme.px(26)
                        icon: "security-high"
                        tip: Tr.t("Check syntax")
                        onClicked: Studio.lintApp(modelData)
                    }
                    IconButton {
                        size: Theme.px(26)
                        icon: "media-record"
                        tip: Studio.tailing ? Tr.t("Stop tail") : Tr.t("Tail logs")
                        onClicked: Studio.tailing ? Studio.stopTail() : Studio.tailApp(modelData)
                    }
                }
                MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            }
            EmptyState {
                anchors.centerIn: parent
                visible: appList.count === 0 && !Studio.busy
                icon: "applications-development"
                title: Tr.t("No apps yet")
                subtitle: Tr.t("Describe an app above and Chronoa will build it for you")
            }
        }

        // ---- wizard: multi-file projects ----
        Item {
            Layout.fillWidth: true
            height: Studio.wizardActive && Studio.wizardCount > 0 ? Theme.px(30) : 0
            visible: Studio.wizardActive && Studio.wizardCount > 0
            RowLayout {
                anchors.fill: parent
                spacing: Theme.px(8)
                Button { text: Tr.t("Previous"); enabled: Studio.wizardStep > 0; onClicked: Studio.wizardPrev() }
                Text {
                    text: Tr.t("Step %1 of %2", Studio.wizardStep + 1, Studio.wizardCount())
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                }
                Button {
                    text: Studio.wizardStep + 1 < Studio.wizardFiles.length ? Tr.t("Next") : Tr.t("Done")
                    onClicked: {
                        if (Studio.wizardStep + 1 < Studio.wizardFiles.length) Studio.wizardNext();
                        else Studio.wizardFinish();
                    }
                }
            }
        }

        // ---- code preview ----
        Text {
            visible: appList.count > 0 && Studio.previewText !== ""
            text: Studio.previewText
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Text {
            visible: Studio.previewPath !== ""
            text: Tr.t("Code preview — %1", Studio.previewPath)
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
            Layout.fillWidth: true
        }

        // ---- live tail ----
        Text {
            visible: Studio.tailing
            text: Studio.tailText
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        // ---- dashboard widgets ----
        Text {
            text: Tr.t("Dashboard widgets")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
            font.weight: Font.DemiBold
            visible: appList.count > 0
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            visible: appList.count > 0
            Repeater {
                model: Studio.widgetTypes
                delegate: Button {
                    text: modelData
                    onClicked: Studio.addWidget(win.selectedApp, modelData)
                }
            }
        }
        ListView {
            id: widgetsList
            Layout.fillWidth: true
            height: Math.min(Studio.widgets.length, 3) * Theme.px(24)
            visible: Studio.widgets.length > 0
            model: Studio.widgets
            delegate: Text {
                text: modelData.type + " — " + modelData.app
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
                Layout.fillWidth: true
            }
        }

        // ---- footer ----
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Tr.t("Generated apps are saved to %1 · Esc closes", Studio.devDir)
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
            elide: Text.ElideMiddle
        }

        // the app list follows the search and the apps themselves
        Connections {
            target: Studio
            function onAppsChanged() { win.shownApps = Studio.search(); }
            function onSearchTextChanged() { win.shownApps = Studio.search(); }
        }
    }
}
