// Settings > About: read the shipped release notes here, in the shell, instead
// of sending the markdown file to xdg-open. Older versions in the same file sit
// behind one disclosure; the machine's details stay in SettingsAbout.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services as Services

ColumnLayout {
    id: page
    Layout.fillWidth: true
    spacing: Theme.px(8)

    readonly property var sections: Services.ReleaseNotes.splitVersions(Services.ReleaseNotes.text)
    readonly property bool empty: Services.ReleaseNotes.loaded && !Services.ReleaseNotes.failed && Services.ReleaseNotes.text.trim() === ""
    property bool showPast: false

    // One honest line for loading, failure and an empty file; the reader itself
    // only appears once there is something to read.
    Text {
        Layout.fillWidth: true
        visible: !Services.ReleaseNotes.loaded || Services.ReleaseNotes.failed || page.empty
        text: !Services.ReleaseNotes.loaded ? Tr.t("Loading…")
            : Services.ReleaseNotes.failed ? Tr.t("Release notes are not installed on this computer.")
            : Tr.t("No release notes yet.")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.type("body")
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }
    Button {
        visible: Services.ReleaseNotes.failed
        flat: true
        text: Tr.t("Retry")
        onClicked: Services.ReleaseNotes.reload()
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.px(240)
        visible: Services.ReleaseNotes.loaded && !Services.ReleaseNotes.failed && !page.empty
        color: Theme.surface1
        radius: Theme.radiusSmall
        border.width: 1
        border.color: Theme.stroke
        Accessible.role: Accessible.StaticText
        Accessible.name: Tr.t("What changed")

        Flickable {
            id: notesFlick
            anchors.fill: parent
            anchors.margins: Theme.px(10)
            clip: true
            contentHeight: body.implicitHeight
            Keys.onUpPressed: notesFlick.scroll(-1)
            Keys.onDownPressed: notesFlick.scroll(1)
            function scroll(dir) {
                contentY = dir < 0 ? Math.max(0, contentY - Theme.px(48))
                                   : Math.min(contentHeight - height, contentY + Theme.px(48));
            }
            Column {
                id: body
                width: notesFlick.width
                spacing: Theme.px(6)
                Repeater {
                    model: page.showPast ? page.sections : page.sections.slice(0, 1)
                    delegate: Column {
                        id: section
                        required property var modelData
                        readonly property var note: modelData
                        width: parent.width
                        spacing: Theme.px(6)
                        Text {
                            visible: section.note.label !== ""
                            width: parent.width
                            text: section.note.label
                            color: Theme.text
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: Theme.type("heading")
                            font.weight: Font.DemiBold
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }
                        Repeater {
                            model: Services.ReleaseNotes.parseRows(section.note.md)
                            delegate: Row {
                                required property var modelData
                                width: parent.width
                                spacing: Theme.px(6)
                                Text {
                                    id: marker
                                    text: "•"
                                    visible: modelData.kind === "bullet"
                                    color: Theme.accent
                                    font.family: Theme.font
                                    font.pixelSize: Theme.type("body")
                                    Accessible.ignored: true
                                }
                                Text {
                                    width: parent.width - (marker.visible ? marker.implicitWidth + parent.spacing : 0)
                                    text: modelData.text
                                    color: modelData.kind === "heading" ? Theme.text : Theme.dim
                                    wrapMode: Text.Wrap
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(modelData.kind !== "heading" ? 12 : (modelData.level <= 1 ? 15 : 13)) * Theme.fontScale
                                    font.weight: modelData.kind === "heading" ? Font.DemiBold : Font.Normal
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: text
                                }
                            }
                        }
                    }
                }
            }
        }
        // Enter takes keyboard focus into the notes; Up/Down then scroll them.
        KeyFocus {
            name: Tr.t("What changed")
            onActivated: notesFlick.forceActiveFocus()
        }
    }

    // Only a file with more than one version gets a past-notes disclosure.
    Button {
        visible: page.sections.length > 1
        flat: true
        text: page.showPast ? Tr.t("Show only the latest notes") : Tr.t("See all past notes")
        Accessible.name: text
        onClicked: page.showPast = !page.showPast
    }
}
