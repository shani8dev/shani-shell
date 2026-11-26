// Pin capture: an always-on-top window showing the last screenshot,
// like Slate's "pin a capture above your work". The user can move it,
// resize it, or close it. Drag the title bar to move, drag the bottom-right
// grip to resize, scroll to zoom, and use the buttons to copy/share/save.
// Right-click copies the path; left-click opens it in the image viewer.
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

    readonly property int minW: Theme.px(240)
    readonly property int minH: Theme.px(180)

    // encode each path segment so '#', '?' or '%' in a filename still loads
    function fileUrl(p) { return "file://" + p.split("/").map(encodeURIComponent).join("/"); }
    function close() { Screenshots.pinned = false; Screenshots.pinnedPath = ""; }

    // keyboard: Esc closes the pin
    Item {
        id: keyHandler
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: win.close()
    }
    onVisibleChanged: if (visible) keyHandler.forceActiveFocus()

    Glass {
        id: card
        anchors.fill: parent
        strong: true
        radius: Theme.radiusLarge
        opacity: Screenshots.pinOpacity

        ColumnLayout {
            anchors { fill: parent; margins: Theme.px(8) }
            spacing: Theme.px(4)

            // title bar: dragging the label moves the floating pin
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(2)
                MouseArea {
                    id: titleDrag
                    Layout.fillWidth: true
                    height: Theme.px(26)
                    cursorShape: Qt.SizeAllCursor
                    property real lastX: 0
                    property real lastY: 0
                    onPressed: { lastX = mouse.x; lastY = mouse.y; }
                    onPositionChanged: if (pressed) {
                        win.x += mouse.x - lastX;
                        win.y += mouse.y - lastY;
                        lastX = mouse.x; lastY = mouse.y;
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: Tr.t("Pinned screenshot")
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.type("body")
                        font.weight: Font.DemiBold
                    }
                }
                IconButton {
                    icon: "edit-copy"; size: Theme.px(20)
                    tip: Tr.t("Copy image"); accessibleName: Tr.t("Copy the pinned image")
                    onClicked: Screenshots.copyImage(Screenshots.pinnedPath)
                }
                IconButton {
                    icon: "document-save"; size: Theme.px(20)
                    tip: Tr.t("Save"); accessibleName: Tr.t("Save the pinned image")
                    onClicked: Screenshots.saveImage(Screenshots.pinnedPath)
                }
                IconButton {
                    icon: "document-share"; size: Theme.px(20)
                    tip: Tr.t("Share"); accessibleName: Tr.t("Share the pinned image")
                    onClicked: Screenshots.shareImage(Screenshots.pinnedPath)
                }
                IconButton {
                    icon: "edit-copy"; size: Theme.px(20)
                    tip: Tr.t("Copy path"); accessibleName: Tr.t("Copy the screenshot path")
                    onClicked: Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", Screenshots.pinnedPath])
                }
                IconButton {
                    icon: "preferences-system"; size: Theme.px(20)
                    tip: Tr.t("Opacity"); accessibleName: Tr.t("Change the pin opacity")
                    onClicked: Screenshots.cyclePinOpacity()
                }
                IconButton {
                    icon: "view-restore"; size: Theme.px(20)
                    tip: Tr.t("Fit image"); accessibleName: Tr.t("Reset the pin zoom to fit")
                    onClicked: Screenshots.resetPinZoom()
                }
                IconButton {
                    icon: "window-close"; size: Theme.px(20)
                    tip: Tr.t("Close"); accessibleName: Tr.t("Close the pinned screenshot")
                    onClicked: win.close()
                }
            }

            // the screenshot image
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Image {
                    id: shot
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    source: Screenshots.pinnedPath !== "" ? fileUrl(Screenshots.pinnedPath) : ""
                    asynchronous: true
                    cache: false
                    sourceSize.width: Math.max(1, Math.round(width))
                    sourceSize.height: Math.max(1, Math.round(height))
                    scale: Screenshots.pinZoom
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
                        onWheel: w => {
                            w.accepted = true;
                            Screenshots.pinZoom = Math.max(0.5, Math.min(4,
                                Screenshots.pinZoom + (w.angleDelta.y > 0 ? 0.25 : -0.25)));
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
                    font.pixelSize: Theme.type("body")
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }

            // footer with file info and the current zoom
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: (Screenshots.pinnedPath !== "" ? Screenshots.pinnedPath.split("/").pop() : "")
                      + "  ·  " + Math.round(Screenshots.pinZoom * 100) + "%"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.type("caption")
                elide: Text.ElideMiddle
            }
        }
    }

    // bottom-right grip: resize within a sensible minimum
    MouseArea {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Theme.px(22); height: Theme.px(22)
        z: 2
        cursorShape: Qt.SizeFDiagCursor
        property real lastX: 0
        property real lastY: 0
        onPressed: { lastX = mouse.x; lastY = mouse.y; }
        onPositionChanged: if (pressed) {
            win.width = Math.max(win.minW, win.width + mouse.x - lastX);
            win.height = Math.max(win.minH, win.height + mouse.y - lastY);
            lastX = mouse.x; lastY = mouse.y;
        }
    }
}
