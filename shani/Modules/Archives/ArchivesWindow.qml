// Archives: look inside a zip, tar, 7z or ISO, and take it out - into a new
// folder beside it (nothing is written over), or into a folder you choose.
// Services/Archive reads and extracts with libarchive's bsdtar.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/FilesReveal.js" as FilesReveal

AppWindow {
    id: win
    appName: "Archive Manager"
    doc: Archive.name
    visible: Archive.shown
    onGone: Archive.close()
    implicitWidth: Theme.px(720)
    implicitHeight: Theme.px(620)

    // A password you mistype locks you out of your own archive for good, so
    // make it be entered twice and have a floor before Create is even enabled.
    readonly property bool passVisible: Archive.format === "zip" || Archive.format === "7z"
    readonly property bool passOk: !win.passVisible || archPass.text === ""
        || (archPass.text.length >= 4 && archPass.text === archPassConfirm.text)
    readonly property string passHint: !win.passVisible || archPass.text === "" ? ""
        : archPass.text.length < 4 ? Tr.t("Password must be at least 4 characters")
        : archPass.text !== archPassConfirm.text ? Tr.t("Passwords do not match") : ""

    // File Roller and Ark keep the contents searchable and let a long job be
    // stopped: a large archive is useless if you must scroll it by eye, and a
    // mistaken "Extract" should not have to mean closing the window.
    property string entryFilter: ""
    // Search first, then browse: a filter and a folder both narrow the list, so
    // the two compose instead of one replacing the other.
    readonly property var matchedEntries: {
        const q = win.entryFilter.trim().toLowerCase();
        if (q === "") return Archive.entries;
        return Archive.entries.filter(e => e.path.toLowerCase().indexOf(q) >= 0);
    }
    readonly property var visibleEntries: Archive.entriesHere(win.matchedEntries)
    // synthetic folders are for browsing only: never select or extract them
    readonly property var visiblePaths: win.visibleEntries.filter(e => !e.virtual).map(e => e.path)
    readonly property bool busy: Archive.reading || Archive.extracting || Archive.creating || Archive.appending || Archive.probeThenExtract
    readonly property bool working: win.busy || Archive.testing
    readonly property bool canGoUp: Archive.currentDir !== ""
    property int cursor: 0
    readonly property var currentEntry: win.visibleEntries.length
        ? win.visibleEntries[Math.min(win.cursor, win.visibleEntries.length - 1)] : null

    function clearPass() { Archive.newPass = ""; archPassConfirm.text = ""; }
    function clearPrompt() { pw.text = ""; }
    // jump from the archive to its folder in Files, with the file chosen
    function reveal(path) { return FilesReveal.show(path, Files); }
    function openRecent(path) { win.clearPrompt(); Archive.open(path); }
    function runTest() { Archive.testArchive(); }

    // A dropped archive opens; dropped files are added to the open archive.
    // file:// URLs are decoded, so a name with spaces works.
    function dropPaths(drop) {
        const out = [];
        if (!drop || !drop.urls) return out;
        for (const u of drop.urls) {
            const s = String(u);
            if (s.indexOf("file://") === 0) out.push(decodeURIComponent(s.substring(7)));
            else if (s.indexOf("/") === 0) out.push(s);
        }
        return out;
    }
    function handleDrop(drop) {
        const paths = win.dropPaths(drop);
        if (!paths.length) return;
        const archives = paths.filter(p => Archive.types.some(ext => p.toLowerCase().endsWith("." + ext)));
        if (archives.length) { win.openRecent(archives[0]); return; }
        if (Archive.file !== "" && Archive.canAppend) Archive.append(paths);
    }

    function moveCursor(delta) {
        if (!win.visibleEntries.length) return;
        win.cursor = Math.max(0, Math.min(win.visibleEntries.length - 1, win.cursor + delta));
        list.currentIndex = win.cursor;
        list.positionViewAtIndex(win.cursor, ListView.Contain);
    }

    function selectAllVisible() { Archive.selectAll(win.visiblePaths); }
    function extractSelectedTo() {
        if (!Archive.selection.length || win.busy) return;
        FilePicker.open({ mode: "folder", title: Tr.t("Extract into"),
                          startPath: Archive.file.substring(0, Archive.file.lastIndexOf("/")),
                          onPicked: paths => { if (paths.length) Archive.extractSelected(Archive.selection, paths[0]); } });
    }

    function pick() {
        FilePicker.open({ mode: "open", title: Tr.t("Open an archive"), filters: Archive.types,
                          startPath: Archive.file !== "" ? Archive.file.substring(0, Archive.file.lastIndexOf("/")) : (Quickshell.env("HOME") + "/Downloads"),
                          onPicked: paths => { if (paths.length) { win.clearPrompt(); Archive.open(paths[0]); } } });
    }
    function extractTo() {
        FilePicker.open({ mode: "folder", title: Tr.t("Extract into"),
                          startPath: Archive.file.substring(0, Archive.file.lastIndexOf("/")),
                          onPicked: paths => { if (paths.length) Archive.extract(paths[0]); } });
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_O) { win.pick(); e.accepted = true; }
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_L) { win.reveal(Archive.file); e.accepted = true; }
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_E) { Archive.extract(""); e.accepted = true; }
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_A) { win.selectAllVisible(); e.accepted = true; }
            else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_T) { win.runTest(); e.accepted = true; }
            else if (e.key === Qt.Key_Up) { win.moveCursor(-1); e.accepted = true; }
            else if (e.key === Qt.Key_Down) { win.moveCursor(1); e.accepted = true; }
            else if (e.key === Qt.Key_Home) { win.cursor = 0; list.currentIndex = 0; e.accepted = true; }
            else if (e.key === Qt.Key_End) { win.cursor = win.visibleEntries.length - 1; list.currentIndex = win.cursor; e.accepted = true; }
            else if (e.key === Qt.Key_Return && win.currentEntry && !win.currentEntry.virtual) {
                Archive.extractOne(win.currentEntry.path); e.accepted = true;
            }
            else if (e.key === Qt.Key_Escape && Archive.selection.length) { Archive.clearSelection(); e.accepted = true; }
            else if (e.key === Qt.Key_Escape) { Archive.close(); e.accepted = true; }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(10)

            // the file actions wrap below the name on a narrow window
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Icon { name: "package-x-generic"; size: Theme.px(22); color: Theme.accent }
                Icon {
                    visible: Archive.wasProtected
                    name: "dialog-password"
                    size: Theme.px(16)
                    color: Theme.accent
                    Accessible.name: Tr.t("Locked")
                }
                ColumnLayout {
                    width: Math.max(Theme.px(160), parent.width - Theme.px(280))
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: Archive.file !== "" ? Archive.name : Tr.t("Archive Manager")
                        color: Theme.text
                        elide: Text.ElideMiddle
                        font.family: Theme.font
                        font.pixelSize: Theme.type("heading")
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: Archive.file !== ""
                        text: Archive.reading ? Tr.t("Reading…")
                            : Archive.entries.length + " " + Tr.t("items") + "  ·  " + Archive.human(Archive.totalSize) + " " + Tr.t("when extracted")
                              + (Archive.selection.length ? "  ·  " + Tr.t("%1 selected").arg(Archive.selection.length) : "")
                              + (Archive.modified ? "  ·  " + Tr.t("Changed this session") : "")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.type("small")
                    }
                }
                Button {
                    visible: Archive.modified
                    text: Tr.t("Reload")
                    flat: true
                    onClicked: Archive.open(Archive.file)
                }
                Button { text: Tr.t("Open…"); flat: true; onClicked: win.pick() }
                Button { visible: Archive.file !== ""; text: Tr.t("Show in Files"); flat: true; onClicked: win.reveal(Archive.file) }
                Button {
                    text: Tr.t("Add files…")
                    flat: true
                    visible: Archive.file !== ""
                    enabled: Archive.canAppend && !Archive.appending
                    onClicked: FilePicker.open({
                        mode: "open", multiple: true,
                        title: Tr.t("Add to the archive"),
                        startPath: Archive.file.substring(0, Archive.file.lastIndexOf("/")),
                        onPicked: paths => Archive.append(paths),
                    })
                }
            }

            // ---- Recently opened archives (File Roller / Ark) ----------------
            Flow {
                Layout.fillWidth: true
                visible: Archive.file === "" && Archive.toCompress.length === 0 && Archive.recent.length > 0
                spacing: Theme.px(8)
                Text {
                    height: Math.max(Theme.px(24), Theme.touchTarget)
                    verticalAlignment: Text.AlignVCenter
                    text: Tr.t("Recent files")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
                Repeater {
                    model: Archive.recent
                    Button {
                        required property var modelData
                        text: modelData.split("/").pop()
                        flat: true
                        Accessible.name: modelData
                        onClicked: win.openRecent(modelData)
                    }
                }
                Button {
                    text: Tr.t("Clear")
                    flat: true
                    Accessible.name: Tr.t("Clear the recent files list")
                    onClicked: Archive.clearRecent()
                }
            }

            // ---- Compress (Files' right-click): the chosen files into one archive ----
            ColumnLayout {
                Layout.fillWidth: true
                visible: Archive.toCompress.length > 0
                spacing: Theme.px(8)
                Text {
                    Layout.fillWidth: true
                    text: Archive.toCompress.length === 1
                        ? Tr.t("Compress “%1”", Archive.toCompress[0].split("/").pop())
                        : Tr.t("Compress %1 items", Archive.toCompress.length)
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.type("body")
                    font.weight: Font.DemiBold
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: Archive.formats
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: Archive.format === modelData.ext
                            onClicked: {
                                Archive.format = modelData.ext;
                                // a tar cannot carry a password: drop a stale one
                                // instead of letting Create refuse it later
                                if (!win.passVisible) win.clearPass();
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: win.passVisible
                    spacing: Theme.px(8)
                    Text { text: Tr.t("Password"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                    TextField {
                        id: archPass
                        Layout.fillWidth: true
                        secret: true
                        placeholder: Tr.t("at least 4 characters, or empty for none")
                        text: Archive.newPass
                        onTextChanged: Archive.newPass = text
                    }
                    TextField {
                        id: archPassConfirm
                        Layout.fillWidth: true
                        secret: true
                        placeholder: Tr.t("Confirm password")
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: win.passHint !== ""
                    text: win.passHint
                    color: Theme.danger
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
                // a failed Compress leaves entries empty, so the result row at
                // the bottom cannot show it — say it here, where Create lives
                Text {
                    Layout.fillWidth: true
                    visible: Archive.error !== ""
                    text: Archive.error
                    color: Theme.danger
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    TextField {
                        id: archName
                        Layout.fillWidth: true
                        placeholder: Tr.t("Name (optional) — otherwise “%1”", Archive.defaultName(Archive.toCompress))
                    }
                    Button {
                        kind: "primary"
                        enabled: !Archive.creating && win.passOk
                        text: Archive.creating ? Tr.t("Compressing…") : Tr.t("Create")
                        onClicked: {
                            Archive.create(Archive.toCompress, Archive.format, archName.text.trim());
                            win.clearPass();  // never leave a secret in the UI or in Archive.newPass
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: Archive.made !== ""
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("Made") + " " + Archive.made.split("/").pop()
                        color: Theme.dim
                        elide: Text.ElideMiddle
                        font.family: Theme.font
                        font.pixelSize: Theme.type("small")
                    }
                    Button { text: Tr.t("Show in Files"); onClicked: win.reveal(Archive.made) }
                    Button { text: Tr.t("Open it"); flat: true; onClicked: { const m = Archive.made; Archive.toCompress = []; Archive.open(m); } }
                }
            }

            // ---- what is inside ----
            // Ark-style folder navigation and sort: the list is the current
            // directory, not the whole archive, with a synthetic folder per
            // subdirectory so archives without dir entries still navigate.
            Flow {
                Layout.fillWidth: true
                visible: Archive.entries.length > 0
                spacing: Theme.px(8)
                Button {
                    text: Tr.t("Up")
                    flat: true
                    enabled: win.canGoUp
                    Accessible.name: Tr.t("Up")
                    onClicked: { Archive.up(); win.cursor = 0; list.currentIndex = 0; }
                }
                Text {
                    width: Math.max(Theme.px(120), Math.min(Theme.px(280), parent.width - Theme.px(240)))
                    height: Math.max(Theme.px(24), Theme.touchTarget)
                    verticalAlignment: Text.AlignVCenter
                    text: Archive.currentDir === "" ? Archive.name : Archive.name + "/" + Archive.currentDir
                    color: Theme.dim
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                    Accessible.name: text
                }
                Text {
                    text: Tr.t("Sort:")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
                Choice {
                    text: Tr.t("Name")
                    selected: Archive.sortOrder === "name"
                    onClicked: Archive.setSortOrder("name")
                }
                Choice {
                    text: Tr.t("Size")
                    selected: Archive.sortOrder === "size"
                    onClicked: Archive.setSortOrder("size")
                }
            }
            Flow {
                Layout.fillWidth: true
                visible: Archive.entries.length > 0
                spacing: Theme.px(8)
                Text {
                    height: Math.max(Theme.px(24), Theme.touchTarget)
                    verticalAlignment: Text.AlignVCenter
                    text: Tr.t("Extract into")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
                Choice {
                    text: Tr.t("Rename")
                    selected: Archive.overwritePolicy === "rename"
                    Accessible.name: Tr.t("Rename")
                    onClicked: Archive.setOverwritePolicy("rename")
                }
                Choice {
                    text: Tr.t("Replace")
                    selected: Archive.overwritePolicy === "overwrite"
                    Accessible.name: Tr.t("Replace")
                    onClicked: Archive.setOverwritePolicy("overwrite")
                }
                Choice {
                    text: Tr.t("Skip")
                    selected: Archive.overwritePolicy === "skip"
                    Accessible.name: Tr.t("Skip")
                    onClicked: Archive.setOverwritePolicy("skip")
                }
                Button {
                    text: Tr.t("Test")
                    flat: true
                    enabled: !win.working
                    Accessible.name: Tr.t("Test")
                    onClicked: win.runTest()
                }
                Text {
                    width: Math.max(Theme.px(120), Math.min(Theme.px(280), parent.width - Theme.px(300)))
                    height: Math.max(Theme.px(24), Theme.touchTarget)
                    verticalAlignment: Text.AlignVCenter
                    visible: Archive.testing || Archive.testResult !== ""
                    text: Archive.testing ? Tr.t("Working…") : Archive.testResult
                    color: Theme.dim
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
            }
            Flow {
                Layout.fillWidth: true
                visible: Archive.entries.length > 0
                spacing: Theme.px(8)
                TextField {
                    id: entrySearch
                    width: Math.max(Theme.px(140), Math.min(Theme.px(280), parent.width - Theme.px(200)))
                    placeholderText: Tr.t("Find a file in the archive")
                    label: Tr.t("Find a file in the archive")
                    text: win.entryFilter
                    onTextChanged: win.entryFilter = text
                }
                Text {
                    text: win.visibleEntries.length + " / " + Archive.entries.length + " " + Tr.t("items")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                    font.features: { "tnum": 1 }
                }
                IconButton {
                    icon: "edit-select-all"
                    size: Theme.px(24)
                    tip: Tr.t("Select all")
                    enabled: win.visibleEntries.length > 0 && !win.busy
                    onClicked: win.selectAllVisible()
                }
                IconButton {
                    icon: "edit-clear-all"
                    size: Theme.px(24)
                    visible: Archive.selection.length > 0
                    tip: Tr.t("Clear")
                    onClicked: Archive.clearSelection()
                }
                Button {
                    text: Tr.t("%1 selected").arg(Archive.selection.length) + " · " + Tr.t("Extract into")
                    enabled: Archive.selection.length > 0 && !win.busy
                    onClicked: win.extractSelectedTo()
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.border
                clip: true
                ListView {
                    reuseItems: true
                    cacheBuffer: 400
                    id: list
                    anchors.fill: parent
                    anchors.margins: Theme.px(6)
                    clip: true
                    spacing: 1
                    boundsBehavior: Flickable.StopAtBounds
                    model: win.visibleEntries
                    highlight: Rectangle { color: Theme.alpha(Theme.accent, 0.08); radius: Theme.radiusSmall }
                    delegate: Item {
                        id: row
                        required property var modelData
                        readonly property int depth: modelData.path.split("/").length - 1
                        readonly property bool chosen: Archive.isSelected(row.modelData.path)
                        width: list.width
                        height: Math.max(Theme.px(26), Theme.touchTarget)
                        Accessible.role: Accessible.ListItem
                        Accessible.name: row.modelData.path
                        KeyFocus {
                            name: row.modelData.path
                            onActivated: Archive.selectEntry(row.modelData.path, "toggle", win.visiblePaths)
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusSmall
                            color: row.chosen ? Theme.alpha(Theme.accent, 0.14)
                                : (rowArea.containsMouse ? Theme.hover : "transparent")
                        }
                        // below the controls: a click on the checkbox or the
                        // extract button is theirs, a click elsewhere is ours
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                list.currentIndex = index;
                                win.cursor = index;
                                const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                Archive.selectEntry(row.modelData.path, shift ? "range" : (ctrl ? "toggle" : "single"), win.visiblePaths);
                            }
                            onDoubleClicked: {
                                if (!row.modelData.dir) return;
                                Archive.browse(row.modelData.path);
                                win.cursor = 0;
                                list.currentIndex = 0;
                            }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.px(3)
                            spacing: Theme.px(8)
                            Choice {
                                visible: !row.modelData.virtual
                                selected: row.chosen
                                text: row.chosen ? "✓" : ""
                                implicitWidth: Math.max(Theme.px(16), Theme.touchTarget)
                                implicitHeight: implicitWidth
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: row.modelData.path
                                onClicked: Archive.selectEntry(row.modelData.path, "toggle", win.visiblePaths)
                            }
                            Item { implicitWidth: row.depth * 14; implicitHeight: 1 }
                            Icon { name: row.modelData.dir ? "folder" : "text-x-generic"; size: Theme.px(16); color: row.modelData.dir ? Theme.accent : Theme.dim }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.path.split("/").pop()
                                color: Theme.text
                                elide: Text.ElideMiddle
                                font.family: Theme.font
                                font.pixelSize: Theme.type("body")
                                Accessible.name: row.modelData.path
                            }
                            Text {
                                text: row.modelData.dir ? "" : Archive.human(row.modelData.size)
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: Theme.type("small")
                                font.features: { "tnum": 1 }
                            }
                            // just this one, beside the archive
                            IconButton {
                                visible: !row.modelData.virtual
                                size: Theme.px(24)
                                icon: "document-save"
                                tip: Tr.t("Extract only this")
                                enabled: !Archive.extracting
                                Accessible.name: Tr.t("Extract only this") + " " + row.modelData.path
                                onClicked: Archive.extractOne(row.modelData.path)
                            }
                        }
                    }
                }
                // Dropping an archive opens it; dropping files adds them to the
                // open archive (same guard as the Add files button).
                DropArea {
                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    onDropped: drop => win.handleDrop(drop)
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: (Archive.entries.length === 0 || win.visibleEntries.length === 0) && !Archive.reading
                    icon: "package-x-generic"
                    title: Archive.error !== "" ? Archive.error
                        : !Archive.available ? Tr.t("bsdtar (libarchive) is not installed")
                        : Archive.entries.length === 0 ? Tr.t("No archive open")
                        : Tr.t("Nothing matches")
                    subtitle: Archive.error !== "" || !Archive.available
                        ? "" : Archive.entries.length === 0 ? Tr.t("Open an archive")
                        : Tr.t("Clear the filter to see every item")
                }
                // the empty state is actionable: open one, retry a failed open,
                // or clear a filter that hid every entry
                Flow {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.px(8)
                    width: Math.min(parent.width - Theme.px(16), Theme.px(400))
                    visible: Archive.entries.length === 0 && !Archive.reading && !win.working
                    spacing: Theme.px(8)
                    Button {
                        visible: Archive.file === "" && Archive.toCompress.length === 0
                        text: Tr.t("Open an archive")
                        onClicked: win.pick()
                    }
                    Button {
                        visible: Archive.error !== "" && Archive.file !== ""
                        text: Tr.t("Reload")
                        flat: true
                        onClicked: Archive.open(Archive.file)
                    }
                    Button {
                        visible: Archive.entries.length > 0 && win.visibleEntries.length === 0
                        text: Tr.t("Clear")
                        flat: true
                        onClicked: { win.entryFilter = ""; Archive.browse(""); }
                    }
                }
            }

            // ---- a password, when the archive has one ----
            RowLayout {
                Layout.fillWidth: true
                visible: Archive.needsPassword
                spacing: Theme.px(8)
                Icon { name: "dialog-password"; size: Theme.px(20); color: Theme.accent }
                TextField {
                    id: pw
                    Layout.fillWidth: true
                    placeholder: Archive.error !== "" ? Archive.error + " — " + Tr.t("try again") : Tr.t("This archive has a password")
                    secret: true
                    onAccepted: if (text !== "") { Archive.unlock(text); text = ""; }
                }
                Button { kind: "primary"; text: Tr.t("Unlock"); onClicked: if (pw.text !== "") { Archive.unlock(pw.text); pw.text = ""; } }
            }
            Connections { target: Archive; function onNeedsPasswordChanged() { if (Archive.needsPassword) pw.forceActiveFocus(); else win.clearPrompt(); } }

            // ---- what happened ----
            RowLayout {
                Layout.fillWidth: true
                visible: Archive.extractedTo !== "" || (Archive.error !== "" && Archive.entries.length > 0)
                spacing: Theme.px(8)
                Text {
                    Layout.fillWidth: true
                    text: Archive.error !== "" ? Archive.error : Tr.t("Extracted to") + " " + Archive.extractedTo
                    color: Archive.error !== "" ? Theme.danger : Theme.dim
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
                Button {
                    visible: Archive.extractedTo !== ""
                    text: Tr.t("Show the folder")
                    onClicked: Files.show(Archive.extractedTo)
                }
            }
            // one result for the whole batch: a failed entry is listed but the
            // ones that came out are not undone, and the folder is still there
            InfoBanner {
                Layout.fillWidth: true
                visible: Archive.batchSummary !== ""
                tone: Archive.batchFailed.length ? "warn" : "ok"
                iconName: Archive.batchFailed.length ? "dialog-warning" : "dialog-ok"
                title: Tr.t("Batch")
                text: Archive.batchSummary + (Archive.batchFailed.length ? "\n" + Archive.error : "")
                Button {
                    visible: Archive.extractedTo !== ""
                    text: Tr.t("Show the folder")
                    onClicked: Files.show(Archive.extractedTo)
                }
                Button {
                    text: Tr.t("Dismiss")
                    flat: true
                    onClicked: { Archive.batchSummary = ""; Archive.batchDone = []; Archive.batchFailed = []; Archive.error = ""; }
                }
            }

            // an indeterminate progress state: the jobs report no byte counts,
            // so show that work is in flight and let Cancel stop it
            RowLayout {
                Layout.fillWidth: true
                visible: win.working
                spacing: Theme.px(8)
                Text {
                    text: Archive.reading ? Tr.t("Reading…")
                        : Archive.extracting ? Tr.t("Extracting…")
                        : Archive.testing ? Tr.t("Working…") : Tr.t("Working…")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                    Accessible.name: text
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: Theme.px(4)
                    radius: Theme.radiusSmall
                    color: Theme.border
                    clip: true
                    Rectangle {
                        id: progressBar
                        width: parent.width * 0.35
                        height: parent.height
                        color: Theme.accent
                        NumberAnimation on x {
                            from: -progressBar.width; to: progressBar.parent.width
                            duration: 1200; loops: Animation.Infinite
                        }
                    }
                }
                Button {
                    visible: Archive.testing
                    text: Tr.t("Cancel")
                    flat: true
                    onClicked: Archive.cancel()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button {
                    Layout.fillWidth: true
                    kind: "primary"
                    enabled: Archive.entries.length > 0 && !Archive.extracting
                    text: Archive.extracting ? Tr.t("Extracting…") : Tr.t("Extract here")
                    onClicked: Archive.extract("")
                }
                Button {
                    Layout.fillWidth: true
                    enabled: Archive.entries.length > 0 && !Archive.extracting
                    text: Tr.t("Extract to…")
                    onClicked: win.extractTo()
                }
                Button {
                    visible: win.busy
                    text: Tr.t("Cancel")
                    onClicked: Archive.cancel()
                }
            }
        }
    }
}
