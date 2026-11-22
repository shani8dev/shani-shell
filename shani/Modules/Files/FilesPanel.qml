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
import qs.Modules.Files
import "../../Common/FilePaths.js" as FilePaths

AppWindow {
    id: win
    property var openWithPaths: []
    appName: "Files"
    visible: Ui.files
    onGone: Files.hide()
    margins: 0
    implicitWidth: Theme.px(1100)
    implicitHeight: Theme.px(760)

    // the keys the surface answers, wherever the focus is not on a control
    Item {
        id: keys
        anchors.fill: parent
        focus: win.visible
        // Escape goes back a folder first, and out of the surface at the top
        Keys.onEscapePressed: {
            if (renameBox.visible || newFolderBox.visible || batchBox.visible || Files.props || Files.comparison || Files.syncAsk || Files.usb || Files.unlockFor || Files.locker || (Files.cloudAsk && !Files.cloudAdding) || win.serveAsk !== "" || Files.conflictAsk || Files.copyTo || Files.historyShown || Files.deleteAsk.length) {
                renameBox.visible = false;
                newFolderBox.visible = false;
                batchBox.visible = false;
                Files.props = null;
                Files.comparison = null;
                Files.syncCancel();
                if (!Files.usbBusy) Files.usb = null;
                Files.unlockFor = null;
                Files.locker = null;
                if (!Files.cloudAdding) Files.cloudAsk = false;
                win.serveAsk = "";
                if (Files.conflictAsk) Files.answerConflict("");
                Files.copyTo = null;
                Files.historyShown = false;
                Files.deleteAsk = [];
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
            // Ctrl+Shift+I: the selection turned over
            if (control && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_I) {
                Files.invertSelection();
                event.accepted = true;
                return;
            }
            // Ctrl+plus / minus / 0: bigger, smaller, as it was
            if (control && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.key === Qt.Key_Minus || event.key === Qt.Key_0)) {
                Files.setZoom(event.key === Qt.Key_0 ? 1 : Files.zoom + (event.key === Qt.Key_Minus ? -0.2 : 0.2));
                event.accepted = true;
                return;
            }
            // tabs: Ctrl+T a new one here, Ctrl+W this one closed, Ctrl+Tab / Ctrl+Shift+Tab the next / the last
            if (control && event.key === Qt.Key_T) { Files.newTab(Files.path); event.accepted = true; return; }
            if (control && event.key === Qt.Key_W && Files.tabs.length > 1) { Files.closeTab(); event.accepted = true; return; }
            if (control && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && Files.tabs.length > 1) {
                const n = Files.tabs.length, back = event.key === Qt.Key_Backtab;
                Files.switchTab((Files.tabIndex + (back ? n - 1 : 1)) % n);
                event.accepted = true;
                return;
            }
            // type to find: the first file whose name starts with what was typed
            // (a pause of a second starts again); a space only once a name is begun
            // (Delete's text is \x7f, a "character" too: it stays Delete)
            if (!control && !alt && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                    && (event.key !== Qt.Key_Space || win.typed !== "")) {
                win.typed += event.text.toLowerCase();
                typedTimer.restart();
                const hit = Files._paths.find(p => Files.baseName(p).toLowerCase().startsWith(win.typed));
                if (hit) {
                    Files.select(hit, "single");
                    const i = Files._paths.indexOf(hit);
                    if (grid.visible) grid.positionViewAtIndex(i, GridView.Contain); else list.positionViewAtIndex(i, ListView.Contain);
                }
                event.accepted = true;
                return;
            }
            // the file clipboard, undo, Properties, search
            if (control && !alt && (event.key === Qt.Key_C || event.key === Qt.Key_X) && Files.selected.length > 0) {
                Files.toClipboard(event.key === Qt.Key_X ? "cut" : "copy", []);
                event.accepted = true;
                return;
            }
            if (control && !alt && event.key === Qt.Key_V) {
                Files.pasteHere(Files.path);
                event.accepted = true;
                return;
            }
            if (control && !alt && ((event.key === Qt.Key_Z && (event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Y)) {
                Files.redo();
                event.accepted = true;
                return;
            }
            if (control && !alt && event.key === Qt.Key_Z) {
                Files.undo();
                event.accepted = true;
                return;
            }
            if (control && event.key === Qt.Key_F) {
                searchBox.forceActiveFocus();
                event.accepted = true;
                return;
            }
            if (alt && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && Files.selected.length > 0) {
                Files.showProps([]);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_F5) {
                dir.reload();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Delete && Files.selected.length > 0 && (event.modifiers & Qt.ShiftModifier) && !Files.isTrash) {
                Files.deleteAsk = Files.selected.slice();         // asked first: no trash to come back from
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Delete && Files.selected.length > 0) {
                Files.trashEntries([]);
                event.accepted = true;
                return;
            }
            // Space: Quick Look at the file the keyboard is on (or the one chosen),
            // with the folder's files to walk with Left and Right
            if (event.key === Qt.Key_Space && !control && !alt) {
                const at = Files.current || (Files.selected.length ? Files.selected[0] : "");
                if (at) {
                    QuickLook.open(at, Files._paths);
                    event.accepted = true;
                    return;
                }
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
    // the search box's words, settled (a new search per keystroke would walk the tree each time)
    property string deepWords: ""
    Timer { id: deepTimer; interval: 400; onTriggered: win.deepWords = searchBox.text.trim().length >= 2 ? searchBox.text.trim() : "" }
    readonly property bool searchingDeep: Files.searchDeep && deepWords !== "" && Files.path.startsWith("/")
    FileDirectory {
        id: dir
        path: win.searchingDeep ? Files.searchPath(win.deepWords) : Files.path
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

    // a folder sync finished: both panes show the folders as they are now
    Connections {
        target: Files
        function onSyncFinished() { dir.reload(); splitDir.reload(); }
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
        // a picture shows itself; the rest may have a thumbnail (a video, a PDF, an office file)
        Files.requestThumbs(entries.filter(e => !e.isDir && !e.image).map(e => e.path));
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

    // ---- "Open with…" app picker ---------------------------------------------
    LazyLoader {
        active: win.openWithPaths.length > 0
        PopupWindow {
            visible: true
            implicitWidth: Theme.px(380)
            implicitHeight: Theme.px(520)
            color: Theme.glassStrong
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(12)
                spacing: Theme.px(8)
                AppPicker {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    label: Tr.t("Open %1 with…").arg(win.openWithPaths.length)
                    onPicked: id => {
                        Files.openWith(id, win.openWithPaths);
                        win.openWithPaths = [];
                    }
                }
                Button {
                    Layout.alignment: Qt.AlignRight
                    text: Tr.t("Cancel")
                    onClicked: win.openWithPaths = []
                }
            }
        }
    }

    Item {
        id: blurCard
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(10)

            // ---- the toolbar ----------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)

                IconButton { icon: "go-previous"; size: Theme.px(30); tip: Tr.t("Back"); enabled: Files.canBack; onClicked: Files.back() }
                IconButton { icon: "go-next"; size: Theme.px(30); tip: Tr.t("Forward"); enabled: Files.canForward; onClicked: Files.forward() }
                IconButton { icon: "go-up"; size: Theme.px(30); tip: Tr.t("Up"); enabled: Files.canUp; onClicked: Files.up() }

                Icon { name: "folder"; size: Theme.px(20); color: Theme.accent }
                Text {
                    Layout.maximumWidth: Theme.px(200)
                    text: Files.placeTitle(Files.path)
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.fontTitle * Theme.fontScale
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                TextField {
                    id: searchBox
                    Layout.preferredWidth: Theme.px(210)
                    placeholder: Tr.t("Search this folder")
                    label: Tr.t("Search this folder")
                    onTextChanged: { Files.searchText = text; dir.query = Files.searchDeep ? "" : text; deepTimer.restart(); }
                    Connections { target: Files; function onSearchTextChanged() { if (searchBox.text !== Files.searchText) searchBox.text = Files.searchText; } }
                }
                // through the folders under this one too (the words then search a tree, not a folder)
                IconButton {
                    icon: "folder-saved-search"
                    size: Theme.px(30)
                    on: Files.searchDeep
                    tip: Files.searchDeep ? Tr.t("Searching the folders inside too") : Tr.t("Search the folders inside too")
                    onClicked: { Files.setSearchDeep(!Files.searchDeep); dir.query = Files.searchDeep ? "" : searchBox.text; deepTimer.restart(); }
                }
                IconButton {
                    icon: Files.viewMode === "grid" ? "view-list" : (Files.viewMode === "columns" ? "view-column" : "view-grid")
                    size: Theme.px(30)
                    tip: Tr.t("Change view")
                    onClicked: {
                        const m = Files.viewMode === "grid" ? "list" : Files.viewMode === "list" ? "columns" : "grid";
                        Files.setViewMode(m);
                    }
                }
                IconButton {
                    icon: "view-sort-descending"
                    size: Theme.px(30)
                    tip: Tr.t("Sort by %1").arg(win.sortLabel())
                    onClicked: Files.setSort(Files.sortKey === "name" ? "size" : Files.sortKey === "size" ? "mtime" : "name")
                }
                IconButton {
                    icon: Files.showHidden ? "view-reveal" : "view-conceal"
                    size: Theme.px(30)
                    tip: Tr.t("Show hidden files")
                    onClicked: Files.toggleHidden()
                }
                IconButton {
                    icon: Files.splitActive ? "view-close" : "view-dual"
                    size: Theme.px(30)
                    tip: Files.splitActive ? Tr.t("Close split view") : Tr.t("Split view (Ctrl+Alt+N)")
                    onClicked: Files.toggleSplit()
                }
                IconButton { icon: "edit-paste"; size: Theme.px(30); tip: Tr.t("Paste here (Ctrl+V)"); onClicked: Files.pasteHere(Files.path) }
                IconButton { icon: "edit-undo"; size: Theme.px(30); tip: Files.undoLabel ? Tr.t("Undo: %1 (Ctrl+Z)", Files.undoLabel) : Tr.t("Nothing to undo"); enabled: Files.undoLabel !== ""; onClicked: Files.undo() }
                IconButton { visible: Files.isTrash; icon: "user-trash-full"; size: Theme.px(30); on: win.confirmEmpty
                             tip: win.confirmEmpty ? Tr.t("Click again: everything in the trash is deleted for good") : Tr.t("Empty the trash")
                             onClicked: { if (!win.confirmEmpty) { win.confirmEmpty = true; confirmTimer.restart(); return; } win.confirmEmpty = false; Files.emptyTrash(); } }
                IconButton { icon: "folder-new"; size: Theme.px(30); tip: Tr.t("New folder"); onClicked: win.openNewFolder() }
                IconButton { icon: "edit-clear-all"; size: Theme.px(30); tip: Tr.t("Tidy this folder: files into folders by kind"); onClicked: Tidy.plan(Files.path) }
                IconButton { icon: "view-refresh"; size: Theme.px(30); tip: Tr.t("Refresh (F5)"); onClicked: dir.reload() }
            }

            // split pane toolbar
            RowLayout {
                visible: Files.splitActive
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text {
                    Layout.maximumWidth: Theme.px(200)
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
                    size: Theme.px(30)
                    tip: Tr.t("Change split view")
                    onClicked: Files.toggleSplitViewMode()
                }
                IconButton { icon: "edit-copy"; size: Theme.px(30); tip: Tr.t("Copy chosen here"); onClicked: Files.copyToSplit(); enabled: Files.selected.length > 0 }
                IconButton { icon: "edit-cut"; size: Theme.px(30); tip: Tr.t("Move chosen here"); onClicked: Files.moveToSplit(); enabled: Files.selected.length > 0 }
                IconButton { icon: "go-up"; size: Theme.px(30); tip: Tr.t("Up"); enabled: Files.splitPath !== "" && Files.splitPath !== "/"; onClicked: { Files.splitPath = FilePaths.parentOf(Files.splitPath); splitDir.reload(); } }
            }

            // ---- the body -------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.px(10)

                // the places
                ColumnLayout {
                    // a fixed column: the rows inside would otherwise stretch it to half the window
                    Layout.preferredWidth: Theme.px(176)
                    Layout.maximumWidth: Theme.px(176)
                    Layout.fillWidth: false
                    Layout.fillHeight: true
                    spacing: 2
                    Text {
                        text: Tr.t("Places")
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                    Repeater {
                        // a drive the Devices list below shows is not listed twice
                        model: Files.places.filter(p => !Files.devices.some(d => d.path && d.path === p.path))
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            height: Theme.px(30)
                            radius: Theme.px(8)
                            color: Files.path === modelData.path ? Theme.accentSoft
                                 : (placeArea.containsMouse ? Theme.hover : "transparent")
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.px(8)
                                anchors.rightMargin: Theme.px(6)
                                spacing: Theme.px(8)
                                Icon { name: modelData.icon; size: Theme.px(15); color: Theme.dim }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: Theme.text
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(12) * Theme.fontScale
                                }
                            }
                            FileDropArea {
                                id: placeDrop
                                anchors.fill: parent
                                dest: modelData.path
                                Rectangle { anchors.fill: parent; visible: placeDrop.hovering; color: "transparent"; radius: Theme.px(8); border.width: 2; border.color: Theme.accent }
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
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            Layout.topMargin: Theme.px(10)
                        }
                        ListRow {
                            Layout.fillWidth: true
                            icon: "document-open-recent"
                            title: Tr.t("Recents")
                            onClicked: Files.open("recent:")
                        }
                        ListRow {
                            Layout.fillWidth: true
                            icon: "starred"
                            title: Tr.t("Starred")
                            visible: Files.starred.length > 0
                            onClicked: Files.open("starred:")
                        }
                        // every file of a kind, wherever it is in your folders (ES File
                        // Explorer's Library)
                        Repeater {
                            model: Files.kinds
                            ListRow {
                                required property var modelData
                                Layout.fillWidth: true
                                icon: modelData[1]
                                title: Files.placeTitle("kind:" + modelData[0])
                                onClicked: Files.open("kind:" + modelData[0])
                            }
                        }
                        ListRow {
                            Layout.fillWidth: true
                            icon: "user-trash"
                            title: Tr.t("Trash")
                            // what is in the Trash, where it is kept (freedesktop: ~/.local/share/Trash/files)
                            onClicked: Files.open(Files.home + "/.local/share/Trash/files")
                        }
                    }
                    // drives, phones, cameras and network places (gio): open - mounting first
                    // when needed - and eject; the computer's other drives below them
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        visible: Files.devices.length > 0
                        Text {
                            text: Tr.t("Devices")
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                            Layout.topMargin: Theme.px(10)
                        }
                        Repeater {
                            model: Files.devices.filter(d => !d.internal).concat(Files.devices.filter(d => d.internal))
                            delegate: Rectangle {
                                id: devRow
                                required property var modelData
                                Layout.fillWidth: true
                                height: Theme.px(30)
                                radius: Theme.px(8)
                                color: modelData.path && Files.path.startsWith(modelData.path) ? Theme.accentSoft
                                     : (devArea.containsMouse ? Theme.hover : "transparent")
                                opacity: modelData.mounted ? 1 : 0.75
                                FileDropArea {
                                    id: devDrop
                                    anchors.fill: parent
                                    dest: devRow.modelData.mounted ? devRow.modelData.path : ""
                                    Rectangle { anchors.fill: parent; visible: devDrop.hovering; color: "transparent"; radius: Theme.px(8); border.width: 2; border.color: Theme.accent }
                                }
                                MouseArea {
                                    id: devArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Files.openDevice(devRow.modelData)
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.px(8)
                                    anchors.rightMargin: Theme.px(2)
                                    spacing: Theme.px(8)
                                    Icon { name: devRow.modelData.icon; size: Theme.px(15); color: Theme.dim }
                                    Text {
                                        Layout.fillWidth: true
                                        text: devRow.modelData.name + (devRow.modelData.internal ? " · " + Tr.t("this computer") : "")
                                        color: Theme.text
                                        elide: Text.ElideRight
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(12) * Theme.fontScale
                                    }
                                    IconButton {
                                        visible: devRow.modelData.mounted && (devRow.modelData.canEject || devRow.modelData.canUnmount)
                                        enabled: Files.busyDevice !== devRow.modelData.mount
                                        icon: "media-eject"
                                        size: Theme.px(24)
                                        tip: devRow.modelData.canEject ? Tr.t("Eject %1", devRow.modelData.name) : Tr.t("Close %1", devRow.modelData.name)
                                        onClicked: Files.ejectDevice(devRow.modelData)
                                    }
                                }
                                KeyFocus { name: devRow.modelData.name; onActivated: Files.openDevice(devRow.modelData) }
                                Accessible.role: Accessible.Button
                                Accessible.name: devRow.modelData.name
                                Accessible.onPressAction: Files.openDevice(devRow.modelData)
                            }
                        }
                    }
                    ListRow {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.px(4)
                        icon: "folder-remote"
                        title: Tr.t("Connect to server…")
                        onClicked: { Files.connectError = ""; Files.connectNeedsLogin = false; Files.loadServers(); connectBox.visible = true; }
                    }
                    // cloud drives (rclone): a click opens one; the cross forgets it here
                    Text {
                        text: Tr.t("Cloud")
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                        Layout.topMargin: Theme.px(10)
                        visible: Files.clouds.length > 0
                    }
                    Repeater {
                        model: Files.clouds
                        RowLayout {
                            id: cloudRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 0
                            property bool confirm: false
                            ListRow {
                                Layout.fillWidth: true
                                icon: "folder-cloud"
                                title: cloudRow.modelData.name + " · " + cloudRow.modelData.label
                                onClicked: Files.openCloud(cloudRow.modelData)
                            }
                            IconButton {
                                icon: cloudRow.confirm ? "edit-delete" : "window-close"
                                size: Theme.px(22)
                                tip: cloudRow.confirm ? Tr.t("Click again to remove %1 from this computer (the files in the cloud stay)", cloudRow.modelData.name) : Tr.t("Remove %1", cloudRow.modelData.name)
                                onClicked: { if (cloudRow.confirm) Files.forgetCloud(cloudRow.modelData); cloudRow.confirm = !cloudRow.confirm; }
                            }
                        }
                    }
                    ListRow {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.px(4)
                        icon: "folder-cloud"
                        title: Tr.t("Add a cloud drive…")
                        onClicked: { Files.cloudError = ""; Files.cloudAsk = true; }
                    }
                    ListRow {
                        Layout.fillWidth: true
                        visible: Files.devices.some(d => !d.internal && d.canEject && !d.network)
                        icon: "drive-removable-media"
                        title: Tr.t("USB drives…")
                        onClicked: Files.openUsb("format")
                    }
                    Item { Layout.fillHeight: true }
                }

                // the folder (main pane)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.px(8)

                    // tabs: shown once there are two (Ctrl+T); each its own folder
                    RowLayout {
                        Layout.fillWidth: true
                        visible: Files.tabs.length > 1
                        spacing: Theme.px(4)
                        Repeater {
                            model: Files.tabPaths
                            Rectangle {
                                id: tabChip
                                required property string modelData
                                required property int index
                                readonly property bool on: index === Files.tabIndex
                                Layout.preferredWidth: Math.min(Theme.px(180), tabRow.implicitWidth + Theme.px(16))
                                implicitHeight: Theme.px(30)
                                radius: Theme.radiusSmall
                                color: on ? Theme.accentSoft : (tabArea.containsMouse ? Theme.hover : Theme.surface1)
                                border.width: on ? 1 : 0
                                border.color: Theme.accentLine
                                FileDropArea { id: tabDrop; anchors.fill: parent; dest: tabChip.modelData.startsWith("/") ? tabChip.modelData : "" }
                                MouseArea { id: tabArea; anchors.fill: parent; hoverEnabled: true; onClicked: Files.switchTab(tabChip.index) }
                                RowLayout {
                                    id: tabRow
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.px(10)
                                    anchors.rightMargin: Theme.px(2)
                                    spacing: Theme.px(4)
                                    Text {
                                        Layout.fillWidth: true
                                        text: Files.placeTitle(tabChip.modelData)
                                        elide: Text.ElideMiddle
                                        color: Theme.text
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(12) * Theme.fontScale
                                    }
                                    IconButton { icon: "window-close"; size: Theme.px(22); tip: Tr.t("Close this tab"); onClicked: Files.closeTab(tabChip.index) }
                                }
                                Accessible.role: Accessible.PageTab
                                Accessible.name: tabChip.modelData
                                Accessible.onPressAction: Files.switchTab(tabChip.index)
                            }
                        }
                        IconButton { icon: "list-add"; size: Theme.px(26); tip: Tr.t("New tab (Ctrl+T)"); onClicked: Files.newTab(Files.path) }
                        Item { Layout.fillWidth: true }
                    }

                    // the path, as the parts that lead to it
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.px(32)
                        radius: Theme.radiusSmall
                        color: Theme.surface1
                        border.width: 1
                        border.color: Theme.stroke
                        Row {
                            id: crumbs
                            anchors.left: parent.left
                            anchors.right: pathBox.visible ? pathBox.left : parent.right
                            anchors.rightMargin: Theme.px(6)
                            anchors.leftMargin: Theme.px(8)
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
                                        font.pixelSize: Theme.px(12) * Theme.fontScale
                                        font.weight: index === win.crumbsModel.length - 1 ? Font.DemiBold : Font.Normal
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Files.open(modelData.path)
                                        }
                                        // keys and a controller: a folder up the path, as the click
                                        Accessible.role: Accessible.Button
                                        Accessible.name: modelData.name
                                        KeyFocus { onActivated: Files.open(modelData.path) }
                                    }
                                    Text {
                                        visible: index < win.crumbsModel.length - 1
                                        text: "›"
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(12) * Theme.fontScale
                                    }
                                }
                            }
                        }
                        // Ctrl+L: type a path
                        TextField {
                            id: pathBox
                            anchors.fill: parent
                            anchors.leftMargin: Theme.px(6)
                            anchors.rightMargin: Theme.px(6)
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

                        // a drop on the folder's background goes into the folder on screen
                        FileDropArea {
                            id: paneDrop
                            anchors.fill: parent
                            dest: Files.path.startsWith("/") && !Files.isTrash ? Files.path : ""
                            Rectangle {
                                anchors.fill: parent
                                visible: paneDrop.hovering
                                color: Theme.alpha(Theme.accent, 0.06); radius: Theme.radiusSmall
                                border.width: 2; border.color: Theme.accent
                            }
                        }

                        // a right-click on the background: the folder's own menu (new folder,
                        // new document, paste, terminal, select all, turn the selection over)
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            enabled: Files.path.startsWith("/") && !Files.isTrash
                            onClicked: mouse => win.openMenu({ path: Files.path, isDir: true, background: true, name: Files.baseName(Files.path) }, mapToItem(win, mouse.x, mouse.y))
                        }

                        // the grid: a tile per file
                        GridView {
                            id: grid
                            anchors.fill: parent
                            anchors.margins: Theme.px(6)
                            visible: Files.viewMode === "grid"
                            model: dir.entries
                            cellWidth: Math.round(124 * Files.zoom)
                            cellHeight: Math.round(112 * Files.zoom)
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
                                    anchors.margins: Theme.px(3)
                                    radius: Theme.radiusSmall
                                    color: Files.isSelected(cell.modelData.path) ? Theme.accentSoft
                                         : (cellArea.containsMouse ? Theme.hover : "transparent")
                                    border.width: Files.isSelected(cell.modelData.path) ? 1 : 0
                                    border.color: Theme.accentLine
                                }
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(8)
                                    spacing: Theme.px(4)
                                    FileIcon {
                                        Layout.alignment: Qt.AlignHCenter
                                        entry: cell.modelData
                                        thumbnail: Files.thumbs[cell.modelData.path] || ""
                                        size: Theme.px(48) * Files.zoom
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
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                }
                                // dragged: the file (or the selection it is part of) as text/uri-list,
                                // a real drag other apps take too; a folder takes drops itself
                                Item {
                                    id: cellDrag
                                    width: 1; height: 1
                                    Drag.active: cellArea.drag.active
                                    Drag.dragType: Drag.Automatic
                                    Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                                    Drag.proposedAction: Qt.MoveAction
                                    Drag.mimeData: ({ "text/uri-list": Files.dragUris(cell.modelData.path) })
                                }
                                FileDropArea {
                                    id: cellDrop
                                    anchors.fill: parent
                                    dest: cell.modelData.isDir ? cell.modelData.path : ""
                                    Rectangle {
                                        anchors.fill: parent; anchors.margins: Theme.px(2)
                                        visible: cellDrop.hovering
                                        color: "transparent"; radius: Theme.radiusSmall
                                        border.width: 2; border.color: Theme.accent
                                    }
                                }
                                MouseArea {
                                    id: cellArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    drag.target: cellDrag
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onReleased: { cellDrag.x = 0; cellDrag.y = 0; }
                                    onClicked: mouse => {
                                        // right: the menu - of the selection when this is in it, else of this one
                                        if (mouse.button === Qt.RightButton) {
                                            if (!Files.isSelected(cell.modelData.path)) Files.select(cell.modelData.path, "single");
                                            win.openMenu(cell.modelData, cellArea.mapToItem(win, mouse.x, mouse.y));
                                            return;
                                        }
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
                                    peekable: true
                                    onPeek: QuickLook.open(cell.modelData.path, Files._paths)
                                    onActiveFocusChanged: if (activeFocus) Files.current = cell.modelData.path
                                    menuable: true
                                    onMenu: win.openMenu(cell.modelData, cellArea.mapToItem(win, mouseX, mouseY))
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: cell.modelData.name
                                Accessible.onPressAction: Files.select(cell.modelData.path, "single")
                            }
                        }

                        // the list: a row per file
                        ListView {
                            reuseItems: true
                            cacheBuffer: 400
                            id: list
                            anchors.fill: parent
                            anchors.margins: Theme.px(4)
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
                                height: Theme.px(32)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.px(6)
                                    color: Files.isSelected(row.modelData.path) ? Theme.accentSoft
                                         : (rowArea.containsMouse ? Theme.hover : "transparent")
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.px(8)
                                    anchors.rightMargin: Theme.px(10)
                                    spacing: Theme.px(10)
                                    FileIcon { entry: row.modelData; thumbnail: Files.thumbs[row.modelData.path] || ""; size: Theme.px(20) }
                                    Text {
                                        Layout.fillWidth: true
                                        text: row.modelData.name
                                        color: Theme.text
                                        elide: Text.ElideMiddle
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(12) * Theme.fontScale
                                    }
                                    Text {
                                        Layout.preferredWidth: Theme.px(78)
                                        horizontalAlignment: Text.AlignRight
                                        text: row.modelData.isDir ? "" : Files.humanSize(row.modelData.size)
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                    Text {
                                        Layout.preferredWidth: Theme.px(92)
                                        horizontalAlignment: Text.AlignRight
                                        text: Files.formatTime(row.modelData.mtime)
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                }
                                // dragged: the file (or the selection it is part of) as text/uri-list,
                                // a real drag other apps take too; a folder takes drops itself
                                Item {
                                    id: rowDrag
                                    width: 1; height: 1
                                    Drag.active: rowArea.drag.active
                                    Drag.dragType: Drag.Automatic
                                    Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                                    Drag.proposedAction: Qt.MoveAction
                                    Drag.mimeData: ({ "text/uri-list": Files.dragUris(row.modelData.path) })
                                }
                                FileDropArea {
                                    id: rowDrop
                                    anchors.fill: parent
                                    dest: row.modelData.isDir ? row.modelData.path : ""
                                    Rectangle {
                                        anchors.fill: parent; anchors.margins: Theme.px(2)
                                        visible: rowDrop.hovering
                                        color: "transparent"; radius: Theme.radiusSmall
                                        border.width: 2; border.color: Theme.accent
                                    }
                                }
                                MouseArea {
                                    id: rowArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    drag.target: rowDrag
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onReleased: { rowDrag.x = 0; rowDrag.y = 0; }
                                    onClicked: mouse => {
                                        // right: the menu - of the selection when this is in it, else of this one
                                        if (mouse.button === Qt.RightButton) {
                                            if (!Files.isSelected(row.modelData.path)) Files.select(row.modelData.path, "single");
                                            win.openMenu(row.modelData, rowArea.mapToItem(win, mouse.x, mouse.y));
                                            return;
                                        }
                                        const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                        const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                        Files.select(row.modelData.path, shift ? "range" : (ctrl ? "toggle" : "single"));
                                    }
                                    onDoubleClicked: Files.openEntry(row.modelData.path)
                                }
                                KeyFocus {
                                    name: row.modelData.name + (row.modelData.isDir ? ", " + Tr.t("folder") : "")
                                    onActivated: Files.openEntry(row.modelData.path)
                                    peekable: true
                                    onPeek: QuickLook.open(row.modelData.path, Files._paths)
                                    onActiveFocusChanged: if (activeFocus) Files.current = row.modelData.path
                                    menuable: true
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
                            font.pixelSize: Theme.px(13) * Theme.fontScale
                        }
                    }

                    // what is there, and what is chosen
                    Text {
                        Layout.fillWidth: true
                        text: {
                            const parts = [Tr.t("%1 items").arg(dir.entries.count)];
                            if (Files.freeBytes >= 0)
                                parts.push(Tr.t("%1 free").arg(Files.humanSize(Files.freeBytes)));
                            if (Files.selected.length > 0)
                                parts.push(Tr.t("%1 selected").arg(Files.selected.length));
                            if (Files.error !== "")
                                parts.push(Files.error);
                            return parts.join("  ·  ");
                        }
                        color: Files.error !== "" ? Theme.red : Theme.faint
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }

                // the split pane
                ColumnLayout {
                    visible: Files.splitActive
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.px(8)

                    // split path breadcrumbs
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.px(32)
                        radius: Theme.radiusSmall
                        color: Theme.surface1
                        border.width: 1
                        border.color: Theme.stroke
                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.px(6)
                            anchors.leftMargin: Theme.px(8)
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
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                        font.weight: index === win.splitCrumbsModel.length - 1 ? Font.DemiBold : Font.Normal
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { Files.splitPath = modelData.path; splitDir.reload(); }
                                        }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: modelData.name
                                        KeyFocus { onActivated: { Files.splitPath = modelData.path; splitDir.reload(); } }
                                    }
                                    Text {
                                        visible: index < win.splitCrumbsModel.length - 1
                                        text: "›"
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
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

                            FileDropArea {
                                id: splitDrop
                                anchors.fill: parent
                                dest: Files.splitPath.startsWith("/") ? Files.splitPath : ""
                                Rectangle { anchors.fill: parent; visible: splitDrop.hovering; color: Theme.alpha(Theme.accent, 0.06); radius: Theme.radiusSmall; border.width: 2; border.color: Theme.accent }
                            }
                            GridView {
                                anchors.fill: parent
                                anchors.margins: Theme.px(6)
                                model: splitDir.entries
                                cellWidth: 110
                                cellHeight: 100
                                boundsBehavior: Flickable.StopAtBounds
                                clip: true
                                delegate: Item {
                                    id: scell
                                    required property var modelData
                                    required property int index
                                    width: Theme.px(110)
                                    height: Theme.px(100)
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: Theme.px(3)
                                        radius: Theme.radiusSmall
                                        color: Files.isSplitSelected(scell.modelData.path) ? Theme.accentSoft
                                             : (scellArea.containsMouse ? Theme.hover : "transparent")
                                    }
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.px(6)
                                        spacing: Theme.px(3)
                                        FileIcon {
                                            Layout.alignment: Qt.AlignHCenter
                                            entry: scell.modelData
                                            thumbnail: Files.thumbs[scell.modelData.path] || ""
                                            size: Theme.px(40)
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
                                            font.pixelSize: Theme.px(10) * Theme.fontScale
                                        }
                                    }
                                    Item {
                                        id: scellDrag
                                        width: 1; height: 1
                                        Drag.active: scellArea.drag.active
                                        Drag.dragType: Drag.Automatic
                                        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                                        Drag.proposedAction: Qt.MoveAction
                                        Drag.mimeData: ({ "text/uri-list": (Files.isSplitSelected(scell.modelData.path) ? Files.splitSelected : [scell.modelData.path]).map(Files.uriOf).filter(u => u !== "").join("\r\n") + "\r\n" })
                                    }
                                    FileDropArea {
                                        id: scellDrop
                                        anchors.fill: parent
                                        dest: scell.modelData.isDir ? scell.modelData.path : ""
                                        Rectangle { anchors.fill: parent; anchors.margins: Theme.px(2); visible: scellDrop.hovering; color: "transparent"; radius: Theme.radiusSmall; border.width: 2; border.color: Theme.accent }
                                    }
                                    MouseArea {
                                        id: scellArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        drag.target: scellDrag
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onReleased: { scellDrag.x = 0; scellDrag.y = 0; }
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.RightButton) {
                                                win.openMenu(scell.modelData, scellArea.mapToItem(win, mouse.x, mouse.y));
                                                return;
                                            }
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
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                    }
                }

                // the preview of what is chosen
                Rectangle {
                    id: preview
                    Layout.preferredWidth: Theme.px(230)
                    Layout.minimumWidth: Theme.px(190)   // keep the empty state readable
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
                        anchors.margins: Theme.px(12)
                        spacing: Theme.px(8)
                        visible: preview.entry !== null
                        FileIcon {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Theme.px(140)
                            Layout.preferredHeight: Theme.px(140)
                            entry: preview.entry
                            size: Theme.px(140)
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: (preview.entry && preview.entry.name) || ""
                            color: Theme.text
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: preview.entry && !preview.entry.isDir ? Files.humanSize(preview.entry.size) : ""
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        // what the camera recorded, for a picture
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            visible: PhotoMeta.camera !== "" || PhotoMeta.date !== ""
                            text: [PhotoMeta.camera, PhotoMeta.date].filter(x => x !== "").join("\n")
                            color: Theme.dim
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: preview.entry ? Files.formatTime(preview.entry.mtime) : ""
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
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
        radius: Theme.px(12)
        width: Theme.px(230)
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
                    height: Theme.px(30)
                    radius: Theme.px(8)
                    color: menuArea.containsMouse ? Theme.hover : "transparent"
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(8)
                        anchors.rightMargin: Theme.px(6)
                        spacing: Theme.px(8)
                        Icon { name: modelData.icon; size: Theme.px(15); color: Theme.dim }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: modelData.danger ? Theme.danger : Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                        }
                    }
                    MouseArea {
                        id: menuArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            const keep = !!modelData.keep;      // "Delete for good": the first click only arms it
                            modelData.run();
                            if (!keep) win.menuEntry = null;
                        }
                    }
                    KeyFocus {
                        name: modelData.label
                        onActivated: {
                            const keep = !!modelData.keep;
                            modelData.run();
                            if (!keep) win.menuEntry = null;
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
        solid: true
        radius: Theme.px(12)
        width: Theme.px(420)
        height: renameCol.implicitHeight + 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        ColumnLayout {
            id: renameCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(10)
            Text {
                text: Tr.t("Rename")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                TextField {
                    id: renameField
                    Layout.fillWidth: true
                    label: Tr.t("New name")
                    onAccepted: win.commitRename()
                }
                Button { text: Tr.t("Rename"); kind: "primary"; onClicked: win.commitRename() }
            }
            // "Suggest a name": what Chronoa is doing, or why there is no suggestion
            Text {
                Layout.fillWidth: true
                visible: win.suggesting && (Tidy.naming || Tidy.namingError !== "" || Tidy.suggestion !== "")
                text: Tidy.naming ? Tr.t("Chronoa is reading it…") : Tidy.namingError !== "" ? Tidy.namingError : Tr.t("Chronoa's suggestion — change it or press Enter")
                color: Tidy.namingError !== "" ? Theme.danger : Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
        }
    }
    property bool suggesting: false
    Connections {
        target: Tidy
        function onSuggestionChanged() {
            if (win.suggesting && renameBox.visible && Tidy.suggestion !== "") {
                renameField.text = Tidy.suggestion;
                renameField.forceActiveFocus();
            }
        }
    }
    Connections { target: renameBox; function onVisibleChanged() { if (!renameBox.visible) win.suggesting = false; } }

    // ---- Tidy: what goes where, shown first; then Undo ----
    Glass {
        parent: win.contentItem
        visible: Tidy.folder === Files.path && Files.path !== "" && (Tidy.planned.length > 0 || Tidy.note !== "" || Tidy.planning)
        z: 25
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, 460)
        height: tidyCol.implicitHeight + 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.px(70)
        ColumnLayout {
            id: tidyCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                text: Tidy.planning ? Tr.t("Looking at the files…") : Tidy.planned.length ? Tr.t("Tidy %1: %2 files into folders by kind", Files.path.split("/").pop() || "/", Tidy.planned.length) : Tidy.note
                color: Theme.text
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Repeater {
                model: Tidy.groups
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Icon { name: "folder"; size: Theme.px(16); color: Theme.accent }
                    Text { Layout.fillWidth: true; text: modelData.group; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                    Text { text: Tr.t("%1 files", modelData.count); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: Tidy.planned.length > 0
                text: Tr.t("Nothing is written over, files still downloading stay, and Undo puts every one back.")
                color: Theme.faint
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tidy.planned.length ? Tr.t("Cancel") : Tr.t("Close"); flat: true; onClicked: { Tidy.cancel(); Tidy.note = ""; } }
                Button { visible: Tidy.canUndo && Tidy.planned.length === 0; text: Tr.t("Undo"); onClicked: { Tidy.undo(); dir.reload(); } }
                Button { visible: Tidy.planned.length > 0; kind: "primary"; text: Tr.t("Sort them"); onClicked: Tidy.apply() }
            }
        }
    }
    Connections { target: Tidy; function onMovedChanged() { dir.reload(); } function onNoteChanged() { dir.reload(); } }

    Glass {
        id: newFolderBox
        parent: win.contentItem
        visible: false
        z: 30
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Theme.px(360)
        height: Theme.px(118)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(10)
            Text {
                text: Tr.t("New folder")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
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

    // ---- several renamed at once: a pattern, and what it will make of them ----------
    Glass {
        id: batchBox
        parent: win.contentItem
        visible: false
        z: 30
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Theme.px(460)
        height: batchCol.implicitHeight + 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        ColumnLayout {
            id: batchCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                text: Tr.t("Rename %1 files", win.batchPaths.length)
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("# is the number, in the order they are chosen; each keeps its own extension")
                color: Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                TextField {
                    id: batchField
                    Layout.fillWidth: true
                    label: Tr.t("New names")
                    onAccepted: { batchBox.visible = false; Files.batchRename(text, win.batchPaths); }
                }
                Button { text: Tr.t("Rename"); kind: "primary"; onClicked: { batchBox.visible = false; Files.batchRename(batchField.text, win.batchPaths); } }
            }
            Repeater {
                model: win.batchPreview(batchField.text)
                Text {
                    required property string modelData
                    text: "→ " + modelData
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
            }
        }
    }

    // ---- Compare: two texts side by side, or what differs between two folders ------
    Glass {
        id: compareBox
        parent: win.contentItem
        visible: Files.comparison !== null
        z: 31
        strong: true
        solid: true
        radius: Theme.px(12)
        width: parent.width * 0.9
        height: parent.height * 0.85
        anchors.centerIn: parent
        readonly property var c: Files.comparison || ({})
        readonly property var rows: c.rows || []
        // where each change starts, for Next / Previous
        readonly property var starts: {
            const out = [];
            for (let i = 0; i < rows.length; i++)
                if ((rows[i].tag && rows[i].tag !== "equal" && (i === 0 || rows[i - 1].tag === "equal")) || rows[i].state)
                    out.push(i);
            return out;
        }
        function jump(dir) {
            const at = compareList.indexAt(0, compareList.contentY + 1);
            const cur = at < 0 ? -1 : at;
            const next = dir > 0 ? starts.find(i => i > cur) : starts.slice().reverse().find(i => i < cur);
            if (next !== undefined) compareList.positionViewAtIndex(next, ListView.Beginning);
        }
        function summary() {
            if (c.loading) return Tr.t("Comparing…");
            if (c.error) return c.error;
            if (c.kind === "binary") return c.same ? Tr.t("The same") : Tr.t("They differ (not text, so not line by line)");
            if (!c.changes) return Tr.t("The same");
            return c.kind === "folders" ? Tr.t("%1 differences", c.changes) : Tr.t("%1 changes", c.changes);
        }
        function shade(tag) {
            if (tag === "insert" || tag === "only-right") return Qt.alpha(Theme.accent, 0.20);
            if (tag === "delete" || tag === "only-left") return Qt.alpha(Theme.danger, 0.20);
            if (tag === "replace" || tag === "differs") return Qt.alpha(Theme.amber, 0.22);
            return "transparent";
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: FilePaths.baseName(compareBox.c.a || "") + "  ↔  " + FilePaths.baseName(compareBox.c.b || "") + "   ·   " + compareBox.summary()
                    elide: Text.ElideMiddle
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "go-up"; size: Theme.px(26); tip: Tr.t("Previous change"); visible: compareBox.starts.length > 0; onClicked: compareBox.jump(-1) }
                IconButton { icon: "go-down"; size: Theme.px(26); tip: Tr.t("Next change"); visible: compareBox.starts.length > 0; onClicked: compareBox.jump(1) }
                Button { visible: Files.compareEdited.l; text: Tr.t("Save left"); onClicked: Files.compareSave(false) }
                Button { visible: Files.compareEdited.r; text: Tr.t("Save right"); kind: "primary"; onClicked: Files.compareSave(true) }
                IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Close"); onClicked: Files.comparison = null }
            }
            // folder comparison only: sync one side into the other with rsync
            RowLayout {
                Layout.fillWidth: true
                visible: compareBox.c.kind === "folders"
                spacing: Theme.px(6)
                Text {
                    text: Tr.t("Sync:")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Button {
                    id: syncModeBtn
                    text: Files.syncMode === "mirror" ? Tr.t("Mirror · delete extra files") : Tr.t("Update · newer files only")
                    onClicked: Files.syncMode = Files.syncMode === "mirror" ? "update" : "mirror"
                    Hint { text: Files.syncMode === "mirror" ? Tr.t("rsync -a --delete: the right side becomes a copy of the left") : Tr.t("rsync -au: only newer files are copied, nothing is deleted") }
                }
                Text {
                    visible: Files.syncBusy
                    text: Tr.t("Syncing…")
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: Tr.t("Sync →")
                    enabled: !Files.syncBusy
                    onClicked: Files.syncFolders(compareBox.c.a, compareBox.c.b, Files.syncMode)
                    Hint { text: Tr.t("Sync %1 into %2", FilePaths.baseName(compareBox.c.a || ""), FilePaths.baseName(compareBox.c.b || "")) }
                }
                Button {
                    text: Tr.t("Sync ←")
                    enabled: !Files.syncBusy
                    onClicked: Files.syncFolders(compareBox.c.b, compareBox.c.a, Files.syncMode)
                    Hint { text: Tr.t("Sync %1 into %2", FilePaths.baseName(compareBox.c.b || ""), FilePaths.baseName(compareBox.c.a || "")) }
                }
            }
            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: compareList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: compareBox.rows
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: compareList.width
                    height: Math.max(lt.implicitHeight, rt.implicitHeight) + 2
                    color: compareBox.shade(modelData.tag || modelData.state)
                    // a folder comparison: the path, and which side has it
                    Text {
                        visible: compareBox.c.kind === "folders"
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(6)
                        text: (modelData.path || "") + "   —   " + (modelData.state === "only-left" ? Tr.t("only in %1", FilePaths.baseName(compareBox.c.a || ""))
                              : modelData.state === "only-right" ? Tr.t("only in %1", FilePaths.baseName(compareBox.c.b || "")) : Tr.t("differs"))
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        verticalAlignment: Text.AlignVCenter
                    }
                    // a change's first line: its lines copied to the other side (Meld's arrows)
                    Row {
                        z: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        visible: compareBox.c.kind === "text" && modelData.tag && modelData.tag !== "equal" && (index === 0 || compareBox.rows[index - 1].tag === "equal")
                        IconButton { icon: "go-next"; size: Theme.px(20); tip: Tr.t("Copy this change to the right"); onClicked: Files.compareTake(index, true) }
                        IconButton { icon: "go-previous"; size: Theme.px(20); tip: Tr.t("Copy this change to the left"); onClicked: Files.compareTake(index, false) }
                    }
                    Row {
                        visible: compareBox.c.kind === "text"
                        anchors.fill: parent
                        Text {
                            id: lt
                            width: parent.width / 2
                            leftPadding: Theme.px(6)
                            text: modelData.l === null || modelData.l === undefined ? "" : (modelData.ln + "  " + modelData.l)
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.mono
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                        }
                        Text {
                            id: rt
                            width: parent.width / 2
                            leftPadding: Theme.px(6)
                            text: modelData.r === null || modelData.r === undefined ? "" : (modelData.rn + "  " + modelData.r)
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.mono
                            font.pixelSize: Theme.px(12) * Theme.fontScale
                        }
                    }
                }
            }
        }
    }

    // ---- folder sync: confirm before rsync, --delete is destructive ------------------
    Glass {
        id: syncBox
        parent: win.contentItem
        visible: Files.syncAsk !== null
        z: 32
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Theme.px(560)
        height: syncCol.implicitHeight + 28
        anchors.centerIn: parent
        readonly property var a: Files.syncAsk || ({})
        ColumnLayout {
            id: syncCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                text: syncBox.a.mode === "mirror"
                    ? Tr.t("Mirror %1 into %2? Files only on the right will be deleted.", FilePaths.baseName(syncBox.a.left || ""), FilePaths.baseName(syncBox.a.right || ""))
                    : Tr.t("Update %1 into %2? Only newer files are copied, nothing is deleted.", FilePaths.baseName(syncBox.a.left || ""), FilePaths.baseName(syncBox.a.right || ""))
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Dry run — what rsync would do:")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(Theme.px(220), syncPrev.implicitHeight + Theme.px(8))
                clip: true
                contentHeight: syncPrev.implicitHeight
                Text {
                    id: syncPrev
                    width: parent.width
                    text: Files.syncPreview
                    color: Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    wrapMode: Text.Wrap
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); onClicked: Files.syncCancel() }
                Button {
                    text: syncBox.a.mode === "mirror" ? Tr.t("Delete extra files and sync") : Tr.t("Sync")
                    kind: "primary"
                    onClicked: Files.syncConfirm()
                    Hint { text: Tr.t("Runs: %1", Files.syncCommand || "rsync") }
                }
            }
        }
    }

    // ---- Properties ------------------------------------------------------------------
    Glass {
        id: propsBox
        parent: win.contentItem
        visible: Files.props !== null
        z: 30
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Theme.px(420)
        height: propsCol.implicitHeight + 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        readonly property var p: Files.props || ({})
        function row(label, value) { return value ? [label, value] : null; }
        ColumnLayout {
            id: propsCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(6)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: propsBox.p.name || Tr.t("%1 items", propsBox.p.count || 0)
                    elide: Text.ElideMiddle
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Close"); onClicked: Files.props = null }
            }
            Repeater {
                model: propsBox.p.loading ? [[Tr.t("Size"), Tr.t("Counting…")]] : [
                    propsBox.row(Tr.t("Kind"), propsBox.p.type === "folder" ? Tr.t("Folder") : propsBox.p.type),
                    propsBox.row(Tr.t("Size"), Files.humanSize(propsBox.p.size || 0) + (propsBox.p.partial ? " +" : "")
                        + ((propsBox.p.files || propsBox.p.dirs) ? "  ·  " + Tr.t("%1 files, %2 folders", propsBox.p.files || 0, propsBox.p.dirs || 0) : "")),
                    propsBox.row(Tr.t("Where"), propsBox.p.path ? FilePaths.parentOf(propsBox.p.path) : ""),
                    propsBox.row(Tr.t("Changed"), propsBox.p.mtime ? Files.formatTime(propsBox.p.mtime) : ""),
                    propsBox.row(Tr.t("Created"), propsBox.p.btime ? Files.formatTime(propsBox.p.btime) : ""),
                    propsBox.row(Tr.t("Opened"), propsBox.p.atime ? Files.formatTime(propsBox.p.atime) : ""),
                    propsBox.row(Tr.t("Owner"), propsBox.p.owner ? propsBox.p.owner + (propsBox.p.group && propsBox.p.group !== propsBox.p.owner ? " · " + propsBox.p.group : "") : ""),
                    propsBox.row(Tr.t("Permissions"), propsBox.p.mode || "")
                ].filter(r => r)
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.px(10)
                    Text { text: modelData[0]; Layout.preferredWidth: Theme.px(96); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                    Text { Layout.fillWidth: true; text: modelData[1]; wrapMode: Text.WrapAnywhere; color: Theme.text; font.family: modelData[0] === Tr.t("Permissions") ? Theme.mono : Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                }
            }
            // who else may open it, and whether it runs as a program: the rights, changed
            // here (with Undo) - the group and everyone else alike, as Nautilus offers it
            Picks {
                id: othersPick
                visible: !propsBox.p.loading && !!propsBox.p.path && propsBox.p.perm !== undefined
                readonly property bool dir: propsBox.p.type === "folder"
                readonly property int perm: propsBox.p.perm || 0
                label: Tr.t("Who else can open it")
                options: [{ label: Tr.t("Only you"), value: "0" }, { label: Tr.t("Everyone can look"), value: "4" }, { label: Tr.t("Everyone can change"), value: "6" }]
                current: String((perm >> 3) & 6)
                onPicked: v => {
                    const r = parseInt(v), x = dir ? (r ? 1 : 0) : ((perm >> 3) & 1);
                    const g = r | x, mode = (perm & 0o7700) | (g << 3) | g;
                    Files.setRights([[propsBox.p.path, mode]], Tr.t("Who can open %1 changed", propsBox.p.name));
                }
            }
            SwitchRow {
                Layout.fillWidth: true
                visible: othersPick.visible && !othersPick.dir
                text: Tr.t("Run as a program")
                hint: Tr.t("For a script or an app you trust: it may then do anything you can")
                checked: (othersPick.perm & 0o100) !== 0
                onToggled: on => {
                    const p = othersPick.perm;
                    // the run bit for you, and for whoever may read it
                    const mode = on ? p | 0o100 | ((p & 0o040) ? 0o010 : 0) | ((p & 0o004) ? 0o001 : 0) : p & ~0o111;
                    Files.setRights([[propsBox.p.path, mode]], on ? Tr.t("%1 runs as a program", propsBox.p.name) : Tr.t("%1 no longer runs", propsBox.p.name));
                }
            }
        }
    }

    // ---- Connect to server: smb://, sftp://, ftp://, dav(s)://, nfs:// (gio); ssh:// (sshfs)
    // the servers used before are a click each; the address is typed only the first time
    Glass {
        id: connectBox
        objectName: "files-connect"
        parent: win.contentItem
        visible: false
        z: 30
        strong: true
        solid: true
        radius: Theme.px(14)
        width: Math.min(parent.width - 40, Theme.px(440))
        height: connectCol.implicitHeight + 28
        anchors.centerIn: parent
        onVisibleChanged: if (visible) { serverField.text = Files.recentServers.length ? Files.recentServers[0] : ""; serverField.input.forceActiveFocus(); }
        ColumnLayout {
            id: connectCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text { text: Tr.t("Connect to server"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale; font.weight: Font.DemiBold }
            // what the network announces: a click connects (Nautilus's "Networks")
            Text {
                visible: Files.servers.length > 0
                text: Tr.t("On this network")
                color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                visible: Files.servers.length > 0
                Repeater {
                    model: Files.servers
                    Choice {
                        required property var modelData
                        text: modelData.name + " · " + Tr.t(modelData.kind)
                        selected: serverField.text === modelData.uri
                        onClicked: { serverField.text = modelData.uri; Files.connectServer(modelData.uri, "", "", ""); }
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                visible: Files.recentServers.length > 0
                Repeater {
                    model: Files.recentServers
                    Choice { required property string modelData; text: modelData; selected: serverField.text === modelData; onClicked: serverField.text = modelData }
                }
            }
            TextField {
                id: serverField
                Layout.fillWidth: true
                placeholder: "smb://server/share · ssh://user@host/path · davs://host/path"
                label: Tr.t("Server address")
                onAccepted: connectGo.clicked()
            }
            TextField { id: userField; Layout.fillWidth: true; visible: Files.connectNeedsLogin; placeholder: Tr.t("User name"); label: Tr.t("User name") }
            TextField { id: passField; Layout.fillWidth: true; visible: Files.connectNeedsLogin; placeholder: Tr.t("Password"); label: Tr.t("Password"); secret: true; onAccepted: connectGo.clicked() }
            Text {
                Layout.fillWidth: true
                visible: Files.connectError !== ""
                text: Files.connectNeedsLogin ? Tr.t("This server asks who you are: %1", Files.connectError) : Files.connectError
                color: Theme.danger; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: connectBox.visible = false }
                Button {
                    id: connectGo
                    text: Files.connecting ? Tr.t("Connecting…") : Tr.t("Connect")
                    enabled: !Files.connecting && serverField.text.trim() !== ""
                    onClicked: Files.connectServer(serverField.text, userField.text, passField.text, "")
                }
            }
            Connections { target: Files; function onConnectingChanged() { if (!Files.connecting && Files.connectError === "") { connectBox.visible = false; passField.text = ""; } } }
        }
    }

    // ---- Shift+Delete: asked, since there is no trash to come back from ------------
    Glass {
        id: deleteBox
        parent: win.contentItem
        visible: Files.deleteAsk.length > 0
        z: 34
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(420))
        height: deleteCol.implicitHeight + 28
        anchors.centerIn: parent
        ColumnLayout {
            id: deleteCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(10)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Files.deleteAsk.length === 1 ? Tr.t("Delete %1 for good? It does not go to the trash, so it cannot be put back.", FilePaths.baseName(Files.deleteAsk[0] || ""))
                                                   : Tr.t("Delete these %1 for good? They do not go to the trash, so they cannot be put back.", Files.deleteAsk.length)
                color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: Files.deleteAsk = [] }
                Button { text: Tr.t("Move to the trash instead"); onClicked: { const p = Files.deleteAsk; Files.deleteAsk = []; Files.trashEntries(p); } }
                Button { kind: "danger"; text: Tr.t("Delete"); onClicked: Files.deleteNow(Files.deleteAsk) }
            }
        }
    }

    // ---- a name already there: one rule for the whole job (TeraCopy's choices) ------
    Glass {
        id: conflictBox
        parent: win.contentItem
        visible: Files.conflictAsk !== null
        z: 34
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(460))
        height: conflictCol.implicitHeight + 28
        anchors.centerIn: parent
        readonly property var c: Files.conflictAsk || ({ names: [] })
        ColumnLayout {
            id: conflictCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: conflictBox.c.names.length === 1 ? Tr.t("%1 is already in %2. What should happen?", conflictBox.c.names[0], FilePaths.baseName(conflictBox.c.dest || ""))
                    : Tr.t("%1 of these are already in %2 (%3). What should happen to them?", conflictBox.c.names.length, FilePaths.baseName(conflictBox.c.dest || ""), conflictBox.c.names.slice(0, 3).join(", ") + (conflictBox.c.names.length > 3 ? "…" : ""))
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
            }
            Repeater {
                model: [["rename", Tr.t("Keep both"), Tr.t("the new one is named \"name (2)\"")],
                        ["skip", Tr.t("Skip them"), Tr.t("the ones there stay; folders get what they are missing")],
                        ["older", Tr.t("Replace the older ones"), Tr.t("only where what comes in is newer")],
                        ["differs", Tr.t("Replace where different"), Tr.t("size or date not the same")],
                        ["replace", Tr.t("Replace them all"), Tr.t("the replaced ones go to the trash")]]
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    title: modelData[1]
                    subtitle: modelData[2]
                    onClicked: Files.answerConflict(modelData[0])
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Choice { text: Tr.t("Check every copy (verify)"); selected: Files.jobVerify; onClicked: Files.setVerify(!Files.jobVerify) }
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: Files.answerConflict("") }
            }
        }
    }

    // ---- Copy to… / Move to…: a folder, the ones used lately first -----------------
    Glass {
        id: copyToBox
        parent: win.contentItem
        visible: Files.copyTo !== null
        z: 33
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(460))
        height: copyToCol.implicitHeight + 28
        anchors.centerIn: parent
        readonly property var c: Files.copyTo || ({ paths: [] })
        ColumnLayout {
            id: copyToCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: (copyToBox.c.mode === "move" ? Tr.t("Move %1 to…", copyToBox.c.paths.length === 1 ? FilePaths.baseName(copyToBox.c.paths[0]) : Tr.t("%1 items", copyToBox.c.paths.length))
                                                  : Tr.t("Copy %1 to…", copyToBox.c.paths.length === 1 ? FilePaths.baseName(copyToBox.c.paths[0]) : Tr.t("%1 items", copyToBox.c.paths.length)))
                color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.DemiBold
            }
            Repeater {
                // the ones used lately, the other pane, the sidebar's places and drives
                model: {
                    const seen = {}, out = [];
                    const add = p => { if (p && p.startsWith("/") && !seen[p]) { seen[p] = true; out.push(p); } };
                    Files.recentDests.forEach(add);
                    if (Files.splitActive) add(Files.splitPath);
                    Files.places.forEach(p => add(p.path));
                    Files.devices.filter(d => d.mounted).forEach(d => add(d.path));
                    return out.slice(0, 10);
                }
                ListRow {
                    required property string modelData
                    Layout.fillWidth: true
                    icon: "folder"
                    title: FilePaths.baseName(modelData) || "/"
                    subtitle: modelData.replace(Files.home, "~")
                    onClicked: Files.sendTo(copyToBox.c.mode, modelData)
                }
            }
            FolderPicker { id: copyToPick; Layout.fillWidth: true; label: Tr.t("Another folder"); onPicked: path => Files.sendTo(copyToBox.c.mode, path) }
            RowLayout {
                Layout.fillWidth: true
                Choice { text: Tr.t("Check every copy (verify)"); selected: Files.jobVerify; onClicked: Files.setVerify(!Files.jobVerify) }
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: Files.copyTo = null }
            }
        }
    }

    // ---- what could not be copied: listed, with Retry (just those) -------------------
    Glass {
        id: failedBox
        parent: win.contentItem
        visible: Files.jobFailed.length > 0 && !Files.jobRunning
        z: 29
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(520))
        height: Math.min(failedCol.implicitHeight + 24, parent.height * 0.6)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.px(18)
        ColumnLayout {
            id: failedCol
            anchors.fill: parent
            anchors.margins: Theme.px(12)
            spacing: Theme.px(4)
            Text {
                Layout.fillWidth: true
                text: Tr.t("%1 could not be copied - the rest were", Files.jobFailed.length)
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; font.weight: Font.DemiBold
            }
            Repeater {
                model: Files.jobFailed.slice(0, 8)
                Text {
                    required property var modelData
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: FilePaths.baseName(modelData.path) + " - " + modelData.error
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Dismiss"); flat: true; onClicked: Files.jobFailed = [] }
                Button { kind: "primary"; text: Tr.t("Retry these"); onClicked: Files.retryFailed() }
            }
        }
    }

    // ---- the copies done lately (TeraCopy's history) ---------------------------------
    Glass {
        id: historyBox
        parent: win.contentItem
        visible: Files.historyShown
        z: 33
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(560))
        height: parent.height * 0.7
        anchors.centerIn: parent
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(6)
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: Tr.t("Copy history"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale; font.weight: Font.DemiBold }
                IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Close"); onClicked: Files.historyShown = false }
            }
            Text { visible: !Files.copyHistory.length; text: Tr.t("No copies yet"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
            ListView {
                reuseItems: true
                cacheBuffer: 400
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: Files.copyHistory
                spacing: Theme.px(4)
                delegate: ColumnLayout {
                    required property var modelData
                    width: ListView.view.width
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: (modelData.mode === "move" ? Tr.t("Moved") : modelData.mode === "hash" ? Tr.t("Checksums") : modelData.mode === "check" ? Tr.t("Tested") : Tr.t("Copied"))
                              + " " + (modelData.names || []).join(", ") + ((modelData.items || 0) > (modelData.names || []).length ? "…" : "")
                              + (modelData.dest && modelData.dest !== "-" ? " → " + modelData.dest.replace(Files.home, "~") : "")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Files.formatTime((modelData.time || 0) * 1000) + " · " + Files.humanSize(modelData.bytes || 0) + " in " + (modelData.seconds || 0) + " s"
                              + (modelData.verified ? " · " + Tr.t("%1 checked", modelData.verified) : "")
                              + (modelData.failed ? " · " + Tr.t("%1 failed", modelData.failed) : "")
                              + (modelData.skipped ? " · " + Tr.t("%1 skipped", modelData.skipped) : "")
                              + (modelData.cancelled ? " · " + Tr.t("stopped") : "")
                        color: modelData.failed ? Theme.danger : Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                }
            }
        }
    }

    // ---- a cloud drive added: which one, its name; the sign-in is the provider's own
    //      page in the browser (Nextcloud / WebDAV: its address and login here)
    Glass {
        id: cloudBox
        parent: win.contentItem
        visible: Files.cloudAsk
        z: 33
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(440))
        height: cloudCol.implicitHeight + 28
        anchors.centerIn: parent
        property string kind: "drive"
        onVisibleChanged: if (visible) { kind = "drive"; cloudName.text = ""; cloudUrl.text = ""; cloudUser.text = ""; cloudPass.text = ""; }
        readonly property var labels: ({ drive: "Google Drive", onedrive: "OneDrive", dropbox: "Dropbox", box: "Box", pcloud: "pCloud", yandex: "Yandex Disk", webdav: "Nextcloud / WebDAV" })
        readonly property string name: cloudName.text.trim() || labels[kind]
        ColumnLayout {
            id: cloudCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text { text: Tr.t("Add a cloud drive"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale; font.weight: Font.DemiBold }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: ["drive", "onedrive", "dropbox", "box", "pcloud", "yandex", "webdav"]
                    Choice { required property string modelData; text: cloudBox.labels[modelData]; selected: cloudBox.kind === modelData; onClicked: cloudBox.kind = modelData }
                }
            }
            TextField { id: cloudName; Layout.fillWidth: true; placeholderText: Tr.t("Name (optional): %1", cloudBox.labels[cloudBox.kind]) }
            TextField { id: cloudUrl; visible: cloudBox.kind === "webdav"; Layout.fillWidth: true; placeholderText: "https://cloud.example.org/remote.php/dav/files/you" }
            TextField { id: cloudUser; visible: cloudBox.kind === "webdav"; Layout.fillWidth: true; placeholderText: Tr.t("User name") }
            TextField { id: cloudPass; visible: cloudBox.kind === "webdav"; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Password (an app password, where it has them)") }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: cloudBox.kind !== "webdav" || Files.cloudAdding
                text: Files.cloudAdding && cloudBox.kind !== "webdav" ? Tr.t("Sign in on the page that opened in your browser, then come back here.")
                    : Tr.t("Its sign-in page opens in your browser; this computer keeps only the permission it gives.")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Text {
                visible: Files.cloudError !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Files.cloudError
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; enabled: !Files.cloudAdding; onClicked: Files.cloudAsk = false }
                Button {
                    kind: "primary"
                    busy: Files.cloudAdding
                    enabled: !Files.cloudAdding && (cloudBox.kind !== "webdav" || (cloudUrl.text.trim() !== "" && cloudUser.text.trim() !== ""))
                    text: cloudBox.kind === "webdav" ? Tr.t("Add") : Tr.t("Sign in")
                    onClicked: Files.addCloud(cloudBox.name, cloudBox.kind, cloudUrl.text.trim(), cloudUser.text.trim(), cloudPass.text)
                }
            }
        }
    }

    // ---- a folder opened to phones: asked first (may they add files?), then a bar
    //      with its link and Stop while it runs; the QR code is the shell's QrView
    property string serveAsk: ""
    Glass {
        id: serveBox
        parent: win.contentItem
        visible: win.serveAsk !== "" || Files.servedPath !== ""
        z: 28
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(480))
        height: serveCol.implicitHeight + 24
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.px(64)
        property bool upload: false
        ColumnLayout {
            id: serveCol
            anchors.fill: parent
            anchors.margins: Theme.px(12)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Files.servedPath !== ""
                    ? (Files.servedUrl ? Tr.t("%1 is open to this network at %2 - point a phone's camera at the code. It stops by itself after an hour unused.", FilePaths.baseName(Files.servedPath), Files.servedUrl)
                                       : Tr.t("Opening %1…", FilePaths.baseName(Files.servedPath)))
                    : Tr.t("Open %1 to phones and computers on this network, through their web browser, until you stop it?", FilePaths.baseName(win.serveAsk))
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Choice { visible: Files.servedPath === ""; text: Tr.t("They can add files too"); selected: serveBox.upload; onClicked: serveBox.upload = !serveBox.upload }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { visible: Files.servedPath === ""; text: Tr.t("Cancel"); flat: true; onClicked: win.serveAsk = "" }
                Button { visible: Files.servedPath === ""; kind: "primary"; text: Tr.t("Open it"); onClicked: { Files.serveFolder(win.serveAsk, serveBox.upload); win.serveAsk = ""; serveBox.upload = false; } }
                Button { visible: Files.servedUrl !== ""; text: Tr.t("Show the code"); flat: true; onClicked: Qr.show(Tr.t("Open %1 on your phone", FilePaths.baseName(Files.servedPath)), Files.servedUrl) }
                Button { visible: Files.servedPath !== ""; kind: "danger"; text: Tr.t("Stop"); onClicked: Files.stopServing() }
            }
        }
    }

    // ---- a password: locking a file, unlocking it, a new or locked encrypted folder ----
    Glass {
        id: lockBox
        parent: win.contentItem
        visible: Files.locker !== null
        z: 33
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(420))
        height: lockCol.implicitHeight + 28
        anchors.centerIn: parent
        readonly property var l: Files.locker || ({})
        readonly property bool twice: l.mode === "lock" || l.mode === "vault-new"
        property bool trashOriginal: false
        onVisibleChanged: if (visible) {
            lockPass.text = ""; lockPass2.text = ""; vaultName.text = ""; trashOriginal = false;
            (l.mode === "vault-new" ? vaultName : lockPass).input.forceActiveFocus();
        }
        readonly property bool ready: lockPass.text !== "" && (!twice || lockPass.text === lockPass2.text)
                                      && (l.mode !== "vault-new" || vaultName.text.trim() !== "")
        function go() {
            if (!ready) return;
            Files.doLock(lockPass.text, l.mode === "vault-new" ? vaultName.text.trim() : trashOriginal);
        }
        ColumnLayout {
            id: lockCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: { const n = FilePaths.baseName(lockBox.l.path || "");
                    return lockBox.l.mode === "lock" ? (/\.pdf$/i.test(n) ? Tr.t("Lock %1 with a password. A locked copy is made beside it; any PDF reader asks for the password.", n)
                                                                          : Files.lockAsZip ? Tr.t("Lock %1 with a password, as a ZIP beside it: 7-Zip, WinRAR, Keka and this computer open it.", n)
                                                                          : Tr.t("Lock %1 with a password. It is sealed into a .gpg file beside it (gpg opens it).", n))
                         : lockBox.l.mode === "unlock" ? Tr.t("The password of %1. An unlocked copy is made beside it.", n)
                         : lockBox.l.mode === "vault-new" ? Tr.t("A new encrypted folder in %1: what you put in it is kept encrypted, file by file, and opens only with its password.", n)
                         : Tr.t("%1 is an encrypted folder. Its password opens it.", n); }
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
            }
            TextField { id: vaultName; visible: lockBox.l.mode === "vault-new"; Layout.fillWidth: true; placeholderText: Tr.t("Name, e.g. Private"); onAccepted: lockPass.input.forceActiveFocus() }
            TextField { id: lockPass; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Password"); onAccepted: lockBox.twice ? lockPass2.input.forceActiveFocus() : lockBox.go() }
            TextField { id: lockPass2; visible: lockBox.twice; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("The password again"); onAccepted: lockBox.go() }
            Text {
                visible: lockBox.twice && lockPass2.text !== "" && lockPass.text !== lockPass2.text
                text: Tr.t("The two are not the same")
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Flow {
                visible: lockBox.l.mode === "lock" && !/\.pdf$/i.test(lockBox.l.path || "")
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Choice { text: Tr.t("ZIP with a password"); selected: Files.lockAsZip; onClicked: Files.lockAsZip = true }
                Choice { text: Tr.t("Sealed with gpg"); selected: !Files.lockAsZip; onClicked: Files.lockAsZip = false }
            }
            Choice { visible: lockBox.l.mode === "lock"; text: Tr.t("Move the original to the trash"); selected: lockBox.trashOriginal; onClicked: lockBox.trashOriginal = !lockBox.trashOriginal }
            Text {
                visible: lockBox.twice
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Tr.t("There is no way back in without the password: keep it somewhere safe.")
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Text {
                visible: Files.lockError !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Files.lockError
                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: Files.locker = null }
                Button {
                    kind: "primary"
                    busy: Files.lockBusy
                    enabled: lockBox.ready && !Files.lockBusy
                    text: lockBox.l.mode === "lock" ? Tr.t("Lock") : lockBox.l.mode === "vault-new" ? Tr.t("Make it") : Tr.t("Unlock")
                    onClicked: lockBox.go()
                }
            }
        }
    }

    // ---- an encrypted drive's password ------------------------------------------------
    Glass {
        id: unlockBox
        parent: win.contentItem
        visible: Files.unlockFor !== null
        z: 32
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(400))
        height: unlockCol.implicitHeight + 28
        anchors.centerIn: parent
        onVisibleChanged: if (visible) { unlockPass.text = ""; unlockPass.input.forceActiveFocus(); }
        ColumnLayout {
            id: unlockCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Tr.t("%1 is locked. Its password opens it.", (Files.unlockFor || {}).name || "")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
            }
            TextField { id: unlockPass; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Password"); onAccepted: Files.unlockDevice(text) }
            Text {
                visible: Files.unlockError !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Files.unlockError
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: Files.unlockFor = null }
                Button { kind: "primary"; text: Tr.t("Unlock"); busy: Files.busyDevice !== ""; enabled: unlockPass.text !== ""; onClicked: Files.unlockDevice(unlockPass.text) }
            }
        }
    }

    // ---- USB drives: a disk image written to one, or one formatted ------------------
    // Everything on the drive goes, so its name is typed before the button wakes up
    // (as with removing an account that has files). Only drives udisks calls
    // removable are offered; the computer's own disk never is.
    Glass {
        id: usbBox
        parent: win.contentItem
        visible: Files.usb !== null
        z: 32
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(480))
        height: usbCol.implicitHeight + 28
        anchors.centerIn: parent
        readonly property var u: Files.usb || ({})
        readonly property bool writing: u.mode === "write"
        property var drive: null
        property string fs: "exfat"
        property bool encrypt: false
        function reset() { drive = null; fs = "exfat"; encrypt = false; usbConfirm.text = ""; usbLabel.text = ""; usbPass.text = ""; usbPass2.text = ""; usbOldPw.text = ""; usbNewPw.text = ""; usbNewPw2.text = ""; }
        // each time it is asked for (also straight from one kind to the other)
        Connections { target: Files; function onUsbChanged() { if (Files.usb && Files.usb.loading) usbBox.reset(); } }
        readonly property bool passOk: !encrypt || writing || (usbPass.text !== "" && usbPass.text === usbPass2.text)
        readonly property bool confirmed: drive !== null && (u.mode === "backup" ? usbBackupTo.value !== ""
                                          : u.mode === "passphrase" ? (usbOldPw.text !== "" && usbNewPw.text !== "" && usbNewPw.text === usbNewPw2.text)
                                          : usbConfirm.text.trim() === drive.name && passOk)
        ColumnLayout {
            id: usbCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: usbBox.writing ? Tr.t("Write %1 to a USB drive", FilePaths.baseName(usbBox.u.image || ""))
                        : usbBox.u.mode === "backup" ? Tr.t("Copy a USB drive into an image file")
                        : usbBox.u.mode === "passphrase" ? Tr.t("Change a locked drive's password") : Tr.t("Format a USB drive")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Close"); enabled: !Files.usbBusy; onClicked: Files.usb = null }
            }
            // what to do with a drive (GNOME Disks' menu); Write when an image was chosen
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: (usbBox.u.image ? [["write", Tr.t("Write the image")]] : []).concat([["format", Tr.t("Format")], ["backup", Tr.t("Back up to an image")], ["passphrase", Tr.t("Change its password")]])
                    Choice { required property var modelData; text: modelData[1]; selected: usbBox.u.mode === modelData[0]; onClicked: Files.usbMode(modelData[0]) }
                }
                Choice { text: Tr.t("Drive health…"); onClicked: Files.driveHealth() }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                readonly property bool erases: usbBox.u.mode === "write" || usbBox.u.mode === "format"
                text: usbBox.u.loading ? Tr.t("Looking for USB drives…")
                    : !(usbBox.u.drives || []).length ? Tr.t("No USB drive or memory card is plugged in.")
                    : erases ? Tr.t("Everything on the drive you pick is erased.")
                    : usbBox.u.mode === "backup" ? Tr.t("The drive is read, not changed: every byte of it into one file, which can be written back later.")
                    : Tr.t("The drive keeps everything on it; only the password that opens it changes.")
                color: (usbBox.u.drives || []).length && erases ? Theme.danger : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: usbBox.u.drives || []
                    Choice {
                        required property var modelData
                        text: modelData.name + " · " + Files.humanSize(modelData.size)
                        selected: usbBox.drive !== null && usbBox.drive.block === modelData.block
                        onClicked: usbBox.drive = modelData
                    }
                }
            }
            // formatting: what to format it as, and an optional name
            Flow {
                visible: !usbBox.writing && usbBox.drive !== null
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [["exfat", Tr.t("exFAT · any computer, phone, TV")], ["vfat", Tr.t("FAT32 · older devices, files up to 4 GB")],
                            ["ntfs", Tr.t("NTFS · Windows")], ["ext4", Tr.t("ext4 · Linux")], ["btrfs", Tr.t("Btrfs · Linux, snapshots")],
                            ["f2fs", Tr.t("F2FS · Linux, kind to flash")], ["xfs", Tr.t("XFS · Linux, big files")],
                            ["udf", Tr.t("UDF · any computer, files over 4 GB")]]
                    Choice { required property var modelData; text: modelData[1]; selected: usbBox.fs === modelData[0]; onClicked: usbBox.fs = modelData[0] }
                }
            }
            TextField { id: usbLabel; visible: !usbBox.writing && usbBox.drive !== null; Layout.fillWidth: true; placeholderText: Tr.t("Name (optional)") }
            // LUKS2: asked for whenever it is plugged in (GNOME Disks' "Password protect")
            Choice {
                visible: !usbBox.writing && usbBox.drive !== null
                text: Tr.t("Lock it with a password")
                selected: usbBox.encrypt
                onClicked: usbBox.encrypt = !usbBox.encrypt
            }
            TextField { id: usbPass; visible: usbBox.encrypt && !usbBox.writing && usbBox.drive !== null; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Password") }
            TextField { id: usbPass2; visible: usbPass.visible; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("The password again") }
            // backing up: where the image goes
            FolderPicker { id: usbBackupTo; visible: usbBox.u.mode === "backup" && usbBox.drive !== null; Layout.fillWidth: true; label: Tr.t("Into"); value: Files.home }
            // a new password: the old one, the new one twice
            TextField { id: usbOldPw; visible: usbBox.u.mode === "passphrase" && usbBox.drive !== null; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Its password now") }
            TextField { id: usbNewPw; visible: usbOldPw.visible; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("The new password") }
            TextField { id: usbNewPw2; visible: usbOldPw.visible; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("The new password again") }
            TextField {
                id: usbConfirm
                visible: usbBox.drive !== null && (usbBox.u.mode === "write" || usbBox.u.mode === "format")
                Layout.fillWidth: true
                placeholderText: usbBox.drive ? Tr.t("Type %1 to erase it", usbBox.drive.name) : ""
            }
            // a write under way: how far
            Rectangle {
                visible: Files.usbBusy && Files.usbTotal > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(4)
                radius: Theme.px(2)
                color: Theme.alpha(Theme.text, 0.15)
                Accessible.role: Accessible.ProgressBar
                Accessible.name: Tr.t("Writing")
                Rectangle { width: parent.width * (Files.usbTotal > 0 ? Files.usbDone / Files.usbTotal : 0); height: parent.height; radius: parent.radius; color: Theme.accent }
            }
            Text {
                visible: Files.usbError !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Files.usbError
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { visible: Files.usbBusy && (usbBox.writing || usbBox.u.mode === "backup"); text: Tr.t("Stop"); onClicked: Files.usbStop() }
                Button {
                    busy: Files.usbBusy
                    enabled: usbBox.confirmed && !Files.usbBusy
                    kind: usbBox.u.mode === "backup" || usbBox.u.mode === "passphrase" ? "primary" : "danger"
                    text: usbBox.writing ? Tr.t("Write") : usbBox.u.mode === "backup" ? Tr.t("Back up") : usbBox.u.mode === "passphrase" ? Tr.t("Change it") : Tr.t("Format")
                    onClicked: {
                        if (!usbBox.confirmed) return;
                        if (usbBox.writing) Files.usbWrite(usbBox.drive);
                        else if (usbBox.u.mode === "backup") Files.usbBackup(usbBox.drive, usbBackupTo.value);
                        else if (usbBox.u.mode === "passphrase") Files.usbPassphrase(usbBox.drive, usbOldPw.text, usbNewPw.text);
                        else Files.usbFormat(usbBox.drive, usbBox.fs, usbLabel.text.trim(), usbBox.encrypt ? usbPass.text : "");
                    }
                }
            }
        }
    }

    // ---- a copy or a move under way: how far, and Stop ------------------------------
    Glass {
        id: jobBar
        objectName: "files-job"
        parent: win.contentItem
        visible: Files.jobRunning
        z: 29
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(460))
        height: jobCol.implicitHeight + 20
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.px(18)
        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(10)
            spacing: Theme.px(12)
            ColumnLayout {
                id: jobCol
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: (Files.jobPaused ? Tr.t("Paused") : Files.jobPhase === "verifying" ? Tr.t("Checking the copy")
                           : Files.jobMode === "hash" ? Tr.t("Making checksums") : Files.jobMode === "check" ? Tr.t("Testing checksums")
                           : Files.jobMode === "move" ? Tr.t("Moving") : Tr.t("Copying"))
                          + (Files.jobTotal > 0 ? " · " + Files.humanSize(Files.jobDone) + " / " + Files.humanSize(Files.jobTotal) : "")
                          + (Files.jobRate > 0 && !Files.jobPaused ? " · " + Files.humanSize(Files.jobRate) + "/s" : "")
                          + (Files.jobSecondsLeft > 0 && !Files.jobPaused ? " · " + (Files.jobSecondsLeft >= 3600 ? Tr.t("%1 h %2 min left", Math.floor(Files.jobSecondsLeft / 3600), Math.round(Files.jobSecondsLeft % 3600 / 60))
                                                                                   : Files.jobSecondsLeft >= 60 ? Tr.t("%1 min left", Math.round(Files.jobSecondsLeft / 60)) : Tr.t("%1 s left", Math.ceil(Files.jobSecondsLeft))) : "")
                          + (Files.jobsWaiting > 0 ? " · " + Tr.t("%1 more waiting", Files.jobsWaiting) : "")
                          + (Files.jobFile ? " · " + Files.jobFile : "")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(4)
                    radius: Theme.px(2)
                    color: Theme.alpha(Theme.text, 0.15)
                    Accessible.role: Accessible.ProgressBar
                    Accessible.name: Tr.t("Copy progress")
                    Rectangle { width: parent.width * Files.jobFraction; height: parent.height; radius: parent.radius; color: Theme.accent }
                }
            }
            // when everything queued is done (TeraCopy's "Shut down when finished")
            Choice {
                text: Files.whenDone === "suspend" ? Tr.t("Then sleep") : Files.whenDone === "poweroff" ? Tr.t("Then shut down") : Tr.t("Then: nothing")
                selected: Files.whenDone !== ""
                onClicked: Files.whenDone = Files.whenDone === "" ? "suspend" : Files.whenDone === "suspend" ? "poweroff" : ""
            }
            Button { text: Files.jobPaused ? Tr.t("Resume") : Tr.t("Pause"); flat: true; onClicked: Files.pauseJob() }
            Button { text: Tr.t("Stop"); flat: true; onClicked: Files.cancelJob() }
        }
    }

    // ---- what was just done, with Undo -------------------------------------------------
    Glass {
        id: noteBar
        parent: win.contentItem
        visible: Files.note !== "" && !Files.props && !Files.jobRunning
        z: 28
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, noteRow.implicitWidth + 28)
        height: noteRow.implicitHeight + 18
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.px(18)
        RowLayout {
            id: noteRow
            anchors.centerIn: parent
            spacing: Theme.px(12)
            Text { text: Files.note; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
            Button { visible: Files.undoLabel !== "" && Files.note === Files.undoLabel; flat: true; text: Tr.t("Undo"); onClicked: Files.undo() }
        }
        Timer { id: noteTimer; running: noteBar.visible; interval: 7000; onTriggered: Files.note = "" }
        Connections { target: Files; function onNoteChanged() { noteTimer.restart(); } }
    }

    // ---- the pieces that need the window ------------------------------------------
    property var menuEntry: null
    property string typed: ""                // type to find: what was typed so far
    Timer { id: typedTimer; interval: 1000; onTriggered: win.typed = "" }
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
        if (e.background) {
            items.push({ label: Tr.t("New folder"), icon: "folder-new", danger: false, run: () => win.openNewFolder() });
            for (const tpl of Files.templates)
                items.push({ label: Tr.t("New %1", tpl.name), icon: "document-new", danger: false, run: () => Files.newFromTemplate(tpl, e.path) });
            items.push({ label: Tr.t("Paste"), icon: "edit-paste", danger: false, run: () => Files.pasteHere(e.path) });
            items.push({ label: Tr.t("Open in terminal"), icon: "utilities-terminal", danger: false, run: () => Files.openTerminal(e.path) });
            items.push({ label: Tr.t("New encrypted folder…"), icon: "folder-locked", danger: false, run: () => Files.askLock("vault-new", e.path) });
            items.push({ label: Tr.t("Copy history"), icon: "document-open-recent", danger: false, run: () => { Files.loadCopyHistory(); Files.historyShown = true; } });
            if (e.path.startsWith("/"))
                items.push({ label: Tr.t("Open from your phone…"), icon: "phone", danger: false, run: () => win.serveAsk = e.path });
            if (e.path.startsWith("/") && !Files.asAdmin)
                items.push({ label: Tr.t("Open as administrator"), icon: "security-high", danger: false, run: () => Files.openAsAdmin(e.path, true) });
            items.push({ label: Tr.t("Select all"), icon: "edit-select-all", danger: false, run: () => Files.selectAll() });
            items.push({ label: Tr.t("Turn the selection over"), icon: "edit-select-invert", danger: false, run: () => Files.invertSelection() });
            items.push({ label: Tr.t("Properties"), icon: "document-properties", danger: false, run: () => Files.showProps([e.path]) });
            return items;
        }
        const chosen = Files.selected.indexOf(e.path) >= 0 ? Files.selected.slice() : [e.path];
        // in the trash: put back where it came from, or delete for good (asked twice)
        if (Files.isTrash) {
            const from = (Files.trashItems[Files.trashNameOf(e.path)] || {}).original || "";
            items.push({ label: from ? Tr.t("Put back in %1", FilePaths.baseName(FilePaths.parentOf(from)) || "/") : Tr.t("Put back"),
                         icon: "edit-undo", danger: false, run: () => Files.putBack(chosen) });
            items.push({ label: win.confirmDelete === e.path ? Tr.t("Click again: gone for good") : Tr.t("Delete for good"), icon: "edit-delete", danger: true,
                         keep: win.confirmDelete !== e.path,
                         run: () => { if (win.confirmDelete !== e.path) { win.confirmDelete = e.path; confirmTimer.restart(); return; } win.confirmDelete = ""; Files.deleteForGood(chosen); } });
            return items;
        }
        if (e.isDir)
            items.push({ label: Tr.t("Open"), icon: "folder-open", danger: false, run: () => Files.open(e.path) });
        else
            items.push({ label: Tr.t("Open"), icon: "document-open", danger: false, run: () => Files.openEntry(e.path) });
        items.push({ label: Tr.t("Open with…"), icon: "view-app-grid", danger: false, run: () => { win.openWithPaths = chosen.slice(); } });
        items.push({ label: Tr.t("Rename"), icon: "document-edit", danger: false, run: () => beginRename(e.path) });
        if (!e.isDir)
            items.push({ label: Tr.t("Suggest a name"), icon: "tools-check-spelling", danger: false,
                         run: () => { Files.select(e.path, "single"); win.suggesting = true; beginRename(e.path); Tidy.suggestName(e.path); } });
        items.push({ label: Tr.t("Copy"), icon: "edit-copy", danger: false, run: () => Files.toClipboard("copy", chosen) });
        items.push({ label: Tr.t("Cut"), icon: "edit-cut", danger: false, run: () => Files.toClipboard("cut", chosen) });
        if (e.isDir)
            items.push({ label: Tr.t("Paste into this folder"), icon: "edit-paste", danger: false, run: () => Files.pasteHere(e.path) });
        // a password: on a PDF (a PDF password), any other file or folder (gpg)
        if (Files.isGpg(e.path) || /\.(pdf|zip)$/i.test(e.path))
            items.push({ label: Tr.t("Unlock…"), icon: "changes-allow", danger: false, run: () => Files.askLock("unlock", e.path) });
        if (!Files.isGpg(e.path))
            items.push({ label: Tr.t("Lock with a password…"), icon: "changes-prevent", danger: false, run: () => Files.askLock("lock", e.path) });
        if (!e.isDir && Files.mountableImage(e.path))
            items.push({ label: Tr.t("Open as a drive"), icon: "media-optical", danger: false, run: () => Files.mountImage(e.path) });
        if (!e.isDir && Files.diskImage(e.path))
            items.push({ label: Tr.t("Write to a USB drive…"), icon: "drive-removable-media", danger: false, run: () => Files.openUsb("write", e.path) });
        for (const s of Files.scripts)
            items.push({ label: Tr.t("Script: %1", s.name), icon: "system-run", danger: false, run: () => Files.runScript(s, chosen) });
        items.push({ label: Tr.t("Copy to…"), icon: "edit-copy", danger: false, run: () => Files.copyTo = { mode: "copy", paths: chosen } });
        items.push({ label: Tr.t("Move to…"), icon: "go-jump", danger: false, run: () => Files.copyTo = { mode: "move", paths: chosen } });
        if (Files.isChecksumFile(e.path))
            items.push({ label: Tr.t("Test the checksums"), icon: "security-high", danger: false, run: () => Files.checkChecksums(e.path) });
        else
            items.push({ label: Tr.t("Make checksums (.sha256)"), icon: "security-high", danger: false, run: () => Files.makeChecksums(chosen) });
        if (chosen.length === 2)
            items.push({ label: Tr.t("Compare"), icon: "view-split-left-right", danger: false, run: () => Files.compare(chosen[0], chosen[1]) });
        if (chosen.length > 1)
            items.push({ label: Tr.t("Rename %1…", chosen.length), icon: "document-edit", danger: false, run: () => win.beginBatchRename(chosen) });
        if (e.isDir)
            items.push({ label: Tr.t("Open from your phone…"), icon: "phone", danger: false, run: () => win.serveAsk = e.path });
        if (e.path.startsWith("/") && !Files.asAdmin)
            items.push({ label: Tr.t("Open as administrator"), icon: "security-high", danger: false, run: () => Files.openAsAdmin(e.path, e.isDir) });
        if (e.isDir && e.path.startsWith(Files.home + "/"))
            items.push(Files.isShared(e.path)
                       ? { label: Tr.t("Stop sharing on the network"), icon: "folder-publicshare", danger: false, run: () => Files.setShared(e.path, false) }
                       : { label: Tr.t("Share on the network"), icon: "folder-publicshare", danger: false, run: () => Files.setShared(e.path, true) });
        if (e.isDir)
            items.push(Files.isBookmarked(e.path)
                       ? { label: Tr.t("Remove from the sidebar"), icon: "user-bookmarks", danger: false, run: () => Files.setBookmark(e.path, false) }
                       : { label: Tr.t("Add to the sidebar"), icon: "user-bookmarks", danger: false, run: () => Files.setBookmark(e.path, true) });
        items.push({ label: Tr.t("Properties"), icon: "document-properties", danger: false, run: () => Files.showProps(chosen) });
        items.push({ label: Tr.t("Duplicate"), icon: "edit-copy", danger: false, run: () => Files.duplicateEntry(e.path) });
        items.push({ label: Tr.t("Copy path"), icon: "edit-copy", danger: false, run: () => Files.copyPath(e.path) });
        items.push(Files.isStarred(e.path)
            ? { label: Tr.t("Unstar"), icon: "non-starred", danger: false, run: () => Files.setStar(chosen, false) }
            : { label: Tr.t("Star"), icon: "starred", danger: false, run: () => Files.setStar(chosen, true) });
        if (e.isDir)
            items.push({ label: Tr.t("Open in terminal"), icon: "utilities-terminal", danger: false, run: () => Files.openTerminal(e.path) });
        if (e.image)
            items.push({ label: Tr.t("Set as wallpaper"), icon: "preferences-desktop-wallpaper", danger: false, run: () => Files.setWallpaper(e.path) });
        items.push({ label: Tr.t("Share…"), icon: "folder-publicshare", danger: false, run: () => Share.open(e.path) });
        // the chosen files when this one is among them, else this one
        items.push({ label: Tr.t("Compress…"), icon: "package-x-generic", danger: false,
                     run: () => Archive.createAsk(Files.selected.indexOf(e.path) >= 0 ? Files.selected : [e.path]) });
        if (!e.isDir && Archive.types.indexOf((e.name.split(".").pop() || "").toLowerCase()) >= 0)
            items.push({ label: Tr.t("Extract here"), icon: "archive-extract", danger: false, run: () => Archive.extractHere(e.path) });
        items.push({ label: Tr.t("Move to trash"), icon: "edit-delete", danger: true, run: () => Files.trashEntries([e.path]) });
        items.push({ label: Tr.t("Delete for good…"), icon: "edit-delete", danger: true, run: () => Files.deleteAsk = chosen });
        return items;
    }

    // two clicks for what has no undo; the first arms it for a few seconds
    property bool confirmEmpty: false
    property string confirmDelete: ""
    Timer { id: confirmTimer; interval: 4000; onTriggered: { win.confirmEmpty = false; win.confirmDelete = ""; } }

    property var batchPaths: []
    function beginBatchRename(paths) {
        win.batchPaths = paths;
        batchField.text = Tr.t("Name") + " #";
        batchBox.visible = true;
        batchField.forceActiveFocus();
        batchField.selectAll();
    }
    // what "Holiday #" makes of the chosen files, as files.py batch-rename will
    function batchPreview(pattern) {
        const w = String(win.batchPaths.length).length;
        return win.batchPaths.slice(0, 3).map((p, i) => {
            const base = FilePaths.baseName(p), dot = base.lastIndexOf(".");
            const num = String(i + 1).padStart(w, "0");
            return (pattern.indexOf("#") >= 0 ? pattern.split("#").join(num) : pattern + " " + num).trim() + (dot > 0 ? base.slice(dot) : "");
        });
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