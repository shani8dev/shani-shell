// A round icon button: hover and press states, optional "on" fill.
// Press gives a scale-down + ripple; hover brightens.
import QtQuick

Rectangle {
    id: root
    property string icon
    property bool on: false
    property real size: Theme.px(32)
    property color iconColor: on ? Theme.accentInk : Theme.text
    property string tip: ""
    signal clicked()
    signal rightClicked()
    signal pressAndHold()               // a long press: the window-layout picker on the bar's maximise
    property bool hasMenu: false           // a right-click does something: the Menu key (a pad's X) too
    property string accessibleName: ""     // overrides the tip as the AT-SPI name, when the tip is a hint rather than a label

    // for screen readers: a button named after what it does
    Accessible.role: Accessible.Button
    readonly property var plainNames: ({ "go-previous": "Previous", "go-next": "Next", "go-up": "Move up", "go-down": "Move down",
        "media-skip-backward": "Previous track", "media-skip-forward": "Next track", "media-playback-start": "Play", "media-playback-pause": "Pause",
        "window-close": "Close", "view-refresh": "Refresh", "list-remove": "Remove", "list-add": "Add", "edit-clear-all": "Clear all",
        "edit-delete": "Delete", "view-more": "More", "notifications-disabled": "Do Not Disturb", "preferences-system-notifications": "Do Not Disturb",
        "media-eject": "Eject", "folder-publicshare": "Share", "chat-message-new": "Summarise", "draw-eraser": "Eraser",
        "edit-undo": "Undo", "document-new": "New", "document-save": "Save", "view-paged": "QR code", "preferences-system": "Settings",
        "window-new": "Open", "insert-image-symbolic": "Insert image" })
    Accessible.name: root.accessibleName !== "" ? root.accessibleName : root.tip !== "" ? root.tip : (plainNames[root.icon.replace(/-symbolic$/, "")] || root.icon.replace(/-symbolic$/, "").replace(/-/g, " "))
    Accessible.checkable: true
    Accessible.checked: root.on
    Accessible.onPressAction: root.clicked()

    implicitWidth: Math.max(size, Theme.touchTarget)
    implicitHeight: Math.max(size, Theme.touchTarget)
    radius: Math.min(width, height) / 2
    clip: true

    // ---- base fill ---------------------------------------------------------
    color: {
        if (on) return Theme.accent
        if (area.pressed) return Theme.pressed
        if (area.containsMouse) return Theme.hover
        return "transparent"
    }
    Behavior on color { ColorAnimation { duration: Theme.anim } }

    // ---- ripple on press ---------------------------------------------------
    Rectangle {
        id: ripple
        width: 0; height: 0
        radius: width / 2
        color: Theme.text
        opacity: area.pressed ? 0.20 : 0
        Behavior on width { NumberAnimation { duration: Theme.mot(260); easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: Theme.mot(260); easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.mot(260); easing.type: Easing.OutCubic } }
        // centre on the press point (or the button when idle); grows outward
        x: (area.pressed ? area.mouseX : parent.width / 2) - width / 2
        y: (area.pressed ? area.mouseY : parent.height / 2) - height / 2
    }

    // ---- subtle scale-down on press ---------------------------------------
    transform: Scale {
        origin.x: area.pressed ? area.mouseX : width / 2
        origin.y: area.pressed ? area.mouseY : height / 2
        xScale: area.pressed ? 0.94 : 1
        yScale: area.pressed ? 0.94 : 1
        Behavior on xScale { NumberAnimation { duration: Theme.mot(120) } }
        Behavior on yScale { NumberAnimation { duration: Theme.mot(120) } }
    }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: root.size * 0.55
        color: root.iconColor
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        enabled: root.enabled
        onPressed: { ripple.width = root.width * 2.4; ripple.height = ripple.width; pressTimer.restart() }
        onReleased: { ripple.width = 0; ripple.height = 0; pressTimer.stop() }
        onClicked: e => e.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }
    // a long press fires pressAndHold once; releasing before it fires is a click
    Timer { id: pressTimer; interval: 500; onTriggered: root.pressAndHold() }
    // keyboard and controller: Enter / Space click, the Menu key right-clicks
    KeyFocus { enabled: root.enabled && root.visible; menuable: root.hasMenu; onActivated: root.clicked(); onMenu: root.rightClicked() }
    // what it is, on hover: the tip, else the name a screen reader says
    Hint { text: root.tip !== "" ? root.tip : root.Accessible.name }
}
