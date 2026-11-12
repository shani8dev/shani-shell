// A folder picker: quick-pick chips for common locations plus Browse.
// Replaces typing a path. Value is the absolute path ("" = system default).
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: root
    property string value: ""
    property string label: ""
    property string placeholder: ""
    property string folderTarget: "" // not used; for compat
    signal picked(string path)

    Layout.fillWidth: true
    spacing: 6

    readonly property string homeDir: Quickshell.env("HOME") || "/home"

    Text {
        visible: label !== ""
        text: label
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSmall * Theme.fontScale
    }

    // Current value display
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: Theme.radiusToken("xs")
            color: Theme.surface1
            border.color: Theme.stroke
            border.width: 1
            Text {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: Text.AlignVCenter
                text: root.value || (root.placeholder || Tr.t("Not set — pick a folder below"))
                color: root.value ? Theme.text : Theme.faint
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
                elide: Text.ElideMiddle
            }
        }
        Button {
            text: Tr.t("Browse")
            onClicked: {
                // the shell's own chooser (Services/FilePicker): the native
                // dialog is the desktop portal's, and made with every picker
                // it held the whole shell while D-Bus waited for the portal
                if (!Ui.filePicker)
                    return;
                Ui.filePicker.open({
                    "mode": "folder",
                    "title": Tr.t("Choose a folder"),
                    "onPicked": paths => {
                        if (!paths || !paths.length)
                            return;
                        root.value = paths[0];
                        root.picked(paths[0]);
                    }
                });
            }
        }
        Button {
            visible: root.value !== ""
            text: Tr.t("Clear")
            onClicked: {
                root.value = "";
                root.picked("");
            }
        }
    }

    // Quick-pick common folders
    // a label above the chips, not among them: a child as wide as its Flow makes the Flow re-lay out itself forever
    Text { Layout.fillWidth: true; text: Tr.t("Quick picks:"); color: Theme.faint; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [
                { label: Tr.t("Home"), path: homeDir },
                { label: Tr.t("Documents"), path: homeDir + "/Documents" },
                { label: Tr.t("Downloads"), path: homeDir + "/Downloads" },
                { label: Tr.t("Pictures"), path: homeDir + "/Pictures" },
                { label: Tr.t("Pictures/Wallpapers"), path: homeDir + "/Pictures/Wallpapers" },
                { label: Tr.t("Pictures/Screenshots"), path: homeDir + "/Pictures/Screenshots" },
                { label: Tr.t("Videos"), path: homeDir + "/Videos" },
                { label: Tr.t("Videos/Recordings"), path: homeDir + "/Videos/Recordings" },
                { label: Tr.t("Desktop"), path: homeDir + "/Desktop" },
                { label: Tr.t("Public"), path: homeDir + "/Public" }
            ]
            Choice {
                required property var modelData
                text: modelData.label
                selected: root.value === modelData.path
                onClicked: {
                    root.value = modelData.path;
                    root.picked(modelData.path);
                }
            }
        }
        Choice {
            text: Tr.t("Other…")
            selected: root.value !== "" && [homeDir, homeDir + "/Documents", homeDir + "/Downloads", homeDir + "/Pictures", homeDir + "/Pictures/Wallpapers", homeDir + "/Pictures/Screenshots", homeDir + "/Videos", homeDir + "/Videos/Recordings", homeDir + "/Desktop", homeDir + "/Public"].indexOf(root.value) < 0
            onClicked: { }
        }
    }

    // Custom path: type your own
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        TextField {
            id: customPath
            Layout.fillWidth: true
            placeholder: Tr.t("Custom path — type your own (dashed border)")
            border.color: Theme.accentLine
            onAccepted: {
                let p = customPath.text.trim();
                if (p === "") return;
                if (p.indexOf("~") === 0) p = homeDir + p.slice(1);
                root.value = p;
                root.picked(p);
                customPath.text = "";
            }
        }
        Button {
            text: Tr.t("Use")
            onClicked: customPath.accepted()
        }
    }
}
