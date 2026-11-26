// A call arriving on any line: the shell's own card, not a notification from
// another app. The bridge reports it in Link.incoming; Answer and Decline go
// straight back through the same bridge.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Link.incoming && Link.incoming.id !== ""
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors.top: true
    margins.top: Theme.px(80)
    implicitWidth: Theme.px(340)
    implicitHeight: card.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-call"
    // the shell's own glass, as on every surface, over a blur of what is behind
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Glass {
        id: card
        width: parent.width
        implicitHeight: col.implicitHeight + Theme.px(36)
        strong: true
        radius: Theme.radiusLarge
        Accessible.name: Tr.t("Incoming call") + ": " + (Link.incoming.name || Link.incoming.number || Tr.t("Unknown"))
        Keys.onEscapePressed: win.decline()
        ColumnLayout {
            id: col
            x: Theme.px(18)
            y: Theme.px(18)
            width: parent.width - Theme.px(36)
            spacing: Theme.px(10)
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)
                Icon { name: "call-start"; size: Theme.px(22); color: Theme.accent }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(2)
                    Text {
                        Layout.fillWidth: true
                        text: Link.incoming.name || Link.incoming.number || Tr.t("Unknown")
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.type("heading")
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("Incoming call") + (Link.incoming.line ? " · " + Link.incoming.line : "")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.type("small")
                        elide: Text.ElideRight
                    }
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Theme.px(8)
                Button {
                    text: Tr.t("Decline")
                    onClicked: win.decline()
                }
                Button {
                    kind: "primary"
                    text: Tr.t("Answer")
                    onClicked: Link.callAction(Link.incoming.id, "answer")
                }
            }
        }
    }

    function decline() { Link.callAction(Link.incoming.id, "decline") }
}
