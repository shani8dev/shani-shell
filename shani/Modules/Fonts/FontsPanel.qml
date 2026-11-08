// The font browser: what fonts are installed (fc-list), each shown as its
// own type; typing previews your words at the chosen size; clicking a row
// copies its family name to the clipboard (for Settings > Personalisation,
// or a document). A font file can be installed from disk into
// ~/.local/share/fonts, and the fontconfig cache is refreshed after.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.fonts && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-fonts"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurRegion : null
    Region { id: blurRegion; item: card; radius: Theme.radiusLarge }

    property var fonts: []        // [{ family, style }]
    property string preview: previewField.text ? previewField.text : Tr.t("The quick brown fox jumps over the lazy dog 1234567890")
    property int previewSize: 15  // 10..48 pt, the size slider
    property string installNote: ""
    property bool installing: false

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
                win.fonts = out.slice(0, 400);
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
            onAccepted: win.installFont(selectedFile.toString().replace(/^file:\/\//, ""))
        }
    }

    MouseArea { anchors.fill: parent; onClicked: Ui.fonts = false }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.fonts = false }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(640, parent.width - 40)
        height: Math.min(600, parent.height - 80)
        strong: true
        radius: Theme.radiusLarge

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SectionTitle {
                    Layout.fillWidth: true
                    text: Tr.t("Fonts")
                }
                Text {
                    text: win.fonts.length ? Tr.t("%1 styles", win.fonts.length) : ""
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 10 * Theme.fontScale
                }
                IconButton {
                    icon: "view-refresh"
                    size: 28
                    tip: Tr.t("Refresh")
                    onClicked: win.refresh()
                }
                IconButton {
                    icon: "window-close"
                    size: 28
                    tip: Tr.t("Close")
                    onClicked: Ui.fonts = false
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
                spacing: 8
                Text {
                    text: Tr.t("Size")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 8
                        radius: 4
                        color: Theme.hover
                        Rectangle {
                            width: Math.max(8, parent.width * ((win.previewSize - 10) / 38))
                            height: parent.height
                            radius: 4
                            color: Theme.accent
                        }
                    }
                    Rectangle {
                        x: Math.max(0, Math.min(parent.width - width, parent.width * ((win.previewSize - 10) / 38) - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        radius: 8
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
                    font.pixelSize: 10 * Theme.fontScale
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    text: Tr.t("Install a font…")
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
                    font.pixelSize: 11 * Theme.fontScale
                }
            }

            ListView {
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
                    radius: 10
                    color: rowArea.containsMouse ? Theme.hover : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: row.modelData.family + (row.modelData.style ? ", " + row.modelData.style : "")
                    Accessible.onPressAction: win.copyFamily(row.modelData.family)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
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
                            font.pixelSize: 10 * Theme.fontScale
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

            Text {
                Layout.fillWidth: true
                text: Tr.t("Click a font to copy its family name · Esc closes")
                color: Theme.faint
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
        }
    }
}
