// The Applications folder: the shell's app grid as a soft-wrap categorised
// grid — folders as chips, search-all and per-app tags reach it, and the
// user's own order is the folder they arranged it into.
//
// Why these live here: the launcher's results are one long flat list; this is
// the same apps drawn as one coherent grid the detail panel below opens from.
import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

Item {
    id: root
    // the shell's visible apps (AppFilter honours parental limits)
    readonly property var model: DesktopEntries.applications.values.filter(a => !a.noDisplay && AppFilter.allowed(a.id))
    // user state: per-app tags (app id -> [tag, ...]) and the user's order
    property var tags: ({})
    property var order: []
    property string filter: ""              // search-all text
    property string category: ""            // folder chip, "" = All

    readonly property bool narrow: root.width < Theme.px(600)
    // the highlighted app (selected by the user, shared with the detail panel)
    property var selected: null
    // drag reorder state: the tile being dragged
    property int dragFrom: -1

    // ---- folders: the categories the grid can wrap into ---------------------
    readonly property var folders: ["Internet", "Office", "Graphics", "AudioVideo", "Development", "Utility", "System", "Game", "Other"]
    // the freedesktop category is Network, the folder people look in is Internet
    readonly property var folderAliases: ({ Network: "Internet" })
    function folderOf(a) {
        for (const c of (a.categories || [])) {
            const name = String(c).replace(/;+$/, "").trim()
            const folder = root.folderAliases[name] || name
            for (const f of root.folders)
                if (folder.toLowerCase() === f.toLowerCase())
                    return f
        }
        return "Other"
    }

    // ---- tags ----------------------------------------------------------------
    // a tag = something the person wrote on the app (root.tags), or a
    // category of the entry that is not itself a folder chip
    function tagsOf(a) {
        const mine = root.tags[a.id] || []
        const fromEntry = ((a.categories || []).map(c => String(c).replace(/;+$/, "").trim()))
            .filter(c => c && !root.folders.some(f => f.toLowerCase() === c.toLowerCase()) && !root.folderAliases[c])
        const out = []
        for (const t of mine.concat(fromEntry))
            if (t && out.indexOf(t) < 0) out.push(t)
        return out
    }
    function tagCloud() {
        const counts = {}
        for (const a of root.visibleApps)
            for (const t of root.tagsOf(a))
                counts[t] = (counts[t] || 0) + 1
        return Object.keys(counts).sort((x, y) => counts[y] - counts[x] || x.localeCompare(y))
    }
    // drag reorder: move an app's id within root.order (ids not in order go last)
    function moveItem(from, to) {
        const arr = root.order.slice()
        const at = arr.indexOf(from)
        const m = at >= 0 ? arr.splice(at, 1)[0] : from
        const t = arr.indexOf(to)
        if (t >= 0) arr.splice(t, 0, m)
        else arr.push(m)
        root.order = arr
    }

    // ---- search-all ----------------------------------------------------------
    function matches(a, t) {
        const s = [a.name, a.genericName, a.comment].join(" ") + " "
            + [].concat(a.keywords || []).join(" ") + " " + root.tagsOf(a).join(" ")
        return !t || s.toLowerCase().indexOf(t) >= 0
    }
    function searchAll(q) {
        return root.model.filter(a => root.matches(a, String(q || "").trim().toLowerCase()))
    }
    readonly property var visibleApps: {
        const byCat = root.model.filter(a => root.category === "" || root.folderOf(a) === root.category)
        const ordered = []
        for (const id of root.order) { const a = byCat.find(x => x.id === id); if (a) ordered.push(a) }
        const rest = byCat.filter(a => ordered.indexOf(a) < 0)
        const t = root.filter.trim().toLowerCase()
        return ordered.concat(rest).filter(a => root.matches(a, t))
    }

    // ---- drawing ----------------------------------------------------------------
    GridLayout {
        id: grid
        anchors.fill: parent
        columnSpacing: Theme.px(8)
        rowSpacing: Theme.px(8)
        // soft wrap: a narrow screen draws one column at a time, wide ones fill
        columns: root.narrow ? 1 : Math.max(1, Math.min(Math.floor(grid.width / Theme.px(118)), 8))
        Repeater {
            model: root.visibleApps
            Rectangle {
                id: tile
                required property var modelData
                required property int index
                Layout.preferredWidth: Theme.px(118)
                Layout.fillHeight: true
                implicitHeight: Theme.px(110)
                radius: Theme.px(16)
                color: root.selected === tile.modelData ? Theme.accentSoft : "transparent"
                Accessible.role: Accessible.ListItem
                Accessible.name: (tile.modelData.name || "") + (root.tagsOf(tile.modelData).length ? ", " + root.tagsOf(tile.modelData).join(", ") : "")
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - Theme.px(16)
                    spacing: Theme.px(6)
                    IconImage {
                        Layout.alignment: Qt.AlignHCenter
                        implicitSize: 40
                        source: Quickshell.iconPath(tile.modelData.icon, "application-x-executable")
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.modelData.name
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        visible: root.tagsOf(tile.modelData).length > 0
                        text: root.tagsOf(tile.modelData).join(", ")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected = tile.modelData
                }
                // drag reorder: remember the tile while the drag is active;
                // moveItem(from, to) puts it back in place on release
                DragHandler {
                    onActiveChanged: if (active) root.dragFrom = tile.index
                }
            }
        }
    }
}
