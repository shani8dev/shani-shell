// Settings > Personalisation > Live wallpaper: a video behind the desktop
// (Services/LiveWallpaper plays it only while it can be seen). Videos in
// Videos/Wallpapers and Videos are one click each; any other file is chosen.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 8
    property bool active: false
    readonly property var d: Settings.data
    property var found: []
    onActiveChanged: if (active) finder.running = true
    Process {
        id: finder
        command: ["sh", "-c", 'v="${XDG_VIDEOS_DIR:-$HOME/Videos}"; find "$v/Wallpapers" "$v" -maxdepth 1 -type f \\( -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mkv" -o -iname "*.mov" \\) 2>/dev/null | awk "!s[\\$0]++" | head -n 12']
        stdout: StdioCollector { onStreamFinished: page.found = text.trim().split("\n").filter(x => x) }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Live wallpaper") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("A video behind the desktop, without sound. It plays only while you can see it: it pauses under windows, when the screen is locked or dimmed, and on battery.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Choice { text: Tr.t("None"); selected: !page.d.wallpaperVideo; onClicked: page.d.wallpaperVideo = "" }
        Repeater {
            model: page.found
            Choice {
                required property string modelData
                text: modelData.split("/").pop()
                selected: page.d.wallpaperVideo === modelData
                onClicked: page.d.wallpaperVideo = modelData
            }
        }
        Choice {
            text: Tr.t("Choose a video…")
            onClicked: FilePicker.open({ mode: "open", title: Tr.t("A video for the wallpaper"), filters: ["mp4", "webm", "mkv", "mov"],
                                         startPath: Quickshell.env("HOME") + "/Videos", onPicked: paths => { if (paths.length) page.d.wallpaperVideo = paths[0]; } })
        }
    }
    SwitchRow {
        Layout.fillWidth: true
        visible: page.d.wallpaperVideo !== ""
        text: Tr.t("Keep playing on battery")
        hint: Tr.t("off: it pauses on battery, as a video costs power")
        checked: page.d.wallpaperVideoOnBattery
        onToggled: on => page.d.wallpaperVideoOnBattery = on
    }
}
