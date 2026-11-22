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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Theme.px(480)
    implicitHeight: Theme.px(360)
    // stay above normal windows but below fullscreen apps
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }

    // keyboard: Esc closes the pin
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: { Screenshots.pinned = false; Screenshots.pinnedPath = ""; }
    }

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
            Image {
                id: shot
                Layout.fillWidth: true
                Layout.fillHeight: true
                fillMode: Image.PreserveAspectFit
                source: Screenshots.pinnedPath !== "" ? "file://" + Screenshots.pinnedPath : ""
                asynchronous: true
                cache: false
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
