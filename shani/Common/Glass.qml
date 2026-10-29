// The translucent card every surface is drawn on. A strong card floats over
// windows (launcher, sidebar, popups, OSD, menus), so it casts a soft shadow;
// a plain one sits on something else and stays flat. "Reduce transparency"
// (Accessibility) makes the charts opaque: content behind never shows through.
import QtQuick
import QtQuick.Effects
import qs.Common

Rectangle {
    property bool strong: false
    property bool lifted: strong
    // the person's view needs the cards readable: opaque, not translucent
    readonly property bool opaque: Settings.data.reduceTransparency
    radius: Theme.radius
    color: strong ? (opaque ? Theme.bg : Theme.glassStrong) : (opaque ? Theme.bg : Theme.glass)
    border.width: 1
    border.color: Theme.stroke

    layer.enabled: lifted
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Theme.shadow
        shadowBlur: 0.9
        shadowVerticalOffset: 6
        shadowHorizontalOffset: 0
        autoPaddingEnabled: true
    }
}
