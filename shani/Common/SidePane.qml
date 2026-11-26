// An app window's sidebar that folds into a drawer on a narrow window (a phone,
// a small split): wide, it is a column beside the content, as before; narrow,
// it takes no room and slides in from the left over the content when `open`
// (the window header's menu button, Common/AppWindow `sidePane`), and a tap
// beside it closes it. One way for every app, so a phone gets the whole width
// for what it is showing.
//
//   SidePane { id: places; compact: win.compact; paneWidth: Theme.px(176)
//              ColumnLayout { anchors.fill: parent; ... } }
// and on the window, sidePane set to that id (the header's menu button, when narrow)
import QtQuick
import QtQuick.Layouts
import qs.Common

Item {
    id: pane
    property bool compact: false
    property bool open: false
    property real paneWidth: Theme.px(176)
    property string label: Tr.t("Places")      // what the header's button says it opens
    default property alias content: holder.data

    z: compact ? 50 : 0
    Layout.preferredWidth: compact ? 0 : paneWidth
    Layout.maximumWidth: compact ? 0 : paneWidth
    Layout.fillWidth: false
    Layout.fillHeight: true
    onCompactChanged: open = false
    Accessible.role: Accessible.Pane
    Accessible.name: label

    // beside the open drawer: dims the content, and a tap there closes it
    Rectangle {
        visible: pane.compact && pane.open
        x: holder.width
        width: pane.Window.width
        height: pane.height
        color: Theme.alpha(Theme.bg, 0.55)
        MouseArea { anchors.fill: parent; onClicked: pane.open = false }
        KeyFocus { name: Tr.t("Close %1", pane.label); onActivated: pane.open = false }
    }
    // the drawer's own ground, so the content does not show through it
    Rectangle {
        visible: pane.compact && holder.visible
        x: holder.x
        width: holder.width
        height: pane.height
        radius: Theme.radiusSmall
        color: Theme.bg
        border.width: 1
        border.color: Theme.stroke
    }
    Item {
        id: holder
        width: pane.compact ? Math.min(pane.Window.width * 0.82, Theme.px(300)) : pane.paneWidth
        height: pane.height
        x: !pane.compact ? 0 : (pane.open ? 0 : -width - Theme.px(12))
        visible: !pane.compact || pane.open || slide.running
        Behavior on x { NumberAnimation { id: slide; duration: Theme.anim; easing.type: Easing.OutCubic } }
    }
}
