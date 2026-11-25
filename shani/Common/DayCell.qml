// One day in a calendar grid: DatePicker, the sidebar calendar and the Calendar
// app's month and week views. One look for every calendar in the shell:
//   selected   accent fill, accent ink
//   today      soft accent fill, accent text (still visible when also selected)
//   week no.   faint, not a button
// The copies had drifted: today was a solid accent square in the sidebar, a
// hover tint with a border in the date picker, and a soft tint in the app; and
// the date picker's days had no spoken name at all.
//
// Extra marks (event dots) go inside as children; they sit over the label.
import QtQuick
import qs.Common

Rectangle {
    id: cell
    property string label: ""
    property var date: null              // the day shown: its spoken name
    property bool isToday: false
    property bool isSelected: false
    property bool isWeek: false          // a week-number cell
    property bool interactive: !isWeek && label !== ""
    property real fontSize: Theme.px(11)
    default property alias content: overlay.data
    signal activated()

    implicitHeight: Theme.px(30)
    radius: Theme.radiusSmall
    color: isSelected ? Theme.accent
         : isToday ? Theme.accentSoft
         : interactive && area.containsMouse ? Theme.hover
         : "transparent"

    Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
    Accessible.ignored: label === ""     // the blanks before the 1st
    Accessible.name: isWeek ? Tr.t("Week %1").arg(label)
                   : (date ? Qt.formatDate(date, "dddd d MMMM yyyy") : label)
                     + (isToday ? " (" + Tr.t("today") + ")" : "")
    Accessible.onPressAction: if (interactive) activated()

    Text {
        anchors.centerIn: parent
        text: cell.label
        color: cell.isSelected ? Theme.accentInk
             : cell.isWeek ? Theme.faint
             : cell.isToday ? Theme.accent
             : Theme.text
        font.family: Theme.font
        font.pixelSize: cell.fontSize * Theme.fontScale
        font.weight: cell.isSelected || cell.isToday ? Font.DemiBold : Font.Normal
        Accessible.ignored: true
    }
    Item { id: overlay; anchors.fill: parent }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: cell.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cell.activated()
    }
    KeyFocus { enabled: cell.interactive; onActivated: cell.activated() }
}
