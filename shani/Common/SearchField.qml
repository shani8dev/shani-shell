// A search box: the shared TextField plus a clear button that refocuses it.
// Defaults are additive — a plain field with no search action still works.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property alias text: field.text
    property alias input: field.input          // callers' Ctrl+F focus keeps working
    property string placeholder: ""
    property string label: root.placeholder
    property bool showClear: true
    signal cleared()

    implicitWidth: Theme.px(180)
    implicitHeight: field.implicitHeight
    color: "transparent"
    Accessible.name: root.label || root.placeholder

    TextField {
        id: field
        anchors { left: parent.left; right: clear.left; rightMargin: Theme.px(4); top: parent.top; bottom: parent.bottom }
        placeholder: root.placeholder
        label: root.label
    }
    IconButton {
        id: clear
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        visible: root.showClear && root.text !== ""
        icon: "edit-clear"
        size: Theme.px(22)
        tip: Tr.t("Clear search")
        accessibleName: Tr.t("Clear search")
        onClicked: { field.text = ""; field.input.forceActiveFocus(); root.cleared(); }
    }
}
