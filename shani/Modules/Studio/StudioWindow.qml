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
            Text {
                text: Tr.t("Studio")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(16) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
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
            Text {
                visible: Studio.busy
                text: Tr.t("Chronoa is generating your app… check the Chronoa panel for progress")
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
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
            model: Studio.apps
            Accessible.role: Accessible.List
            Accessible.name: Tr.t("Your apps")
            delegate: Rectangle {
                required property var modelData
                width: appList.width
                height: Theme.px(52)
                radius: Theme.radiusSmall
                // the row says it is waiting for the second click, not only its tooltip
                color: win.confirmDelete === modelData.name ? Theme.alpha(Theme.danger, 0.14)
                     : rowArea.containsMouse ? Theme.hover : "transparent"
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.name + (win.confirmDelete === modelData.name ? ", " + Tr.t("Click again to delete") : "")
                RowLayout {
                    anchors { fill: parent; margins: Theme.px(10) }
                    spacing: Theme.px(10)
                    Icon { name: "application-x-executable"; size: Theme.px(22); color: Theme.dim }
                    ColumnLayout {
                        Layout.fillWidth: true
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
    }
}
