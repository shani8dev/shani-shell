// Aether: extract a theme from a picture (Omarchy theme-extractor parity, on
// this shell's own palette code — Matugen). Pick an image (or use the last
// wallpaper), preview it, Extract the palette Matugen derives, Apply it as
// the wallpaper + colours, or Save it as a named theme in Settings. The
// state lives in Services/Aether; this is only the surface, in the QrView
// PanelWindow pattern.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.aether && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-aether"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property var roles: ["primary", "on_primary", "primary_container", "secondary_container", "tertiary", "surface", "surface_high", "on_surface", "on_surface_variant", "outline"]
    readonly property var shown: (Matugen.previewPalette && Object.keys(Matugen.previewPalette).length) ? Matugen.previewPalette : Matugen.palette

    MouseArea { anchors.fill: parent; onClicked: Aether.close() }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Aether.close() }

    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Math.min(600, parent.width - 80)
        implicitHeight: col.implicitHeight + 40
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Icon { name: "palette"; size: 20; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Aether")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "window-close"; size: 28; tip: Tr.t("Close"); onClicked: Aether.close() }
            }

            Text {
                Layout.fillWidth: true
                text: Tr.t("Matugen only reads the current wallpaper file, so Apply copies this picture over that file (cp) and then regenerates the colours with themeReload. Extract runs the same matugen call on this picture in isolation — it changes nothing until you press Apply.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                radius: Theme.radiusSmall
                color: Theme.hover
                clip: true
                Image {
                    anchors.fill: parent
                    source: Aether.image ? "file://" + Aether.image : ""
                    fillMode: Image.PreserveAspectFit
                    Accessible.role: Accessible.Graphic
                    Accessible.name: Tr.t("Picture being themed")
                }
                Text {
                    visible: Aether.image === ""
                    anchors.centerIn: parent
                    text: Tr.t("No picture yet — pick one, type a path, or use the last wallpaper")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
            Text {
                Layout.fillWidth: true
                text: Aether.image || Tr.t("(nothing picked)")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
                elide: Text.ElideMiddle
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                TextField {
                    id: pathField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Path to a picture (/home/.../photo.jpg)")
                    onAccepted: {
                        let p = pathField.text.trim();
                        if (p === "") return;
                        if (p.indexOf("~") === 0) p = (Quickshell.env("HOME") || "/home") + p.slice(1);
                        Aether.open(p);
                    }
                }
                Button { text: Tr.t("Use path"); onClicked: pathField.accepted() }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                Button { text: Tr.t("Browse…"); onClicked: fileDlg.open() }
                Button { text: Tr.t("Use last wallpaper"); onClicked: Aether.open(Aether.lastWallpaper) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Button { text: Tr.t("Extract palette"); onClicked: Aether.extract() }
                Button { text: Tr.t("Apply as wallpaper + colours"); kind: "primary"; onClicked: Aether.apply() }
            }

            Text {
                visible: Matugen.previewRunning
                text: Tr.t("Extracting…")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
            Text {
                visible: !Matugen.previewRunning && Matugen.previewError !== ""
                text: Matugen.previewError
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Text {
                visible: Matugen.available === false
                text: Tr.t("matugen is not installed — Aether needs it to extract colours (ShaniOS ships it)")
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Text {
                visible: Aether.note !== "" && Matugen.previewError === ""
                text: Aether.note
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            SectionTitle { visible: Object.keys(win.shown || {}).length > 0; Layout.fillWidth: true; text: Tr.t("Dominant colours matugen derives") }
            ColumnLayout {
                visible: Object.keys(win.shown || {}).length > 0
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: win.roles
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            implicitWidth: 28
                            implicitHeight: 20
                            radius: 6
                            color: (win.shown && win.shown[modelData]) || Theme.accent
                            border.color: Theme.stroke
                            border.width: 1
                            Accessible.role: Accessible.Graphic
                            Accessible.name: modelData
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData + "  " + ((win.shown && win.shown[modelData]) || "—")
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                TextField {
                    id: themeField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Name this theme")
                    onAccepted: Aether.saveTheme(themeField.text)
                }
                Button { text: Tr.t("Save theme"); onClicked: Aether.saveTheme(themeField.text) }
            }

            Text {
                visible: (Settings.data.aetherThemes || []).length === 0
                text: Tr.t("No themes saved yet — extract, name it, Save theme.")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
                Layout.fillWidth: true
            }
            ColumnLayout {
                visible: (Settings.data.aetherThemes || []).length > 0
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: Settings.data.aetherThemes || []
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: (modelData.name || "Untitled theme") + (modelData.image ? "  ·  " + modelData.image : "")
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                            elide: Text.ElideMiddle
                        }
                        Button { text: Tr.t("Load"); onClicked: Aether.loadTheme(index) }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Esc closes")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
        }
    }

    Loader {
        id: fileDlg
        active: false
        function open() { active = true; item.open(); }
        sourceComponent: FileDialog {
            title: Tr.t("Choose a picture")
            nameFilters: [Tr.t("Pictures") + " (*.png *.jpg *.jpeg *.webp)"]
            onAccepted: Aether.open(selectedFile.toString().replace(/^file:\/\//, ""))
        }
    }
}
