// The font browser: what fonts are installed (fc-list), each shown as its
// own type; typing previews your words at the chosen size; clicking a row
// copies its family name to the clipboard (for Settings > Personalisation,
// or a document). A font file can be installed from disk into
// ~/.local/share/fonts, and the fontconfig cache is refreshed after.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Fonts"
    visible: Ui.fonts
    onGone: Ui.fonts = false
    margins: 0
    implicitWidth: Theme.px(640)
    implicitHeight: Theme.px(600)

    property var fonts: []        // [{ family, style }]
    property var familyNames: ({})  // every installed family name -> true
    property string preview: previewField.text ? previewField.text : Tr.t("The quick brown fox jumps over the lazy dog 1234567890")
    property int previewSize: 15  // 10..48 pt, the size slider
    property string installNote: ""
    property bool installing: false
    property bool truncated: false   // more fonts than the list shows
    property int totalFonts: 0

    function refresh() {
        fonts = [];
        listFonts.running = true;
    }
    function copyFamily(family) {
        if (!family)
            return;
        Quickshell.clipboardText = family;
        Quickshell.execDetached(["notify-send", "-a", "Fonts", family]);
    }
    function installFont(path) {
        if (!path || win.installing)
            return;
        win.installing = true;
        win.installNote = Tr.t("Installing…");
        installFontProc.command = ["sh", "-c", 'dest="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"; mkdir -p "$dest" && cp -- "$1" "$dest/" && fc-cache -f >/dev/null 2>&1', "sh", path];
        installFontProc.running = true;
    }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: if (visible) refresh()

    Process {
        id: listFonts
        command: ["fc-list", ":", "family", "style"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                const out = [];
                const lines = text.split("\n");
                for (const line of lines) {
                    if (!line || line.indexOf(":") < 0)
                        continue;
                    const ci = line.indexOf(":");
                    const family = line.slice(0, ci).trim();
                    if (!family)
                        continue;
                    // "Family:style=Regular …" — the style after "style=" (or the tail)
                    let style = "";
                    const si = line.indexOf("style=");
                    if (si >= 0)
                        style = line.slice(si + 6).split(",")[0].trim();
                    else
                        style = line.slice(ci + 1).split(",")[0].trim();
                    const key = family + "\0" + style;
                    if (seen[key])
                        continue;
                    seen[key] = true;
                    out.push({ family: family, style: style });
                }
                out.sort((a, b) => a.family.toLowerCase().localeCompare(b.family.toLowerCase()));
                // every family name there is (fc-list gives "Family,Family Regular"; the
                // list below is cut to 400): what "Installed" is judged by
                const names = {};
                for (const f of out) for (const n of f.family.split(",")) names[n.trim()] = true;
                win.familyNames = names;
                win.fonts = out.slice(0, 400);
                win.truncated = out.length > 400;
                win.totalFonts = out.length;
            }
        }
    }

    Process {
        id: installFontProc
        onExited: code => {
            win.installing = false;
            if (code === 0) {
                win.installNote = Tr.t("Installed — font cache refreshed");
                Quickshell.execDetached(["notify-send", "-a", "Fonts", Tr.t("Font installed")]);
                win.refresh();
            } else {
                win.installNote = Tr.t("Could not install this font file");
            }
        }
    }

    // made on first use: a native dialog is the desktop portal's, and made
    // with every picker it held the whole shell while D-Bus waited for it
    Loader {
        id: fontFileDlg
        active: false
        function open() { active = true; item.open(); }
        sourceComponent: FileDialog {
            title: Tr.t("Install a font file")
            nameFilters: [Tr.t("Font files") + " (*.ttf *.otf *.ttc *.pfb)"]
            onAccepted: win.installFont(decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")))
        }
    }

    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.fonts = false }

    Item {
        id: card
        anchors.fill: parent


        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            spacing: Theme.px(12)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Item { Layout.fillWidth: true }
                Text {
                    text: win.fonts.length ? Tr.t("%1 styles", win.fonts.length) : ""
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                IconButton {
                    icon: "view-refresh"
                    size: Theme.px(28)
                    tip: Tr.t("Refresh")
                    onClicked: win.refresh()
                }
            }

            // a font file opened from Files (GNOME Font Viewer parity): the font in its
            // own type - its name, the letters, your words at four sizes - and Install
            // when its family is not among the installed ones yet
            Rectangle {
                id: fileCard
                objectName: "font-file"
                Layout.fillWidth: true
                visible: Ui.fontFile !== ""
                implicitHeight: fileCol.implicitHeight + Theme.px(24)
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.stroke
                FontLoader { id: fileFont; source: Ui.fontFile !== "" ? "file://" + Ui.fontFile : "" }
                readonly property bool ready: fileFont.status === FontLoader.Ready
                readonly property bool installed: ready && win.familyNames[fileFont.name] === true
                Binding { target: Ui; property: "fontFileFamily"; value: fileCard.ready ? fileFont.name : (fileFont.status === FontLoader.Error ? "!" : "") }
                Binding { target: Ui; property: "fontFileInstalled"; value: fileCard.installed }
                // what the file says of itself (fontconfig's fc-query, as GNOME Font Viewer's
                // details): its style, version, maker, format, and how many languages it covers
                property string details: ""
                Process {
                    id: fontInfo
                    running: Ui.fontFile !== ""
                    command: ["fc-query", "-i", "0", "-f", "%{style[0]}|%{fontversion}|%{foundry}|%{fontformat}|%{lang}", Ui.fontFile]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const p = text.split("|");
                            if (p.length < 5) { fileCard.details = ""; return; }
                            const v = parseInt(p[1]) || 0, langs = p.slice(4).filter(x => x).length;
                            fileCard.details = [p[0], v ? Tr.t("version %1", (v / 65536).toFixed(2).replace(/\.?0+$/, "")) : "",
                                                p[2] && p[2] !== "unknown" ? Tr.t("by %1", p[2]) : "", p[3],
                                                langs ? Tr.t("%1 languages", langs) : ""].filter(x => x).join(" · ");
                            Ui.fontFileDetails = fileCard.details;
                        }
                    }
                }
                ColumnLayout {
                    id: fileCol
                    anchors.fill: parent
                    anchors.margins: Theme.px(12)
                    spacing: Theme.px(6)
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: fileCard.ready ? fileFont.name : (fileFont.status === FontLoader.Error ? Tr.t("Not a font this can read") : Tr.t("Reading…"))
                            color: Theme.text; font.family: Theme.font; font.weight: Font.DemiBold
                            font.pixelSize: Theme.px(15) * Theme.fontScale
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: fileCard.ready
                            text: fileCard.installed ? Tr.t("Installed") : Tr.t("Not installed")
                            color: fileCard.installed ? Theme.accent : Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        Button {
                            visible: fileCard.ready && !fileCard.installed
                            text: win.installing ? Tr.t("Installing…") : Tr.t("Install")
                            enabled: !win.installing
                            onClicked: win.installFont(Ui.fontFile)
                        }
                        IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("All fonts"); onClicked: Ui.fontFile = "" }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: fileCard.details !== ""
                        text: fileCard.details
                        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: fileCard.ready
                        text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789 .,;:!?&@()"
                        font.family: fileFont.name; font.pixelSize: Theme.px(16)
                        color: Theme.text; wrapMode: Text.Wrap
                    }
                    Repeater {
                        model: fileCard.ready ? [14, 22, 32, 44] : []
                        Text {
                            required property int modelData
                            Layout.fillWidth: true
                            text: win.preview
                            font.family: fileFont.name; font.pixelSize: Theme.px(modelData)
                            color: Theme.text; elide: Text.ElideRight
                        }
                    }
                }
            }

            TextField {
                id: previewField
                Layout.fillWidth: true
                placeholder: Tr.t("Preview text — type here")
                label: Tr.t("Preview text")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Text {
                    text: Tr.t("Size")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: Theme.px(28)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: Theme.px(8)
                        radius: Theme.px(4)
                        color: Theme.hover
                        Rectangle {
                            width: Math.max(8, parent.width * ((win.previewSize - 10) / 38))
                            height: parent.height
                            radius: Theme.px(4)
                            color: Theme.accent
                        }
                    }
                    Rectangle {
                        x: Math.max(0, Math.min(parent.width - width, parent.width * ((win.previewSize - 10) / 38) - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.px(16)
                        height: Theme.px(16)
                        radius: Theme.px(8)
                        color: Theme.text
                        border.width: 3
                        border.color: Theme.accent
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function at(x) {
                            win.previewSize = Math.max(10, Math.min(48, Math.round(10 + 38 * Math.max(0, Math.min(1, x / width)))));
                        }
                        onPressed: me => at(me.x)
                        onPositionChanged: me => { if (pressed) at(me.x); }
                    }
                    KeyFocus {
                        name: Tr.t("Preview size")
                        slider: true
                        onStep: dir => win.previewSize = Math.max(10, Math.min(48, win.previewSize + dir));
                    }
                }
                Text {
                    text: win.previewSize + " pt"
                    color: Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button {
                    text: win.installing ? Tr.t("Installing…") : Tr.t("Install a font…")
                    enabled: !win.installing
                    onClicked: fontFileDlg.open()
                }
                Text {
                    Layout.fillWidth: true
                    visible: win.installNote !== ""
                    text: win.installNote
                    color: Theme.dim
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }

            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: win.fonts
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: Math.max(52, win.previewSize * 2 + 22)
                    radius: Theme.px(10)
                    color: rowArea.containsMouse ? Theme.hover : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: row.modelData.family + (row.modelData.style ? ", " + row.modelData.style : "")
                    Accessible.onPressAction: win.copyFamily(row.modelData.family)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(12)
                        anchors.rightMargin: Theme.px(12)
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: win.preview
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: row.modelData.family
                            font.pixelSize: win.previewSize * Theme.fontScale
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.family + (row.modelData.style ? " · " + row.modelData.style : "")
                            color: Theme.faint
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.copyFamily(row.modelData.family)
                    }
                    KeyFocus {
                        name: row.modelData.family
                        onActivated: win.copyFamily(row.modelData.family)
                    }
                }
            }

            EmptyState {
                Layout.fillWidth: true
                visible: win.fonts.length === 0 && !listFonts.running
                icon: "preferences-desktop-font"
                title: Tr.t("No fonts listed")
                subtitle: Tr.t("fc-list found nothing — is fontconfig installed?")
            }

            EmptyState {
                Layout.fillWidth: true
                visible: listFonts.running
                icon: "preferences-desktop-font"
                title: Tr.t("Reading installed fonts…")
                subtitle: ""
            }

            Item { Layout.fillWidth: true }
            Text {
                Layout.fillWidth: true
                visible: win.truncated
                text: Tr.t("Showing the first %1 of %2 styles").arg(win.fonts.length).arg(win.totalFonts)
                color: Theme.dim
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Click a font to copy its family name · Esc closes")
                color: Theme.faint
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
        }
    }
}
