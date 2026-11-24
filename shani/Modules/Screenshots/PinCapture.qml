// Pin capture: an always-on-top window showing the last screenshot,
// like Slate's "pin a capture above your work". The user can move it,
// resize it, or close it. Right-click copies the path; double-click
// opens it in the image viewer.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Screenshots.pinned && Screenshots.pinnedPath !== ""
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    // floating window, not fullscreen — positioned by the user
    WlrLayershell.namespace: "shani-pin-capture"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Theme.px(480)
    implicitHeight: Theme.px(360)
    // stay above normal windows but below fullscreen apps
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }

    // encode each path segment so '#', '?' or '%' in a filename still loads
    function fileUrl(p) { return "file://" + p.split("/").map(encodeURIComponent).join("/"); }

    // keyboard: Esc closes the pin
    Item {
        id: keyHandler
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: { Screenshots.pinned = false; Screenshots.pinnedPath = ""; }
    }
    onVisibleChanged: if (visible) keyHandler.forceActiveFocus()

    Glass {
        id: card
        anchors.fill: parent
        strong: true
        radius: Theme.radiusLarge

        ColumnLayout {
            anchors { fill: parent; margins: Theme.px(8) }
            spacing: Theme.px(4)

            // title bar with close + copy buttons
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: Tr.t("Pinned screenshot")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                IconButton {
                    icon: "edit-copy"
                    size: Theme.px(24)
                    tip: Tr.t("Copy path")
                    onClicked: Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", Screenshots.pinnedPath])
                }
                IconButton {
                    icon: "window-close"
                    size: Theme.px(24)
                    tip: Tr.t("Close")
                    onClicked: { Screenshots.pinned = false; Screenshots.pinnedPath = ""; }
                }
            }

            // the screenshot image
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Image {
                    id: shot
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    source: Screenshots.pinnedPath !== "" ? fileUrl(Screenshots.pinnedPath) : ""
                    asynchronous: true
                    cache: false
                    sourceSize.width: Math.max(1, Math.round(width))
                    sourceSize.height: Math.max(1, Math.round(height))
                    visible: status !== Image.Error
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", Screenshots.pinnedPath]);
                            } else {
                                Quickshell.execDetached(["xdg-open", Screenshots.pinnedPath]);
                            }
                        }
                        // Qt fires `clicked` for both clicks of a double-click, so a
                        // separate handler opened the image twice over. Left-click above
                        // already opens it once.
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: shot.status === Image.Error
                    text: Tr.t("Screenshot not found")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                }
            }

            // footer with file info
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Screenshots.pinnedPath !== "" ? Screenshots.pinnedPath.split("/").pop() : ""
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(9) * Theme.fontScale
                elide: Text.ElideMiddle
            }
        }
    }
}
