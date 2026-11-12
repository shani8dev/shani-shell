// Settings > Personalisation > Colours from a picture: the desktop's colours
// taken from a picture by matugen. Pick one (or the last wallpaper), Extract to
// see the colours first, Apply to make it the wallpaper and the colours yours,
// or Save it as a named theme. The state lives in Services/WallpaperStyle.
import Quickshell
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    objectName: "section:colours"
    spacing: 10
    property bool active: false
    onActiveChanged: if (active && WallpaperStyle.image === "" && WallpaperStyle.lastWallpaper) WallpaperStyle.open(WallpaperStyle.lastWallpaper)

    property var roles: ["primary", "on_primary", "primary_container", "secondary_container", "tertiary", "surface", "surface_high", "on_surface", "on_surface_variant", "outline"]
    readonly property var shown: (Matugen.previewPalette && Object.keys(Matugen.previewPalette).length) ? Matugen.previewPalette : Matugen.palette

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Colours from a picture") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("The desktop's colours, taken from a picture. Extract shows them first; Apply makes the picture your wallpaper and the colours yours.")
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
            source: WallpaperStyle.image ? "file://" + WallpaperStyle.image : ""
            fillMode: Image.PreserveAspectFit
            Accessible.role: Accessible.Graphic
            Accessible.name: Tr.t("Picture being themed")
        }
        Text {
            visible: WallpaperStyle.image === ""
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
        text: WallpaperStyle.image || Tr.t("(nothing picked)")
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
                WallpaperStyle.open(p);
            }
        }
        Button { text: Tr.t("Use path"); onClicked: pathField.accepted() }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6
        Button { text: Tr.t("Browse…"); onClicked: fileDlg.open() }
        Button { text: Tr.t("Use last wallpaper"); onClicked: WallpaperStyle.open(WallpaperStyle.lastWallpaper) }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Button { text: Tr.t("Extract palette"); onClicked: WallpaperStyle.extract() }
        Button { text: Tr.t("Apply as wallpaper + colours"); kind: "primary"; onClicked: WallpaperStyle.apply() }
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
        text: Tr.t("matugen is not installed — colours from a picture need it (ShaniOS ships it)")
        color: Theme.danger
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
    Text {
        visible: WallpaperStyle.note !== "" && Matugen.previewError === "" && Matugen.available !== false   // the line above already says matugen is missing
        text: WallpaperStyle.note
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    SectionTitle { visible: Object.keys(page.shown || {}).length > 0; Layout.fillWidth: true; text: Tr.t("Dominant colours matugen derives") }
    ColumnLayout {
        visible: Object.keys(page.shown || {}).length > 0
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: page.roles
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 20
                    radius: 6
                    color: (page.shown && page.shown[modelData]) || Theme.accent
                    border.color: Theme.stroke
                    border.width: 1
                    Accessible.role: Accessible.Graphic
                    Accessible.name: modelData
                }
                Text {
                    Layout.fillWidth: true
                    text: modelData + "  " + ((page.shown && page.shown[modelData]) || "—")
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
            onAccepted: WallpaperStyle.saveTheme(themeField.text)
        }
        Button { text: Tr.t("Save theme"); onClicked: WallpaperStyle.saveTheme(themeField.text) }
    }

    Text {
        visible: (Settings.data.wallpaperStyleThemes || []).length === 0
        text: Tr.t("No themes saved yet — extract, name it, Save theme.")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
        Layout.fillWidth: true
    }
    ColumnLayout {
        visible: (Settings.data.wallpaperStyleThemes || []).length > 0
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: Settings.data.wallpaperStyleThemes || []
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
                Button { text: Tr.t("Load"); onClicked: WallpaperStyle.loadTheme(index) }
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
        onAccepted: WallpaperStyle.open(selectedFile.toString().replace(/^file:\/\//, ""))
    }
}
}
