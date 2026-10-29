// A quick-settings tile: icon, title, state line. Click toggles; tiles with a
// detail view grow a chevron that opens it below the grid.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property string tid               // its id in Settings.tileOrder / hiddenTiles
    property bool can: true           // whether it can work on this machine
    property string icon
    property string title
    property string subtitle: ""
    property bool on: false
    property bool hasDetail: false
    property bool expanded: false
    signal toggled()
    signal detail()

    // arranging (the grid's edit mode): a tap shows or hides it, a drag moves it
    readonly property bool editing: !!parent && parent.editing === true
    readonly property bool hiddenNow: Settings.data.hiddenTiles.indexOf(tid) >= 0
    function activate() { if (editing) parent.toggleHidden(tid); else toggled(); }

    Accessible.role: Accessible.CheckBox
    Accessible.name: editing ? root.title + ", " + (hiddenNow ? Tr.t("hidden") : Tr.t("shown")) : root.title
    Accessible.description: editing ? Tr.t("Press to show or hide; drag to move") : root.subtitle
    Accessible.checkable: true
    Accessible.checked: editing ? !hiddenNow : root.on
    Accessible.onPressAction: root.activate()
    Accessible.onToggleAction: root.activate()
    opacity: editing && hiddenNow ? 0.45 : 1
    Behavior on opacity { NumberAnimation { duration: Theme.anim } }

    implicitHeight: 58
    height: 58
    // the grid places it: by id, in the person's order, only if it can work here
    onCanChanged: report()
    Component.onCompleted: report()
    function report() {
        if (!parent || parent.can === undefined)
            return;
        const c = Object.assign({}, parent.can);
        c[tid] = can;
        parent.can = c;
    }
    Connections {
        target: parent
        ignoreUnknownSignals: true
        function onShownChanged() { parent.place(root); }
        function onEditingChanged() { parent.place(root); }
        function onWidthChanged() { parent.place(root); }
    }
    radius: 14
    // off: a tint of the text colour, so a tile reads as a tile on a light panel too
    color: on ? Theme.accent : Theme.alpha(Theme.text, area.containsMouse ? 0.11 : 0.065)
    border.width: 1
    border.color: expanded ? Theme.accentLine : on ? "transparent" : Theme.alpha(Theme.text, 0.06)
    Behavior on color { ColorAnimation { duration: Theme.anim } }

    readonly property color ink: on ? Theme.accentInk : Theme.text

    Icon {
        id: ic
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        size: 20
        color: root.ink
    }
    Column {
        anchors.left: ic.right
        anchors.leftMargin: 10
        anchors.right: chevron.visible ? chevron.left : parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
            width: parent.width
            text: root.title
            color: root.ink
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 12 * Theme.fontScale
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.subtitle
            color: root.on ? Theme.alpha(Theme.accentInk, 0.75) : Theme.dim
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 10 * Theme.fontScale
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => root.editing ? root.activate() : (e.button === Qt.RightButton && root.hasDetail) ? root.detail() : root.toggled()
        drag.target: root.editing ? root : null
        drag.threshold: 6
        preventStealing: root.editing      // the sidebar's scrolling would take the drag
        onPressed: if (root.editing) root.z = 10
        onReleased: {
            root.z = 0;
            if (root.editing && drag.active === false && moved) root.parent.dropTile(root);
            moved = false;
        }
        property bool moved: false
        drag.onActiveChanged: if (drag.active) moved = true
    }
    // in edit mode: a badge, − to hide or + to show
    Rectangle {
        visible: root.editing
        width: 18
        height: 18
        radius: 9
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: -4
        color: root.hiddenNow ? Theme.accent : Theme.surface3
        border.width: 1
        border.color: Theme.stroke
        Text {
            anchors.centerIn: parent
            text: root.hiddenNow ? "+" : "−"
            color: root.hiddenNow ? Theme.accentInk : Theme.text
            font.pixelSize: 13 * Theme.fontScale
            font.weight: Font.DemiBold
        }
    }

    Rectangle {
        id: chevron
        visible: root.hasDetail && !root.editing
        width: 26
        height: parent.height - 12
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        radius: 9
        color: chevArea.containsMouse ? Theme.alpha(root.ink, 0.15) : "transparent"
        Text {
            anchors.centerIn: parent
            text: root.expanded ? "▾" : "›"
            color: root.ink
            font.pixelSize: 15 * Theme.fontScale
        }
        MouseArea {
            id: chevArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.detail()
        }
    }
}
