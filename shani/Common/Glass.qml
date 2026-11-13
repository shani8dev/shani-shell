// The translucent card every surface is drawn on. A strong card floats over
// windows (launcher, sidebar, popups, OSD, menus), so it casts a soft shadow;
// a plain one sits on something else and stays flat. "Reduce transparency"
// (Accessibility) makes the charts opaque: content behind never shows through.
//
// `elevation` picks the shadow: "none" / "soft" / "card" / "raised".
// `edge` picks the edge style: "subtle" / "strong" / "none".

// "Reduce transparency" (Accessibility) makes the cards opaque; on battery,
// blurs cost watts — the "Opaque panels on battery" switch does the same then
// (services/Power mirrors the state into Common/PowerState).
import QtQuick
import QtQuick.Effects
import qs.Common

Rectangle {
    property bool strong: false
    property bool lifted: strong
    property string elevation: "card"     // none | soft | card | raised
    property string edge: "subtle"        // subtle | strong | none
    // the person's view needs the cards readable: opaque, not translucent
    readonly property bool opaque: solid || Settings.data.reduceTransparency || (Settings.data.reduceTransparencyOnBattery && PowerState.onBattery)
    // a card over an app's own content (Files' Tidy and rename cards): nothing
    // blurs what is behind it there, so translucent would show text through text
    property bool solid: false
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
