// Settings, as a window of its own: the categories down the left (with a
// search), the chosen one on the right - room for Displays' arrangement,
// Sound's equaliser and Automations, which the control centre's narrow column
// never had. The pages themselves are SettingsPage's, made when opened.
// Ui.openSettings(cat) opens it; Escape or the window's close closes it.
// A window like the shell's other apps (Common/AppWindow), with their header.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "SettingsIndex.js" as SettingsIndex

AppWindow {
    id: win
    appName: "Settings"
    visible: Ui.settingsOpen
    onGone: Ui.settingsOpen = false
    margins: 0
    implicitWidth: 1040
    implicitHeight: 800

    Item {
        id: winRoot
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.settingsOpen = false

        // ---- the categories -------------------------------------------------------
        Rectangle {
            id: side
            objectName: "region:categories"
            width: 260
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            color: Settings.blurWanted ? Theme.alpha(Theme.surface1, 0.55) : Theme.surface1
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                TextField {
                    id: search
                    Layout.fillWidth: true
                    placeholder: Tr.t("Search settings")
                    onAccepted: {
                        if (page.settingsMatches.length) { page.openSetting(page.settingsMatches[0]); return; }
                        if (list.count) { Ui.settingsCat = page.shownCats[0].id; search.text = ""; page.settingsMatches = []; page.query = ""; }
                    }
                    // typing starts a search, as in GNOME's and Windows' Settings
                    Component.onCompleted: search.input.forceActiveFocus()
                    Connections { target: search.input; function onTextChanged() { page.query = search.text; page.settingsMatches = search.text.trim() === "" ? [] : SettingsIndex.matches(search.text); } }
                }
                SettingsMatchList {
                    Layout.fillWidth: true
                    visible: page.settingsMatches.length > 0
                    matches: page.settingsMatches
                    icons: page.catIcons
                    onActivated: e => page.openSetting(e)
                }
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: page.shownCats
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool current: Ui.settingsCat === modelData.id
                        width: ListView.view.width
                        height: 40
                        radius: Theme.radiusSmall
                        color: current ? Theme.accentSoft : (rowArea.containsMouse ? Theme.surface2 : "transparent")
                        Behavior on color { ColorAnimation { duration: Theme.anim } }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData.label
                        Accessible.onPressAction: Ui.settingsCat = modelData.id
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12
                            Icon { name: row.modelData.icon; size: 18; color: row.current ? Theme.accent : Theme.dim }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.label
                                elide: Text.ElideRight
                                color: row.current ? Theme.text : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 13 * Theme.fontScale
                                font.weight: row.current ? Font.DemiBold : Font.Normal
                            }
                            Rectangle {
                                visible: (page.modified[row.modelData.id] || 0) > 0
                                implicitWidth: 7
                                implicitHeight: 7
                                radius: 3.5
                                color: Theme.accent
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                        MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Ui.settingsCat = row.modelData.id }
                        KeyFocus { name: row.modelData.label; onActivated: Ui.settingsCat = row.modelData.id }
                    }
                }
                // ---- changed since sign-in: take one back, or all. Below the categories, so
                // the list above stays where it was and the keyboard reaches it first ----
                // (named as the search names them; five at most, so the list stays short)
                ColumnLayout {
                    id: changed
                    Layout.fillWidth: true
                    readonly property var keys: Settings.changedKeys.filter(k => SettingsIndex.labelOf(k) !== "")
                    visible: keys.length > 0 && page.query === ""
                    spacing: 6
                    SectionTitle {
                        Layout.fillWidth: true
                        text: Tr.t("Changed this session")
                    }
                    Repeater {
                        model: changed.keys.slice(0, 5)
                        delegate: RowLayout {
                            id: changedRow
                            required property string modelData
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: Tr.t(SettingsIndex.labelOf(changedRow.modelData))
                                font.family: Theme.font
                                font.pixelSize: 11 * Theme.fontScale
                                color: Theme.dim
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Button {
                                text: Tr.t("Undo")
                                flat: true
                                Accessible.name: Tr.t("Undo") + ": " + SettingsIndex.labelOf(changedRow.modelData)
                                onClicked: Settings.undo(changedRow.modelData)
                            }
                        }
                    }
                    Button {
                        Layout.fillWidth: true
                        visible: changed.keys.length > 1
                        text: Tr.t("Undo all") + " (" + changed.keys.length + ")"
                        kind: "outline"
                        onClicked: Settings.undoAll()
                    }
                }
            }
        }

        // ---- the chosen one ---------------------------------------------------------
        Flickable {
            id: content
            objectName: "region:page"
            anchors { top: parent.top; bottom: parent.bottom; left: side.right; right: parent.right }
            anchors.margins: 28
            contentHeight: body.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: body
                width: Math.min(content.width, 720)
                spacing: 16
                Text {
                    text: page.catTitle
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 24 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                SettingsPage {
                    id: page
                    Layout.fillWidth: true
                    inWindow: true
                }
            }
            // a new category starts at its top
            Connections { target: Ui; function onSettingsCatChanged() { content.contentY = 0; } function onSettingsSectionChanged() { if (Ui.settingsSection) toSection.restart(); } }
            // ...or at the part it was opened for (Ui.openSettings(cat, "section:…")),
            // once the category's page has laid out
            Timer {
                id: toSection
                interval: 300
                running: Ui.settingsSection !== ""
                onTriggered: {
                    const find = (it, name) => {
                        if (!it) return null;
                        if (it.objectName === name && it.visible) return it;
                        for (const c of it.children || []) { const f = find(c, name); if (f) return f; }
                        return null;
                    };
                    const it = find(page, Ui.settingsSection);
                    if (it)
                        content.contentY = Math.max(0, Math.min(content.contentHeight - content.height, it.mapToItem(content.contentItem, 0, 0).y - 12));
                    Ui.settingsSection = "";
                }
            }
        }
    }
    // a setting changed: a toast with Undo, over the bottom of the window
    Toast {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 24
        z: 20
        message: page.toastMsg
        showUndo: page.toastUndo !== undefined
        visible: page.toastMsg !== ""
        onUndo: page.undoToast()
    }
}
