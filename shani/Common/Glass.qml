// The translucent card every surface is drawn on. A strong card floats over
// windows (launcher, sidebar, popups, OSD, menus), so it casts a soft shadow;
// a plain one sits on something else and stays flat. "Reduce transparency"
// (Accessibility) makes the charts opaque: content behind never shows through.
//
// `elevation` picks the shadow: "none" / "soft" / "card" / "raised".
// `edge` picks the edge style: "subtle" / "strong" / "none".
import QtQuick
import QtQuick.Effects
import qs.Common

Rectangle {
    property bool strong: false
    property bool lifted: strong
    property string elevation: "card"     // none | soft | card | raised
    property string edge: "subtle"        // subtle | strong | none
    // the person's view needs the cards readable: opaque, not translucent
    readonly property bool opaque: Settings.data.reduceTransparency
    radius: Theme.radius
    color: strong ? (opaque ? Theme.bg : Theme.glassStrong) : (opaque ? Theme.bg : Theme.glass)
    border.width: edge === "strong" ? 1 : (edge === "subtle" ? 0.5 : 0)
    border.color: Theme.stroke

    layer.enabled: lifted
    layer.effect: MultiEffect {
        enabled: elevation !== "none"
        shadowEnabled: true
        shadowColor: elevation === "soft" ? Theme.shadowSoft
                     : elevation === "raised" ? Theme.shadowRaised
                     : Theme.shadowCard
        shadowBlur: elevation === "soft" ? 0.6 : (elevation === "raised" ? 1.4 : 0.9)
        shadowVerticalOffset: elevation === "raised" ? 8 : 6
        shadowHorizontalOffset: 0
        autoPaddingEnabled: true
    }
}
