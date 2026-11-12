// The Files surface: the shell's file manager. The folder on screen, the
// places on the left, a search box, and the files in the middle as a grid of
// tiles or as a list of rows. Click to choose, Ctrl-click for more, Shift-click
// for a range, Enter or a double click to open (a folder is walked into, a
// file is opened with the app it belongs to), F2 to rename, Delete to move to
// the trash, Backspace to go up, Escape to close.
//
// Split view: Ctrl+Alt+N opens a second pane; files can be
// copied or moved between panes with buttons in the toolbar.
//
// The listing comes from Services/Files.qml and bridge/files.py: the folder is
// watched, so a file made or removed elsewhere shows up here too. Nothing is
// deleted by the file manager - the trash is the desktop trash, where it can
// be put back.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/FilePaths.js" as FilePaths

AppWindow {
    id: win
    appName: "Files"
    visible: Ui.files
    onGone: Files.hide()
    margins: 0
    implicitWidth: 1100
    implicitHeight: 760

    // the keys the surface answers, wherever the focus is not on a control
    Item {
        id: keys
        anchors.fill: parent
        focus: win.visible
        // Escape goes back a folder first, and out of the surface at the top
        Keys.onEscapePressed: {
            if (renameBox.visible || newFolderBox.visible) {
                renameBox.visible = false;
                newFolderBox.visible = false;
                return;
            }
            if (Files.splitActive) {
                Files.toggleSplit();
                return;
            }
            if (Files.canUp)
                Files.up();
            else
                Files.hide();
        }
        Keys.onPressed: event => {
            const control = (event.modifiers & Qt.ControlModifier) !== 0;
            const alt = (event.modifiers & Qt.AltModifier) !== 0;
            if (control && alt && event.key === Qt.Key_N) {
                Files.toggleSplit();
                event.accepted = true;
                return;
            }
            if (control && event.key === Qt.Key_L) {
                pathBox.visible = true;
                pathBox.text = Files.path;
                pathBox.forceActiveFocus();
                pathBox.selectAll();
                event.accepted = true;
                return;
            }
            if (control && event.key === Qt.Key_A) {
                Files.selectAll();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_F5) {
                dir.reload();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Delete && Files.selected.length > 0) {
                Files.trashEntries([]);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_F2 && Files.selected.length === 1) {
                win.beginRename(Files.selected[0]);
                event.accepted = true;
            }
        }
    }

    onVisibleChanged: {
        if (!visible)
            return;
        Files.loadPlaces();
        if (Files.path === "")
            Files.open(Files.home);
    }

    // ---- the folder being shown ------------------------------------------------
    FileDirectory {
        id: dir
        path: Files.path
        includeHidden: Files.showHidden
        sortKey: Files.sortKey
        sortDesc: Files.sortDesc
        onListed: win.sync()
    }

    // the second pane for split view
    FileDirectory {
        id: splitDir
        path: Files.splitPath
        includeHidden: Files.showHidden
        sortKey: Files.sortKey
        sortDesc: Files.sortDesc
        onListed: {
            if (Files.splitActive)
                win.syncSplit();
        }
    }

    // the service keeps the paths and the entries, so a range selection and a
    // lookup by path follow what is on screen
    function sync() {
        const paths = [];
        const entries = [];
        for (let i = 0; i < dir.entries.count; i++) {
            const e = dir.entries.get(i);
            paths.push(e.path);
            entries.push(e);
        }
        Files.setPaths(paths);
        Files.setEntries(entries);
    }

    function syncSplit() {
        const paths = [];
        const entries = [];
        for (let i = 0; i < splitDir.entries.count; i++) {
            const e = splitDir.entries.get(i);
            paths.push(e.path);
            entries.push(e);
        }
        Files.setSplitPaths(paths);
        Files.setSplitEntries(entries);
    }

    // ---- split-pane service functions ----------------------------------------
    function setSplitPaths(paths) {
        Files._splitPaths = paths || [];
    }
    function setSplitEntries(entries) {
        const map = {};
        for (const e of entries || [])
            map[e.path] = e;
        Files._splitEntries = map;
    }


    Item {
        id: blurCard
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // ---- the toolbar ----------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                IconButton { icon: "go-previous"; size: 30; tip: Tr.t("Back"); enabled: Files.canBack; onClicked: Files.back() }
                IconButton { icon: "go-next"; size: 30; tip: Tr.t("Forward"); enabled: Files.canForward; onClicked: Files.forward() }
                IconButton { icon: "go-up"; size: 30; tip: Tr.t("Up"); enabled: Files.canUp; onClicked: Files.up() }

                Icon { name: "folder"; size: 20; color: Theme.accent }
                Text {
                    Layout.maximumWidth: 200
                    text: Files.path === "" ? Tr.t("Files") : Files.path === "recent:" ? Tr.t("Recent") : Files.path.endsWith("/.local/share/Trash/files") ? Tr.t("Trash") : Files.baseName(Files.path) || "/"
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.fontTitle * Theme.fontScale
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                TextField {
                    id: searchBox
                    Layout.preferredWidth: 210
                    placeholder: Tr.t("Search this folder")
                    label: Tr.t("Search this folder")
                    onTextChanged: dir.query = text
                }
                IconButton {
                    icon: Files.viewMode === "grid" ? "view-list" : (Files.viewMode === "columns" ? "view-column" : "view-grid")
                    size: 30
                    tip: Tr.t("Change view")
                    onClicked: {
                        const m = Files.viewMode === "grid" ? "list" : Files.viewMode === "list" ? "columns" : "grid";
                        Files.setViewMode(m);
                    }
                }
                IconButton {
                    icon: "view-sort-descending"
                    size: 30
                    tip: Tr.t("Sort by %1").arg(win.sortLabel())
                    onClicked: Files.setSort(Files.sortKey === "name" ? "size" : Files.sortKey === "size" ? "mtime" : "name")
                }
                IconButton {
                    icon: Files.showHidden ? "view-reveal" : "view-conceal"
                    size: 30
                    tip: Tr.t("Show hidden files")
                    onClicked: Files.toggleHidden()
                }
                IconButton {
                    icon: Files.splitActive ? "view-close" : "view-dual"
                    size: 30
                    tip: Files.splitActive ? Tr.t("Close split view") : Tr.t("Split view (Ctrl+Alt+N)")
                    onClicked: Files.toggleSplit()
                }
                IconButton { icon: "folder-new"; size: 30; tip: Tr.t("New folder"); onClicked: win.openNewFolder() }
                IconButton { icon: "view-refresh"; size: 30; tip: Tr.t("Refresh (F5)"); onClicked: dir.reload() }
            }

            // split pane toolbar
            RowLayout {
                visible: Files.splitActive
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.maximumWidth: 200
                    text: Files.splitPath === "" ? Tr.t("Split") : Files.baseName(Files.splitPath) || "/"
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.fontTitle * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                IconButton {
                    icon: Files.splitViewMode === "grid" ? "view-list" : "view-grid"
                    size: 30
                    tip: Tr.t("Change split view")
                    onClicked: Files.toggleSplitViewMode()
                }
                IconButton { icon: "edit-copy"; size: 30; tip: Tr.t("Copy chosen here"); onClicked: Files.copyToSplit(); enabled: Files.selected.length > 0 }
                IconButton { icon: "edit-cut"; size: 30; tip: Tr.t("Move chosen here"); onClicked: Files.moveToSplit(); enabled: Files.selected.length > 0 }
                IconButton { icon: "go-up"; size: 30; tip: Tr.t("Up"); enabled: Files.splitPath !== "" && Files.splitPath !== "/"; onClicked: { Files.splitPath = FilePaths.parentOf(Files.splitPath); splitDir.reload(); } }
            }

            // ---- the body -------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // the places
                ColumnLayout {
                    // a fixed column: the rows inside would otherwise stretch it to half the window
                    Layout.preferredWidth: 176
                    Layout.maximumWidth: 176
                    Layout.fillWidth: false
                    Layout.fillHeight: true
                    spacing: 2
                    Text {
                        text: Tr.t("Places")
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10 * Theme.fontScale
                    }
                    Repeater {
                        model: Files.places
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            height: 30
                            radius: 8
                            color: Files.path === modelData.path ? Theme.accentSoft
                                 : (placeArea.containsMouse ? Theme.hover : "transparent")
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 6
                                spacing: 8
                                Icon { name: modelData.icon; size: 15; color: Theme.dim }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: Theme.text
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: 12 * Theme.fontScale
                                }
                            }
                            MouseArea {
                                id: placeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Files.open(modelData.path)
                            }
                            KeyFocus {
                                name: modelData.name
                                onActivated: Files.open(modelData.path)
                            }
                        }
                    }
                    // sidebar extras: Recents and Trash
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: Tr.t("Special")
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10 * Theme.fontScale
                            Layout.topMargin: 10
                        }
                        ListRow {
                            Layout.fillWidth: true
                            icon: "document-open-recent"
                            title: Tr.t("Recents")
                            onClicked: Files.open("recent:")
                        }
                        ListRow {
                            Layout.fillWidth: true
                            icon: "user-trash"
                            title: Tr.t("Trash")
                            // what is in the Trash, where it is kept (freedesktop: ~/.local/share/Trash/files)
                            onClicked: Files.open(Files.home + "/.local/share/Trash/files")
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // the folder (main pane)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    // the path, as the parts that lead to it
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Theme.radiusSmall
                        color: Theme.surface1
                        border.width: 1
                        border.color: Theme.stroke
                        Row {
                            id: crumbs
                            anchors.left: parent.left
                            anchors.right: pathBox.visible ? pathBox.left : parent.right
                            anchors.rightMargin: 6
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Repeater {
                                model: win.crumbsModel
                                delegate: Row {
                                    required property var modelData
                                    required property int index
                                    spacing: 2
                                    Text {
                                        text: modelData.name
                                        color: index === win.crumbsModel.length - 1 ? Theme.text : Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: 12 * Theme.fontScale
                                        font.weight: index === win.crumbsModel.length - 1 ? Font.DemiBold : Font.Normal
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Files.open(modelData.path)
                                        }
                                    }
                                    Text {
                                        visible: index < win.crumbsModel.length - 1
                                        text: "›"
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: 12 * Theme.fontScale
                                    }
                                }
                            }
                        }
                        // Ctrl+L: type a path
                        TextField {
                            id: pathBox
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            visible: false
                            label: Tr.t("Path")
                            onAccepted: {
                                const p = Files.normalize(text);
                                pathBox.visible = false;
                                if (p !== "")
                                    Files.open(p);
                            }
                            Keys.onEscapePressed: pathBox.visible = false
                        }
                    }

                    // the files
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusSmall
                        color: Theme.alpha(Theme.bg, 0.35)
                        clip: true

                        // the grid: a tile per file
                        GridView {
                            id: grid
                            anchors.fill: parent
                            anchors.margins: 6
                            visible: Files.viewMode === "grid"
                            model: dir.entries
                            cellWidth: 124
                            cellHeight: 112
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            function orderedFocus() {
                                const out = [];
                                for (let i = 0; i < count; i++) {
                                    const it = itemAtIndex(i);
                                    if (it && it.focusItem)
                                        out.push(it.focusItem);
                                }
                                out.sort((a, b) => (a.parent.y - b.parent.y) || (a.parent.x - b.parent.x));
                                return out;
                            }
                            delegate: Item {
                                id: cell
                                required property var modelData
                                required property int index
                                width: grid.cellWidth
                                height: grid.cellHeight
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    radius: Theme.radiusSmall
                                    color: Files.isSelected(cell.modelData.path) ? Theme.accentSoft
                                         : (cellArea.containsMouse ? Theme.hover : "transparent")
                                    border.width: Files.isSelected(cell.modelData.path) ? 1 : 0
                                    border.color: Theme.accentLine
                                }
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4
                                    FileIcon {
                                        Layout.alignment: Qt.AlignHCenter
                                        entry: cell.modelData
                                        size: 48
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: cell.modelData.name
                                        color: Theme.text
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        wrapMode: Text.Wrap
                                        font.family: Theme.font
                                        font.pixelSize: 11 * Theme.fontScale
                                    }
                                }
                                MouseArea {
                                    id: cellArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                        const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                        Files.select(cell.modelData.path, shift ? "range" : (ctrl ? "toggle" : "single"));
                                    }
                                    onDoubleClicked: Files.openEntry(cell.modelData.path)
                                }
                                KeyFocus {
                                    id: cellFocus
                                    name: cell.modelData.name + (cell.modelData.isDir ? ", " + Tr.t("folder") : "")
                                    columns: Math.max(1, Math.floor(grid.width / grid.cellWidth))
                                    ordered: grid.orderedFocus
                                    onActivated: Files.openEntry(cell.modelData.path)
                                    onMenu: win.openMenu(cell.modelData, cellArea.mapToItem(win, mouseX, mouseY))
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: cell.modelData.name
                                Accessible.onPressAction: Files.select(cell.modelData.path, "single")
                            }
                        }

                        // the list: a row per file
                        ListView {
                            id: list
                            anchors.fill: parent
                            anchors.margins: 4
                            visible: Files.viewMode === "list"
                            model: dir.entries
                            spacing: 1
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            delegate: Item {
                                id: row
                                required property var modelData
                                required property int index
                                width: list.width
                                height: 32
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: Files.isSelected(row.modelData.path) ? Theme.accentSoft
                                         : (rowArea.containsMouse ? Theme.hover : "transparent")
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 10
                                    spacing: 10
                                    FileIcon { entry: row.modelData; size: 20 }
                                    Text {
                                        Layout.fillWidth: true
                                        text: row.modelData.name
                                        color: Theme.text
                                        elide: Text.ElideMiddle
                                        font.family: Theme.font
                                        font.pixelSize: 12 * Theme.fontScale
                                    }
                                    Text {
                                        Layout.preferredWidth: 78
                                        horizontalAlignment: Text.AlignRight
                                        text: row.modelData.isDir ? "" : Files.humanSize(row.modelData.size)
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: 11 * Theme.fontScale
                                    }
                                    Text {
                                        Layout.preferredWidth: 92
                                        horizontalAlignment: Text.AlignRight
                                        text: Files.formatTime(row.modelData.mtime)
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: 11 * Theme.fontScale
                                    }
                                }
                                MouseArea {
                                    id: rowArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                        const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                        Files.select(row.modelData.path, shift ? "range" : (ctrl ? "toggle" : "single"));
                                    }
                                    onDoubleClicked: Files.openEntry(row.modelData.path)
                                }
                                KeyFocus {
                                    name: row.modelData.name + (row.modelData.isDir ? ", " + Tr.t("folder") : "")
                                    onActivated: Files.openEntry(row.modelData.path)
                                    onMenu: win.openMenu(row.modelData, rowArea.mapToItem(win, mouseX, mouseY))
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: row.modelData.name
                                Accessible.onPressAction: Files.select(row.modelData.path, "single")
                            }
                        }

                        // nothing here
                        EmptyState {
                            anchors.centerIn: parent
                            visible: dir.entries.count === 0 && !dir.loading
                            width: parent.width - 40
                            icon: "folder"
                            title: dir.error !== "" ? Tr.t("This folder could not be opened") : Tr.t("This folder is empty")
                            subtitle: dir.error !== "" ? dir.error : Tr.t("Nothing to show here")
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: dir.loading && dir.entries.count === 0
                            text: Tr.t("Loading…")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 13 * Theme.fontScale
                        }
                    }

                    // what is there, and what is chosen
                    Text {
                        Layout.fillWidth: true
                        text: {
                            const parts = [Tr.t("%1 items").arg(dir.entries.count)];
                            if (Files.selected.length > 0)
                                parts.push(Tr.t("%1 selected").arg(Files.selected.length));
                            if (Files.error !== "")
                                parts.push(Files.error);
                            return parts.join("  ·  ");
                        }
                        color: Files.error !== "" ? Theme.red : Theme.faint
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                    }
                }

                // the split pane
                ColumnLayout {
                    visible: Files.splitActive
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    // split path breadcrumbs
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Theme.radiusSmall
                        color: Theme.surface1
                        border.width: 1
                        border.color: Theme.stroke
                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Repeater {
                                model: win.splitCrumbsModel
                                delegate: Row {
                                    required property var modelData
                                    required property int index
                                    spacing: 2
                                    Text {
                                        text: modelData.name
                                        color: index === win.splitCrumbsModel.length - 1 ? Theme.text : Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: 11 * Theme.fontScale
                                        font.weight: index === win.splitCrumbsModel.length - 1 ? Font.DemiBold : Font.Normal
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { Files.splitPath = modelData.path; splitDir.reload(); }
                                        }
                                    }
                                    Text {
                                        visible: index < win.splitCrumbsModel.length - 1
                                        text: "›"
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: 11 * Theme.fontScale
                                    }
                                }
                            }
                        }

                        // split pane files (grid view only for simplicity)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusSmall
                            color: Theme.alpha(Theme.bg, 0.35)
                            clip: true

                            GridView {
                                anchors.fill: parent
                                anchors.margins: 6
                                model: splitDir.entries
                                cellWidth: 110
                                cellHeight: 100
                                boundsBehavior: Flickable.StopAtBounds
                                clip: true
                                delegate: Item {
                                    id: scell
                                    required property var modelData
                                    required property int index
                                    width: 110
                                    height: 100
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        radius: Theme.radiusSmall
                                        color: Files.isSplitSelected(scell.modelData.path) ? Theme.accentSoft
                                             : (scellArea.containsMouse ? Theme.hover : "transparent")
                                    }
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 3
                                        FileIcon {
                                            Layout.alignment: Qt.AlignHCenter
                                            entry: scell.modelData
                                            size: 40
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: scell.modelData.name
                                            color: Theme.text
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            maximumLineCount: 2
                                            wrapMode: Text.Wrap
                                            font.family: Theme.font
                                            font.pixelSize: 10 * Theme.fontScale
                                        }
                                    }
                                    MouseArea {
                                        id: scellArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                            const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                            Files.selectSplit(scell.modelData.path, shift ? "range" : (ctrl ? "toggle" : "single"));
                                        }
                                        onDoubleClicked: { Files.splitPath = scell.modelData.path; splitDir.reload(); }
                                    }
                                    KeyFocus {
                                        name: scell.modelData.name
                                        onActivated: { Files.splitPath = scell.modelData.path; splitDir.reload(); }
                                    }
                                }
                            }

                            EmptyState {
                                anchors.centerIn: parent
                                visible: splitDir.entries.count === 0 && !splitDir.loading
                                width: parent.width - 40
                                icon: "folder"
                                title: Tr.t("This folder is empty")
                                subtitle: Tr.t("Nothing to show here")
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                const parts = [Tr.t("%1 items").arg(splitDir.entries.count)];
                                if (Files.splitSelected.length > 0)
                                    parts.push(Tr.t("%1 selected").arg(Files.splitSelected.length));
                                return parts.join("  ·  ");
                            }
                            color: Theme.faint
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                        }
                    }
                }

                // the preview of what is chosen
                Rectangle {
                    id: preview
                    Layout.preferredWidth: 230
                    Layout.fillHeight: true
                    visible: Files.showPreview && !Files.splitActive
                    radius: Theme.radiusSmall
                    color: Theme.alpha(Theme.bg, 0.35)
                    border.width: 1
                    border.color: Theme.stroke
                    clip: true

                    readonly property var entry: Files.selected.length === 1 ? Files.entryFor(Files.selected[0]) : null

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        visible: preview.entry !== null
                        FileIcon {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 140
                            Layout.preferredHeight: 140
                            entry: preview.entry
                            size: 140
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: preview.entry ? preview.entry.name : ""
                            color: Theme.text
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 12 * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: preview.entry && !preview.entry.isDir ? Files.humanSize(preview.entry.size) : ""
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: preview.entry ? Files.formatTime(preview.entry.mtime) : ""
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                        }
                        Item { Layout.fillHeight: true }
                        Button {
                            Layout.fillWidth: true
                            text: Tr.t("Open")
                            kind: "primary"
                            enabled: preview.entry !== null
                            onClicked: Files.openEntry(preview.entry.path)
                        }
                    }
                    EmptyState {
                        anchors.centerIn: parent
                        visible: preview.entry === null
                        width: parent.width - 24
                        icon: "document-open"
                        title: Tr.t("Nothing chosen")
                        subtitle: Tr.t("Choose a file to see it here")
                    }
                }
            }
        }
    }

    // ---- the right-click menu -------------------------------------------------
    Glass {
        id: menuBox
        parent: win.contentItem
        visible: win.menuEntry !== null
        z: 20
        strong: true
        radius: 12
        width: 230
        height: menuCol.implicitHeight + 12
        x: Math.min(Math.max(8, win.menuX), win.width - width - 8)
        y: Math.min(Math.max(8, win.menuY), win.height - height - 8)
        Column {
            id: menuCol
            x: 6
            y: 6
            width: parent.width - 12
            Repeater {
                model: win.menuItems()
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: menuCol.width
                    height: 30
                    radius: 8
                    color: menuArea.containsMouse ? Theme.hover : "transparent"
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 8
                        Icon { name: modelData.icon; size: 15; color: Theme.dim }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: modelData.danger ? Theme.danger : Theme.text
                            font.family: Theme.font
                            font.pixelSize: 12 * Theme.fontScale
                        }
                    }
                    MouseArea {
                        id: menuArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            win.menuEntry = null;
                            modelData.run();
                        }
                    }
                    KeyFocus {
                        name: modelData.label
                        onActivated: {
                            win.menuEntry = null;
                            modelData.run();
                        }
                    }
                }
            }
        }
    }

    // ---- renaming, and a new folder ---------------------------------------------
    Glass {
        id: renameBox
        parent: win.contentItem
        visible: false
        z: 30
        strong: true
        radius: 12
        width: 360
        height: 118
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            Text {
                text: Tr.t("Rename")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13 * Theme.fontScale
                font.weight: Font.DemiBold
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: renameField
                    Layout.fillWidth: true
                    label: Tr.t("New name")
                    onAccepted: win.commitRename()
                }
                Button { text: Tr.t("Rename"); kind: "primary"; onClicked: win.commitRename() }
            }
        }
    }

    Glass {
        id: newFolderBox
        parent: win.contentItem
        visible: false
        z: 30
        strong: true
        radius: 12
        width: 360
        height: 118
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            Text {
                text: Tr.t("New folder")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13 * Theme.fontScale
                font.weight: Font.DemiBold
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: newFolderField
                    Layout.fillWidth: true
                    label: Tr.t("Folder name")
                    onAccepted: win.commitNewFolder()
                }
                Button { text: Tr.t("Create"); kind: "primary"; onClicked: win.commitNewFolder() }
            }
        }
    }

    // ---- the pieces that need the window ------------------------------------------
    property var menuEntry: null
    property real menuX: 0
    property real menuY: 0

    // the parts of the path, as the buttons that lead to it
    readonly property var crumbsModel: {
        const p = Files.path;
        if (!p || p === "/")
            return [{ name: "/", path: "/" }];
        const home = Files.home;
        const out = [];
        let rest = p;
        let at = "";
        if (home && p.indexOf(home + "/") === 0) {
            out.push({ name: Tr.t("Home"), path: home });
            rest = p.substring(home.length);
            at = home;
        }
        for (const part of rest.split("/").filter(x => x)) {
            at = at + "/" + part;
            out.push({ name: part, path: at });
        }
        // a long path: the last few parts are what matter
        if (out.length > 5)
            return out.slice(0, 1).concat(out.slice(-3));
        return out;
    }

    readonly property var splitCrumbsModel: {
        const p = Files.splitPath;
        if (!p || p === "/")
            return [{ name: "/", path: "/" }];
        const home = Files.home;
        const out = [];
        let rest = p;
        let at = "";
        if (home && p.indexOf(home + "/") === 0) {
            out.push({ name: Tr.t("Home"), path: home });
            rest = p.substring(home.length);
            at = home;
        }
        for (const part of rest.split("/").filter(x => x)) {
            at = at + "/" + part;
            out.push({ name: part, path: at });
        }
        if (out.length > 5)
            return out.slice(0, 1).concat(out.slice(-3));
        return out;
    }

    function sortLabel() {
        if (Files.sortKey === "size")
            return Tr.t("size");
        if (Files.sortKey === "mtime")
            return Tr.t("date");
        return Tr.t("name");
    }

    function openMenu(entry, point) {
        if (!entry)
            return;
        menuEntry = entry;
        menuX = point.x;
        menuY = point.y;
    }

    function menuItems() {
        const e = menuEntry;
        if (!e)
            return [];
        const items = [];
        if (e.isDir)
            items.push({ label: Tr.t("Open"), icon: "folder-open", danger: false, run: () => Files.open(e.path) });
        else
            items.push({ label: Tr.t("Open"), icon: "document-open", danger: false, run: () => Files.openEntry(e.path) });
        items.push({ label: Tr.t("Open with…"), icon: "view-app-grid", danger: false, run: () => { /* handled by Ui.openFilesWith */ } });
        items.push({ label: Tr.t("Rename"), icon: "document-edit", danger: false, run: () => beginRename(e.path) });
        items.push({ label: Tr.t("Duplicate"), icon: "edit-copy", danger: false, run: () => Files.duplicateEntry(e.path) });
        items.push({ label: Tr.t("Copy path"), icon: "edit-copy", danger: false, run: () => Files.copyPath(e.path) });
        items.push({ label: Tr.t("Share…"), icon: "folder-publicshare", danger: false, run: () => Share.open(e.path) });
        items.push({ label: Tr.t("Move to trash"), icon: "edit-delete", danger: true, run: () => Files.trashEntries([e.path]) });
        return items;
    }

    function beginRename(path) {
        const e = Files.entryFor(path);
        if (!e)
            return;
        renameField.text = e.name;
        renameBox.visible = true;
        renameField.forceActiveFocus();
        renameField.selectAll();
    }

    function commitRename() {
        const path = Files.selected.length === 1 ? Files.selected[0] : "";
        const name = renameField.text;
        renameBox.visible = false;
        if (!path || !Files.validName(name))
            return;
        Files.renameEntry(path, name);
    }

    function openNewFolder() {
        newFolderField.text = "";
        newFolderBox.visible = true;
        newFolderField.forceActiveFocus();
    }

    function commitNewFolder() {
        const name = newFolderField.text;
        newFolderBox.visible = false;
        if (!Files.validName(name))
            return;
        Files.makeFolder(name);
    }
}