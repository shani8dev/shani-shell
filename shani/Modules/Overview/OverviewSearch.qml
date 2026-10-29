// The overview, made GNOME's Activities / KDE's Overview: niri draws every
// workspace and its windows (live, zoomed out); the shell adds a search field
// at the top while it is open. Typing starts a search - the overview closes
// into the launcher with what was typed - and the keys niri's overview is
// driven with keep working: arrows move between windows and workspaces, Enter
// takes the one picked, Esc leaves. The dock stays, with its workspace tiles.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Niri.overviewOpen && !Ui.launcher
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors.top: true
    margins.top: 58
    implicitWidth: 620
    implicitHeight: 64
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-overview-search"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.data.blur ? pillRegion : null
    Region { id: pillRegion; item: pill; radius: pill.radius }

    function search(text) {
        typed = "";
        Niri.action("close-overview");
        Ui.toggleLauncher(text);
    }
    // what is typed is gathered for a moment and handed over whole, so the
    // letters typed while the launcher opens are not lost
    property string typed: ""
    Timer { id: handOver; interval: 220; onTriggered: win.search(win.typed) }
    onVisibleChanged: if (!visible) { handOver.stop(); typed = ""; }

    Glass {
        id: pill
        anchors.fill: parent
        anchors.margins: 4
        strong: true
        radius: height / 2
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            spacing: 12
            Icon { name: "system-search"; size: 20; color: Theme.accent }
            Text {
                Layout.fillWidth: true
                text: win.typed || Tr.t("Type to search apps, files and settings")
                color: win.typed ? Theme.text : Theme.dim
                font.family: Theme.font
                font.pixelSize: 16 * Theme.fontScale
            }
            Text {
                text: Tr.t("arrows · Enter · Esc")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: win.search("") }
    }

    Item {
        id: keys
        focus: true
        Accessible.role: Accessible.EditableText
        Accessible.name: Tr.t("Search")
        Keys.onPressed: e => {
            const move = { [Qt.Key_Left]: "focus-column-left", [Qt.Key_Right]: "focus-column-right",
                           [Qt.Key_Up]: "focus-window-or-workspace-up", [Qt.Key_Down]: "focus-window-or-workspace-down" }[e.key];
            if (move) {
                Niri.action(move);
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Escape) {
                Niri.action("close-overview");
            } else if (e.text && (e.text.trim() !== "" || win.typed !== "") && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                win.typed += e.text;
                handOver.restart();
            } else {
                return;
            }
            e.accepted = true;
        }
    }
    Connections { target: win; function onVisibleChanged() { if (win.visible) keys.forceActiveFocus(); } }
}
