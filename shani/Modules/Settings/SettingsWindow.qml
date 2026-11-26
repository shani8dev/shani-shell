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
import QtQuick.Controls
import qs.Common
import qs.Services
import "SettingsIndex.js" as SettingsIndex
import "../../Common/FormFactor.js" as FF

AppWindow {
    id: win
    appName: "Settings"
    visible: Ui.settingsOpen
    onGone: Ui.settingsOpen = false
    margins: 0
    // never more than the screen it opens on (a phone's is ~412 wide): niri gives a
    // window the size it asks for, and 1040 there ran off the screen
    readonly property var openOn: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    implicitWidth: Math.min(Theme.px(1040), openOn ? openOn.width - 16 : Theme.px(1040))
    implicitHeight: Math.min(Theme.px(800), openOn ? openOn.height - 60 : Theme.px(800))

    Item {
        id: winRoot
        anchors.fill: parent
        focus: true
        // a phone's width or a narrow window: one pane at a time - the categories,
        // or the page chosen with a way back (docs/FORM-FACTORS.md, breakpoints)
        readonly property bool compact: FF.widthClass(width) === "compact"
        property bool showingPage: true
        property string crumbSubpage: ""     // an optional third crumb for a drill-in
        function crumbBack() { winRoot.showingPage = false; }  // one level back; Escape still closes the window
        onCompactChanged: Ui.settingsCompact = compact
        Component.onCompleted: Ui.settingsCompact = compact
        onShowingPageChanged: Ui.settingsShowingPage = showingPage
        Connections { target: Ui; function onSettingsCatChanged() { winRoot.showingPage = true; } }
        Keys.onEscapePressed: Ui.settingsOpen = false

        // ---- the categories -------------------------------------------------------
        Rectangle {
            id: side
            objectName: "region:categories"
            visible: !winRoot.compact || !winRoot.showingPage
            width: winRoot.compact ? parent.width : Theme.px(260)
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            color: Settings.blurWanted ? Theme.alpha(Theme.surface1, 0.55) : Theme.surface1
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(14)
                spacing: Theme.px(10)
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
                    needle: page.query
                    matches: page.settingsMatches
                    icons: page.catIcons
                    onActivated: e => page.openSetting(e)
                }
                EmptyState {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: page.query.trim() !== "" && !page.settingsMatches.length && !page.shownCats.length
                    icon: "edit-find"
                    title: Tr.t("No setting matches")
                    subtitle: Tr.t("Try “proxy”, “fonts” or “lid”")
                }
                ListView {
                    reuseItems: true
                    cacheBuffer: 400
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }
                    // in sections (a heading row before each); a search shows the matches alone
                    model: page.query.trim() === "" ? page.sidebarRows : page.shownCats
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool header: !!modelData.header
                        readonly property bool current: !header && Ui.settingsCat === modelData.id
                        width: ListView.view.width
                        height: header ? Theme.px(30) : Theme.px(40)
                        radius: Theme.radiusSmall
                        color: current ? Theme.accentSoft : (!header && rowArea.containsMouse ? Theme.surface2 : "transparent")
                        // a section's name: read as a heading, not a page to open
                        Text {
                            visible: row.header
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.px(12)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.px(4)
                            text: row.modelData.label.toUpperCase()
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.type("caption")
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.6
                            Accessible.role: Accessible.Heading
                            Accessible.name: row.modelData.label
                        }
                        Behavior on color { ColorAnimation { duration: Theme.anim } }
                        Accessible.role: header ? Accessible.Heading : Accessible.PageTab
                        Accessible.name: modelData.label
                        Accessible.onPressAction: if (!header) Ui.settingsCat = modelData.id
                        RowLayout {
                            visible: !row.header
                            anchors.fill: parent
                            anchors.leftMargin: Theme.px(12)
                            anchors.rightMargin: Theme.px(12)
                            spacing: Theme.px(12)
                            Icon { name: row.modelData.icon || ""; size: Theme.px(18); color: row.current ? Theme.accent : Theme.dim }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.label
                                elide: Text.ElideRight
                                color: row.current ? Theme.text : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.type("body")
                                font.weight: row.current ? Font.DemiBold : Font.Normal
                            }
                            Rectangle {
                                visible: (page.modified[row.modelData.id] || 0) > 0
                                implicitWidth: Theme.px(7)
                                implicitHeight: Theme.px(7)
                                radius: 3.5
                                color: Theme.accent
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                        MouseArea { id: rowArea; anchors.fill: parent; enabled: !row.header; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Ui.settingsCat = row.modelData.id; winRoot.showingPage = true; } }
                        KeyFocus { enabled: !row.header; name: row.modelData.label; onActivated: Ui.settingsCat = row.modelData.id }
                    }
                }
                // ---- changed since sign-in: take one back, or all. Below the categories, so
                // the list above stays where it was and the keyboard reaches it first ----
                // (named as the search names them; five at most, so the list stays short)
                ColumnLayout {
                    id: changed
                    Layout.fillWidth: true
                    // the category list above is clipped mid-row when it scrolls
                    // (a short window shows seven of twenty-three): without a gap
                    // and a line, that half row reads as the rail overprinting a
                    // category - "Accessibility" cut in half, twice in one render
                    Layout.topMargin: Theme.px(8)
                    readonly property var keys: Settings.changedKeys.filter(k => SettingsIndex.labelOf(k) !== "")
                    visible: keys.length > 0 && page.query === ""
                    spacing: Theme.px(6)
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.stroke }
                    // one line until asked: the list took the column the categories need
                    property bool open: false
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(6)
                        Text {
                            Layout.fillWidth: true
                            text: Tr.t("%1 changed this session", changed.keys.length)
                            color: Theme.dim
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.type("small")
                        }
                        Button {
                            text: changed.keys.length > 1 ? Tr.t("Undo all") : Tr.t("Undo")
                            flat: true
                            Accessible.name: changed.keys.length > 1 ? Tr.t("Undo all %1 changes", changed.keys.length) : Tr.t("Undo")
                            onClicked: changed.keys.length > 1 ? Settings.undoAll() : Settings.undo(changed.keys[0])
                        }
                        IconButton {
                            size: Theme.px(26)
                            icon: changed.open ? "go-up" : "go-down"
                            tip: changed.open ? Tr.t("Hide the changes") : Tr.t("Show the changes")
                            onClicked: changed.open = !changed.open
                        }
                    }
                    Repeater {
                        model: changed.open ? changed.keys.slice(0, 5) : []
                        delegate: RowLayout {
                            id: changedRow
                            required property string modelData
                            Layout.fillWidth: true
                            spacing: Theme.px(6)
                            Text {
                                id: changedLabel
                                text: Tr.t(SettingsIndex.labelOf(changedRow.modelData))
                                // Text has no `hovered`; a HoverHandler supplies it
                                HoverHandler { id: changedHover }
                                ToolTip.text: text
                                ToolTip.visible: changedLabel.truncated && changedHover.hovered
                                ToolTip.delay: 400
                                font.family: Theme.font
                                font.pixelSize: Theme.type("small")
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
                }
            }
        }

        // ---- the chosen one ---------------------------------------------------------
        Flickable {
            id: content
            objectName: "region:page"
            visible: !winRoot.compact || winRoot.showingPage
            anchors { top: parent.top; bottom: parent.bottom; left: winRoot.compact ? parent.left : side.right; right: parent.right }
            anchors.margins: winRoot.compact ? Theme.px(14) : Theme.px(28)
            contentHeight: body.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }
            ColumnLayout {
                id: body
                width: Math.min(content.width, 720)
                spacing: Theme.px(16)
                // compact: back to the categories
                Button {
                    visible: winRoot.compact
                    text: "← " + Tr.t("Categories")
                    onClicked: winRoot.showingPage = false
                }
                // breadcrumb: Settings › category [› subpage]. The "Settings"
                // crumb goes back one level to the categories; Escape still
                // closes the whole window (Keys.onEscapePressed above).
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Text {
                        id: crumbSettings
                        text: Tr.t("Settings")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.type("body")
                        Accessible.role: Accessible.Link
                        Accessible.name: text
                        Accessible.onPressAction: winRoot.crumbBack()
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: winRoot.crumbBack() }
                        KeyFocus { name: crumbSettings.text; onActivated: winRoot.crumbBack() }
                    }
                    Text { text: "›"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("body") }
                    Text {
                        text: page.catTitle
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(24) * Theme.fontScale
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text { visible: winRoot.crumbSubpage !== ""; text: "›"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("body") }
                    Text {
                        visible: winRoot.crumbSubpage !== ""
                        text: winRoot.crumbSubpage
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.type("body")
                    }
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
                    const find = (it, name, byLabel) => {
                        if (!it) return null;
                        const accessible = it.Accessible ? String(it.Accessible.name || "").toLowerCase() : "";
                        const hit = byLabel
                            ? (accessible.length > 0 && (accessible.indexOf(name) >= 0 || name.indexOf(accessible) >= 0) && it.visible)
                            : (it.objectName === name && it.visible);
                        if (hit) return it;
                        for (const c of it.children || []) { const f = find(c, name, byLabel); if (f) return f; }
                        return null;
                    };
                    // "section:id" is a named anchor; "label:text" comes from a
                    // search result and finds the control a screen reader names.
                    const name = Ui.settingsSection;
                    const byLabel = name.indexOf("label:") === 0;
                    const it = find(page, byLabel ? name.slice(6).toLowerCase() : name, byLabel);
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
        anchors.bottomMargin: Theme.px(24)
        z: 20
        message: page.toastMsg
        showUndo: page.toastUndo !== undefined
        onUndo: page.undoToast()
    }
}
