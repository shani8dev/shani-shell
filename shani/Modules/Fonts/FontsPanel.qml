// The font browser: what fonts are installed (fc-list), each shown as its
// own type; typing previews your words; clicking a row copies its family
// name to the clipboard (for Settings > Personalisation, or a document).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
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

    function refresh() {
        fonts = [];
        listFonts.running = true;
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

    MouseArea { anchors.fill: parent; onClicked: Ui.fonts = false }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.fonts = false }

    Glass {
        id: card
        anchors.centerIn: parent
        width: 640
        height: 560
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
                    height: 52
                    radius: 10
                    color: rowArea.containsMouse ? Theme.hover : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: row.modelData.family + (row.modelData.style ? ", " + row.modelData.style : "")
                    Accessible.onPressAction: Quickshell.clipboardText = row.modelData.family

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
                            font.pixelSize: 15 * Theme.fontScale
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
                        onClicked: {
                            Quickshell.clipboardText = row.modelData.family;
                            Quickshell.execDetached(["notify-send", "-a", "Fonts", row.modelData.family]);
                        }
                    }
                    KeyFocus {
                        name: row.modelData.family
                        onActivated: {
                            Quickshell.clipboardText = row.modelData.family;
                            Quickshell.execDetached(["notify-send", "-a", "Fonts", row.modelData.family]);
                        }
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
