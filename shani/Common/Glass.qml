// The translucent card every surface is drawn on. A strong card floats over
// windows (launcher, sidebar, popups, OSD, menus), so it casts a soft shadow;
// a plain one sits on something else and stays flat.
import QtQuick
import QtQuick.Effects

Rectangle {
    property bool strong: false
    property bool lifted: strong
    radius: Theme.radius
    color: strong ? Theme.glassStrong : Theme.glass
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
