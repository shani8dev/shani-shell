// The answer first (docs/DESIGN.md): what a screen is about, in one line, at
// the top - "Everything looks good", "Backed up yesterday at 21:04" - with
// the state's glyph, a line of detail, a few checks as chips, and the one
// thing to do about it on the right. Narrow, the parts stack.
//
//   StatusHero { tone: "ok"; overline: Tr.t("Backups"); headline: Tr.t("Backed up yesterday")
//                detail: Tr.t("Your home folder, on Archive SSD"); chips: [Tr.t("Restore tested")]
//                actions: [ Button { text: Tr.t("Back up now"); kind: "primary" } ] }
import QtQuick
import QtQuick.Layouts
import qs.Common

Rectangle {
    id: root
    property string tone: "ok"              // ok | warn | error | info | busy
    property string overline: ""
    property string headline: ""
    property string detail: ""
    property var chips: []                  // short facts that hold, shown with a check
    property alias actions: actionRow.data
    readonly property color toneColor: Theme.toneColor(tone === "busy" ? "info" : tone)
    readonly property bool compact: width > 0 && width < Theme.px(560)

    Accessible.role: Accessible.StaticText
    Accessible.name: [overline, headline, detail].concat(chips).filter(s => s !== "").join(". ")

    implicitWidth: Theme.px(640)
    implicitHeight: grid.implicitHeight + Theme.space(compact ? 8 : 12)
    radius: Theme.radiusLarge + Theme.px(4)
    border.width: 1
    border.color: Theme.alpha(toneColor, 0.35)
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Qt.tint(Theme.card, Theme.alpha(root.toneColor, 0.26)) }
        GradientStop { position: 1; color: Qt.tint(Theme.card, Theme.alpha(root.toneColor, 0.06)) }
    }

    GridLayout {
        id: grid
        anchors.fill: parent
        anchors.margins: Theme.space(root.compact ? 4 : 6)
        columns: root.compact ? 1 : 3
        columnSpacing: Theme.space(6)
        rowSpacing: Theme.space(4)

        Item {
            implicitWidth: Theme.px(root.compact ? 48 : 72)
            implicitHeight: implicitWidth
            Layout.alignment: Qt.AlignVCenter
            StatusGlyph { anchors.centerIn: parent; visible: root.tone !== "busy"; tone: root.tone; size: parent.width }
            Spinner { anchors.centerIn: parent; visible: root.tone === "busy"; size: parent.width * 0.6; color: root.toneColor }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space(1)
            Text {
                Layout.fillWidth: true
                visible: root.overline !== ""
                text: root.overline
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("caption")
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
            }
            Text {
                Layout.fillWidth: true
                text: root.headline
                color: Theme.text
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.type(root.compact ? "subtitle" : "title")
                font.weight: Font.Bold
                Accessible.role: Accessible.Heading
                Accessible.name: root.headline
            }
            Text {
                Layout.fillWidth: true
                visible: root.detail !== ""
                text: root.detail
                color: Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.type("body")
            }
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space(2)
                visible: root.chips.length > 0
                spacing: Theme.space(2)
                Repeater {
                    model: root.chips
                    StatusPill { required property var modelData; tone: root.tone === "busy" ? "info" : root.tone; text: modelData }
                }
            }
        }
        RowLayout {
            id: actionRow
            Layout.alignment: root.compact ? Qt.AlignLeft : (Qt.AlignRight | Qt.AlignVCenter)
            spacing: Theme.space(2)
        }
    }
}
