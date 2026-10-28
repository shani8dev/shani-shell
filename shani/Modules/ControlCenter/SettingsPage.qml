// The shell's own settings, in the sidebar. Everything here is a key in
// ~/.config/shani-shell/settings.json — this page and the file are the same
// thing, and either can change it.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    readonly property var d: Settings.data
    property var wallpapers: []

    function minutes(s) { return s <= 0 ? "Never" : Math.round(s / 60) + " min"; }

    Process {
        running: page.visible
        command: ["sh", "-c", 'find /usr/share/backgrounds "$HOME/Pictures/Wallpapers" -maxdepth 2 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \\) 2>/dev/null | head -60']
        stdout: StdioCollector { onStreamFinished: page.wallpapers = text.trim().split("\n").filter(x => x) }
    }

    SectionTitle { Layout.fillWidth: true; text: "Wallpaper" }
    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 6
        rowSpacing: 6
        Repeater {
            model: page.wallpapers
            Rectangle {
                required property string modelData
                Layout.fillWidth: true
                implicitHeight: 62
                radius: 10
                color: Theme.hover
                border.width: page.d.wallpaper === modelData ? 2 : 0
                border.color: Theme.accent
                clip: true
                Image {
                    anchors.fill: parent
                    anchors.margins: 2
                    source: "file://" + parent.modelData
                    sourceSize: Qt.size(240, 140)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.d.wallpaper = parent.modelData
                }
            }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: "Bar & dock" }
    SwitchRow { Layout.fillWidth: true; text: "Network speed"; checked: page.d.showNetSpeed; onToggled: on => page.d.showNetSpeed = on }
    SwitchRow { Layout.fillWidth: true; text: "CPU and memory"; checked: page.d.showSysStats; onToggled: on => page.d.showSysStats = on }
    SwitchRow { Layout.fillWidth: true; text: "24-hour clock"; checked: page.d.use24h; onToggled: on => page.d.use24h = on }
    SwitchRow { Layout.fillWidth: true; text: "Seconds"; checked: page.d.showSeconds; onToggled: on => page.d.showSeconds = on }
    SwitchRow { Layout.fillWidth: true; text: "Dock"; checked: page.d.dock; onToggled: on => page.d.dock = on }
    SwitchRow { Layout.fillWidth: true; text: "Hide the dock"; hint: "touch the bottom edge to show it"; checked: page.d.dockAutoHide; onToggled: on => page.d.dockAutoHide = on }

    // ---- screen keyboard languages: any xkb layout, plus the hand-made two
    SectionTitle { Layout.fillWidth: true; text: "Screen keyboard" }
    property var catalogue: []
    Process {
        running: page.visible && page.catalogue.length === 0
        command: ["python3", Osk.script, "--list"]
        stdout: StdioCollector { onStreamFinished: { try { page.catalogue = JSON.parse(text); } catch (e) {} } }
    }
    function nameOf(id) {
        if (id === "en") return "English";
        if (id === "mr") return "मराठी (smart matras)";
        const c = catalogue.find(x => x.id === id);
        return c ? c.name : id;
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: page.d.oskLanguages
            Choice {
                required property string modelData
                text: page.nameOf(modelData) + (page.d.oskLanguages.length > 1 ? "  ✕" : "")
                selected: true
                onClicked: if (page.d.oskLanguages.length > 1) page.d.oskLanguages = Array.from(page.d.oskLanguages).filter(x => x !== modelData)
            }
        }
    }
    TextField {
        id: layoutSearch
        Layout.fillWidth: true
        placeholder: "Add a layout — marathi, tamil, russian, arabic …"
    }
    Repeater {
        model: {
            const q = layoutSearch.text.trim().toLowerCase();
            if (q.length < 2)
                return [];
            return page.catalogue.filter(x => x.name.toLowerCase().indexOf(q) >= 0 || x.id.indexOf(q) >= 0
                || x.langs.some(l => l === q)).slice(0, 12);
        }
        ListRow {
            required property var modelData
            Layout.fillWidth: true
            icon: "input-keyboard"
            title: modelData.name
            subtitle: modelData.id
            onClicked: {
                if (page.d.oskLanguages.indexOf(modelData.id) < 0)
                    page.d.oskLanguages = Array.from(page.d.oskLanguages).concat([modelData.id]);
                layoutSearch.text = "";
            }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: "Look & feel" }
    SwitchRow { Layout.fillWidth: true; text: "Blur"; checked: page.d.blur; onToggled: on => page.d.blur = on }
    SwitchRow { Layout.fillWidth: true; text: "Reduce motion"; hint: "no slides, fades or zoom"; checked: page.d.reduceMotion; onToggled: on => page.d.reduceMotion = on }
    RowLayout {
        Layout.fillWidth: true
        visible: NightLight.available
        Text { text: "Night light"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; Layout.preferredWidth: 90 }
        Repeater {
            model: [2700, 3400, 4000, 5000]
            Choice {
                required property int modelData
                text: modelData + " K"
                selected: page.d.nightLightTemp === modelData
                onClicked: page.d.nightLightTemp = modelData
            }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: "When idle" }
    Repeater {
        model: [
            { label: "Lock after", key: "lockAfter", options: [60, 120, 300, 600, 900, 0] },
            { label: "Screen off after", key: "screenOffAfter", options: [120, 300, 600, 1800, 0] },
            { label: "Suspend after", key: "suspendAfter", options: [900, 1800, 3600, 0] }
        ]
        ColumnLayout {
            id: stage
            required property var modelData
            Layout.fillWidth: true
            spacing: 4
            Text { text: stage.modelData.label + " (on power)"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: stage.modelData.options
                    Choice {
                        required property int modelData
                        text: page.minutes(modelData)
                        selected: page.d[stage.modelData.key] === modelData
                        onClicked: page.d[stage.modelData.key] = modelData
                    }
                }
            }
        }
    }
    SwitchRow { Layout.fillWidth: true; text: "Lock before suspend"; checked: page.d.lockBeforeSuspend; onToggled: on => page.d.lockBeforeSuspend = on }

    Text {
        Layout.fillWidth: true
        text: "Saved to " + Settings.path
        color: Theme.faint
        elide: Text.ElideMiddle
        font.family: Theme.mono
        font.pixelSize: 10
    }
}
