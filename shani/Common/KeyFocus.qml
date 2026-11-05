// Keyboard (and game controller) reach for anything clickable: put one inside
// the thing, and it takes focus in the surface's tab order, draws the accent
// ring while focused, and turns keys into what a click does.
//   Enter / Space        activated()        (what the click does)
//   Menu / Shift+F10     menu()             (what a right-click does, where there is one)
//   arrows               the next / previous item in reading order; with `columns`
//                        set, Up / Down jump a row (a grid of tiles)
//   Left / Right on a slider (`slider: true`): step(-1 / +1) instead
//   Tab / Shift+Tab      the first item of the next / previous region (an ancestor
//                        whose objectName starts with "region:"), else the next item
//   Escape               not taken: it reaches the surface, which goes back or closes
// The focused item is scrolled into view in the nearest Flickable, and its name is
// Ui.navFocus (the tests read it). One component, so every ring looks the same.
import QtQuick
import qs.Common

Item {
    id: f
    anchors.fill: parent
    // what this stands for, to a screen reader and in Ui.navFocus: the parent's own name
    property string name: parent && parent.Accessible ? parent.Accessible.name : ""
    property int columns: 0
    property bool slider: false
    // items laid out by position rather than in the order they are declared (the
    // tiles): a function giving their Focus items in reading order
    property var ordered: null
    property real radius: parent && parent.radius !== undefined ? parent.radius : Theme.radiusSmall
    signal activated()
    signal menu()
    signal step(int dir)
    activeFocusOnTab: enabled
    Accessible.ignored: true                  // the parent already speaks for itself

    function region(item) {
        for (let p = item; p; p = p.parent)
            if (String(p.objectName).indexOf("region:") === 0)
                return p;
        return null;
    }
    function move(n) {
        if (f.ordered) {
            const list = f.ordered();
            const i = list.indexOf(f);
            if (i >= 0 && i + n >= 0 && i + n < list.length) {
                list[i + n].forceActiveFocus(Qt.TabFocusReason);
                return;
            }
            if (i >= 0)                       // off the grid's edge: on to what comes before or after it
                return (n > 0 ? list[list.length - 1] : list[0]).moveOut(n > 0);
        }
        let it = f;
        for (let i = 0; i < Math.abs(n); i++) {
            const next = it.nextItemInFocusChain(n > 0);
            if (!next || next === f)
                break;
            it = next;
        }
        if (it !== f)
            it.forceActiveFocus(Qt.TabFocusReason);
    }
    // past the last (or before the first) of an ordered set: the chain beyond the whole set
    function moveOut(forward) {
        const set = f.ordered ? f.ordered() : [f];
        let it = f;
        for (let i = 0; i < 400; i++) {
            it = it.nextItemInFocusChain(forward);
            if (!it || it === f)
                return;
            if (set.indexOf(it) < 0) {
                it.forceActiveFocus(Qt.TabFocusReason);
                return;
            }
        }
    }
    function jumpRegion(forward) {
        const mine = region(f);
        let it = f;
        for (let i = 0; i < 400; i++) {
            it = it.nextItemInFocusChain(forward);
            if (!it || it === f)
                return move(forward ? 1 : -1);
            if (region(it) !== mine) {
                if (!forward)                 // to the first item of that region, not its last
                    for (let p = it.nextItemInFocusChain(false); p && p !== f && region(p) === region(it); p = p.nextItemInFocusChain(false))
                        it = p;
                // a grid laid out by position starts at its first place, not its first declared
                const first = it.ordered ? it.ordered()[0] : it;
                (first || it).forceActiveFocus(Qt.TabFocusReason);
                return;
            }
        }
    }
    Keys.onPressed: e => {
        const k = e.key;
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { f.activated(); e.accepted = true; }
        else if (k === Qt.Key_Menu || (k === Qt.Key_F10 && (e.modifiers & Qt.ShiftModifier))) { f.menu(); e.accepted = true; }
        else if (f.slider && (k === Qt.Key_Left || k === Qt.Key_Right)) { f.step(k === Qt.Key_Left ? -1 : 1); e.accepted = true; }
        else if (k === Qt.Key_Down) { f.move(f.columns || 1); e.accepted = true; }
        else if (k === Qt.Key_Up) { f.move(-(f.columns || 1)); e.accepted = true; }
        else if (k === Qt.Key_Right) { f.move(1); e.accepted = true; }
        else if (k === Qt.Key_Left) { f.move(-1); e.accepted = true; }
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { f.jumpRegion(k === Qt.Key_Tab && !(e.modifiers & Qt.ShiftModifier)); e.accepted = true; }
    }
    onActiveFocusChanged: {
        if (!activeFocus)
            return;
        Ui.navFocus = f.name;
        // keep it in view: the nearest Flickable scrolls just enough
        for (let p = f.parent; p; p = p.parent) {
            if (p.contentY !== undefined && p.contentHeight !== undefined && p.contentItem) {
                const r = f.mapToItem(p.contentItem, 0, 0);
                if (r.y < p.contentY)
                    p.contentY = Math.max(0, r.y - 8);
                else if (r.y + f.height > p.contentY + p.height)
                    p.contentY = Math.min(Math.max(0, p.contentHeight - p.height), r.y + f.height - p.height + 8);
                break;
            }
        }
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        visible: f.activeFocus
        radius: f.radius + 3
        color: "transparent"
        border.width: 2
        border.color: Theme.accent
    }
}
