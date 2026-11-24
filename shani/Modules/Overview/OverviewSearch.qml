// The overview, made GNOME's Activities / KDE's Overview: niri draws every
// workspace and its windows (live, zoomed out); the shell adds a search field
// at the top while it is open. Typing starts a search - the overview closes
// into the launcher with what was typed - and the keys niri's overview is
// driven with keep working: arrows move between windows and workspaces, Enter
// takes the one picked, Esc leaves. The dock stays, with its workspace tiles.
// A first-run strip under the field teaches the gestures that reach the
// window tools; it goes away for good at its ×.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    NavWindow {}     // known to the keys-and-controller reach check (Ui.navAuditAll)
    id: win
    visible: Niri.overviewOpen && !Ui.launcher
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors.top: true
    margins.top: 58
    implicitWidth: Theme.px(620)
    implicitHeight: Theme.px(64) + (hints.visible ? hints.implicitHeight + Theme.px(8) : 0)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-overview-search"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: (visible) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted ? pillRegion : null
    Region { id: pillRegion; item: pill; radius: pill.radius }

    // Settings.data's JsonAdapter only accepts keys declared in Common/Settings.qml,
    // which this module does not own (that file is being changed elsewhere), so the
    // one dismissal flag lives in a sibling file in the same config dir, the way
    // Services/Osk.qml keeps its own controls. Defaults are declared on the adapter.
    readonly property string hintsDir: {
        const p = Settings.path;
        return p.substring(0, p.lastIndexOf("/"));
    }
    FileView {
        id: hintsFile
        path: win.hintsDir + "/gesture-hints.json"
        watchChanges: true
        atomicWrites: true
        printErrors: false
        JsonAdapter { id: hintsPrefs; property bool dismissed: false }
    }
    // five at most, so the strip stays one short block under the search field
    readonly property var gestureTips: [
        { keys: "Super+Alt+←/→", what: Tr.t("Snap left") },
        { keys: "Hold zoom", what: Tr.t("Window layout") },
        { keys: "Hover", what: Tr.t("Preview") },
        { keys: "Right-click dock", what: Tr.t("Switch windows") },
        { keys: "Middle-click dock", what: Tr.t("New window") }
    ]
    function dismissHints() {
        hintsPrefs.dismissed = true;
        Quickshell.execDetached(["mkdir", "-p", win.hintsDir]);
        hintsFile.writeAdapter();
    }

    function search(text) {
        handOver.stop();   // a pending hand-over would toggle the launcher again 220 ms later
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
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.px(4)
        height: Theme.px(56)
        strong: true
        radius: height / 2
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.px(22)
            anchors.rightMargin: Theme.px(22)
            spacing: Theme.px(12)
            Icon { name: "system-search"; size: Theme.px(20); color: Theme.accent }
            Text {
                Layout.fillWidth: true
                text: win.typed || Tr.t("Type to search apps, files and settings")
                color: win.typed ? Theme.text : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(16) * Theme.fontScale
            }
            Text {
                text: Tr.t("arrows · Enter · Esc")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: win.search("") }
    }

    // Only bindings that exist are taught: Super+Alt+Arrow is bound in
    // shani-desktop-niri's config, the bar's zoom button opens layouts on a
    // long press, HoverPeek previews dock tiles and files, and the dock's
    // right-click lists an app's windows (its middle click opens a NEW window).
    Glass {
        id: hints
        visible: !hintsPrefs.dismissed
        anchors.top: pill.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.px(4)
        implicitWidth: grid.implicitWidth + Theme.px(16)
        implicitHeight: grid.implicitHeight + Theme.px(12)
        radius: Theme.radiusSmall
        elevation: "none"
        Grid {
            id: grid
            anchors.centerIn: parent
            columns: 2
            columnSpacing: Theme.px(16)
            rowSpacing: Theme.px(6)
            Repeater {
                model: win.gestureTips
                Row {
                    required property var modelData
                    spacing: Theme.px(8)
                    Rectangle {
                        width: Theme.px(104)
                        height: Theme.px(20)
                        radius: Theme.px(5)
                        color: Theme.alpha(Theme.text, 0.09)
                        Text {
                            anchors.centerIn: parent
                            text: parent.parent.modelData.keys
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                            font.weight: Font.Medium
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.what
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
            }
        }
        IconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.px(4)
            icon: "window-close"
            size: Theme.px(18)
            tip: Tr.t("Hide the navigation hints")
            accessibleName: Tr.t("Hide the navigation hints")
            onClicked: win.dismissHints()
        }
        // the button takes Tab; Escape must still leave the overview from it
        Keys.onEscapePressed: Niri.action("close-overview")
    }

    Item {
        id: keys
        focus: true
        activeFocusOnTab: true
        Accessible.role: Accessible.EditableText
        Accessible.name: Tr.t("Search")
        Keys.onPressed: e => {
            const move = { [Qt.Key_Left]: "focus-column-left", [Qt.Key_Right]: "focus-column-right",
                           [Qt.Key_Up]: "focus-window-or-workspace-up", [Qt.Key_Down]: "focus-window-or-workspace-down" }[e.key];
            if (move) {
                Niri.action(move);
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Escape) {
                // Escape, or Enter with nothing typed: back to the window picked with the arrows
                if (e.key === Qt.Key_Escape || win.typed === "") {
                    handOver.stop();
                    Niri.action("close-overview");
                } else
                    win.search(win.typed);
            } else if (e.key === Qt.Key_Backspace || e.key === Qt.Key_Delete) {
                // there is no caret: Backspace takes the last character typed
                if (win.typed === "")
                    return;
                win.typed = win.typed.slice(0, -1);
                if (win.typed !== "")
                    handOver.restart();
                else
                    handOver.stop();
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
    Connections { target: Ui; function onLauncherChanged() { if (Ui.launcher && Niri.overviewOpen) Niri.action("close-overview"); } }
}
