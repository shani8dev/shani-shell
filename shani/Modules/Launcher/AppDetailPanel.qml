// The right detail panel for the Applications folder: the selected app's
// details — icon, name, description, keywords and tags (add one here), and
// Open to launch it. Deep preview: the full entry the grid shows.
import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

Item {
    id: root
    property var selected: null        // the app entry (DesktopEntry) previewed
    property var tags: ({})            // id -> [tag, ...], the panel's own map
    property string newTag: ""        // what is typed into the add-tag field

    function tagsOf(a) {
        const e = a || root.selected
        return ((root.tags[(e || {}).id] || []).slice())
    }
    function addTag() {
        const e = root.selected
        const t = root.newTag.trim()
        if (!e || !t) return
        const mine = root.tagsOf(e)
        if (mine.indexOf(t) < 0) root.tags[e.id] = mine.concat([t])
        root.newTag = ""
    }
    function removeTag(a, t) {
        const e = a || root.selected
        if (!e || !t) return
        root.tags[e.id] = root.tagsOf(e).filter(x => x !== t)
    }
    function open(a) {
        Launch.app((a || root.selected || {}).id)
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: Theme.px(12)

        IconImage {
            Layout.alignment: Qt.AlignHCenter
            implicitSize: 64
            source: Quickshell.iconPath(root.selected ? root.selected.icon : "", "application-x-executable")
        }
        Text {
            Layout.fillWidth: true
            text: root.selected ? root.selected.name : ""
            Accessible.name: root.selected ? root.selected.name : ""
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.type("heading")
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            Layout.fillWidth: true
            text: root.selected ? (root.selected.genericName || root.selected.comment || "") : ""
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
            wrapMode: Text.Wrap
        }
        // the app's keywords, and its tags as removable chips
        Text {
            Layout.fillWidth: true
            text: [].concat(root.selected ? root.selected.keywords || [] : []).join(" ")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.type("small")
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            Repeater {
                model: root.tagsOf(root.selected)
                Item {
                    required property var modelData
                    height: Theme.px(22)
                    Layout.preferredWidth: chip.implicitWidth + Theme.px(8)
                    Rectangle {
                        id: chip
                        anchors.fill: parent
                        radius: Theme.px(8)
                        color: Theme.alpha(Theme.accent, 0.12)
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.removeTag(root.selected, modelData)
                        }
                        Text {
                            anchors.centerIn: parent
                            text: modelData + " ✕"
                            color: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: Theme.type("small")
                        }
                    }
                }
            }
        }
        // add a tag to the selected app
        RowLayout {
            Layout.fillWidth: true
            TextField {
                id: tagField
                Layout.fillWidth: true
                placeholderText: Tr.t("New tag…")
                text: root.newTag
                onAccepted: root.addTag()
            }
            Button { text: Tr.t("Add tag"); onClicked: root.addTag() }
        }
        Button {
            text: Tr.t("Open")
            kind: "primary"
            onClicked: root.open()
        }
    }
}
