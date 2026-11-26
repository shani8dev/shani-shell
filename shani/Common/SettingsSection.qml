// A titled block of settings, drawn as a Card: the title, an optional hint
// line under it, then the rows. Every Settings page and many apps are built
// from these, so one change here updates them all. Children are the rows;
// each keeps its own Layout.fillWidth.
import QtQuick
import qs.Common

Card {
    id: root
    property string hint: ""
    property bool hintVisible: true
    subtitle: hintVisible ? hint : ""
}
