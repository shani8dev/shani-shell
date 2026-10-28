// Settings > Personalisation > Icons, fonts & cursor: what is installed —
// icon themes (an index.theme with Directories=), cursor themes (a cursors/
// folder), fonts (fontconfig's families) — chosen here, applied by Appearance
// (apps) and InputConfig (niri's pointer).
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    readonly property var d: Settings.data
    property var iconThemes: []
    property var cursorThemes: []
    property var fonts: []
    property var monoFonts: []
    property string picking: ""           // "ui" | "mono" | ""

    Process {
        running: page.active && page.iconThemes.length === 0
        command: ["sh", "-c", 'for d in /usr/share/icons/* "${XDG_DATA_HOME:-$HOME/.local/share}"/icons/* "$HOME"/.icons/*; do
                [ -f "$d/index.theme" ] || continue; n=${d##*/}
                [ "$n" = hicolor ] || [ "$n" = default ] && continue
                grep -q "^Directories=" "$d/index.theme" && echo "icon $n"
                [ -d "$d/cursors" ] && echo "cursor $n"
            done | sort -u
            fc-list : family spacing | sed "s/,.*:/:/" | sort -u | sed "s/^/font /"']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                page.iconThemes = l.filter(x => x.startsWith("icon ")).map(x => x.slice(5));
                page.cursorThemes = l.filter(x => x.startsWith("cursor ")).map(x => x.slice(7));
                // "font Inter:" or "font DejaVu Sans Mono:spacing=100" (100 = monospace)
                const fams = l.filter(x => x.startsWith("font ")).map(x => x.slice(5));
                page.fonts = Array.from(new Set(fams.map(f => f.split(":")[0]))).filter(f => f && !f.startsWith(".")).sort();
                page.monoFonts = Array.from(new Set(fams.filter(f => /spacing=(100|110)/.test(f)).map(f => f.split(":")[0]))).sort();
            }
        }
    }

    component Picks: ColumnLayout {
        id: picks
        property string label
        property var options: []
        property var current
        signal picked(var value)
        Layout.fillWidth: true
        spacing: 6
        Text { text: picks.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: picks.options
                Choice {
                    required property var modelData
                    text: typeof modelData === "object" ? modelData.label : modelData
                    selected: picks.current === (typeof modelData === "object" ? modelData.value : modelData)
                    onClicked: picks.picked(typeof modelData === "object" ? modelData.value : modelData)
                }
            }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: "Icons, fonts & cursor" }
    Picks {
        label: "Icons"
        options: page.iconThemes
        current: page.d.iconTheme
        onPicked: v => page.d.iconTheme = v
    }
    RowLayout {
        visible: Appearance.iconsNeedRestart
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: "Apps use it now; the shell's own icons after it restarts."
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: 11 * Theme.fontScale
        }
        Button { text: "Restart the shell"; onClicked: Appearance.restartShell() }
    }
    Picks {
        label: "Pointer"
        options: page.cursorThemes
        current: page.d.cursorTheme
        onPicked: v => page.d.cursorTheme = v
    }
    Picks {
        label: "Pointer size"
        options: [{ label: "Normal", value: 24 }, { label: "Large", value: 32 }, { label: "Larger", value: 48 }, { label: "Largest", value: 64 }]
        current: page.d.cursorSize
        onPicked: v => page.d.cursorSize = v
    }

    // fonts: the current one, a size, and a search of what is installed
    Repeater {
        model: [{ id: "ui", label: "Interface font", key: "uiFont", size: "uiFontSize" }, { id: "mono", label: "Monospace font (terminals, code)", key: "monoFont", size: "monoFontSize" }]
        ColumnLayout {
            id: fontRow
            required property var modelData
            Layout.fillWidth: true
            spacing: 6
            Text { text: fontRow.modelData.label; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Choice {
                    text: page.d[fontRow.modelData.key] + "  ›"
                    selected: page.picking === fontRow.modelData.id
                    onClicked: page.picking = page.picking === fontRow.modelData.id ? "" : fontRow.modelData.id
                }
                Repeater {
                    model: [10, 11, 12, 13, 14]
                    Choice {
                        required property int modelData
                        text: String(modelData)
                        selected: page.d[fontRow.modelData.size] === modelData
                        onClicked: page.d[fontRow.modelData.size] = modelData
                    }
                }
            }
            Text {
                text: fontRow.modelData.id === "mono" ? "fn main() { println!(\"0O 1lI\"); }" : "The quick brown fox — शनि ओएस"
                color: Theme.text
                font.family: page.d[fontRow.modelData.key]
                font.pointSize: page.d[fontRow.modelData.size]
            }
            TextField {
                id: fontSearch
                Layout.fillWidth: true
                visible: page.picking === fontRow.modelData.id
                placeholder: "Search fonts"
            }
            Repeater {
                model: page.picking !== fontRow.modelData.id ? [] : (fontRow.modelData.id === "mono" ? page.monoFonts : page.fonts)
                    .filter(f => fontSearch.text.trim() === "" || f.toLowerCase().indexOf(fontSearch.text.trim().toLowerCase()) >= 0).slice(0, 12)
                ListRow {
                    required property string modelData
                    Layout.fillWidth: true
                    icon: "preferences-desktop-font"
                    title: modelData
                    selected: modelData === page.d[fontRow.modelData.key]
                    onClicked: {
                        page.d[fontRow.modelData.key] = modelData;
                        page.picking = "";
                    }
                }
            }
        }
    }
}
