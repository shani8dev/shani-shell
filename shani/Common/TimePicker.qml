// A time-of-day picker: chips for hour and minute, no typing.
// Value is "HH:MM" — the same string Settings uses everywhere.
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: root
    property string value: "19:00"
    property string label: ""
    signal picked(string time)

    Layout.fillWidth: true
    spacing: 6

    readonly property string hour: value.split(":")[0] || "19"
    readonly property string minute: value.split(":")[1] || "00"

    function set(h, m) {
        const time = String(h).padStart(2, "0") + ":" + String(m).padStart(2, "0");
        root.value = time;
        root.picked(time);
    }

    Text {
        visible: label !== ""
        text: label
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSmall * Theme.fontScale
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        ColumnLayout {
            spacing: 4
            Layout.fillWidth: true
            Text { text: Tr.t("Hour"); color: Theme.faint; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]
                    Choice {
                        required property int modelData
                        text: String(modelData).padStart(2, "0")
                        selected: parseInt(root.hour, 10) === modelData
                        onClicked: root.set(modelData, parseInt(root.minute, 10) || 0)
                    }
                }
            }
        }

        ColumnLayout {
            spacing: 4
            Layout.fillWidth: true
            Text { text: Tr.t("Minute"); color: Theme.faint; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]
                    Choice {
                        required property int modelData
                        text: String(modelData).padStart(2, "0")
                        selected: parseInt(root.minute, 10) === modelData
                        onClicked: root.set(parseInt(root.hour, 10) || 0, modelData)
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text { text: root.value; color: Theme.accent; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; font.weight: Font.DemiBold }
        Text { text: Tr.t("· tap to change"); color: Theme.faint; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
    }

    // Custom: type your own (validated)
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        TextField {
            id: customField
            Layout.fillWidth: true
            placeholder: Tr.t("Custom — HH:MM, e.g. 23:45")
            onAccepted: {
                const t = customField.text.trim();
                if (/^\d\d?:\d\d$/.test(t)) {
                    const parts = t.split(":");
                    const h = parseInt(parts[0], 10);
                    const m = parseInt(parts[1], 10);
                    if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
                        root.set(h, m);
                        customField.text = "";
                    }
                }
            }
        }
        Button {
            text: Tr.t("Use")
            onClicked: customField.accepted()
        }
    }

    // Quick presets for common schedules
    // a label above the chips, not among them: a child as wide as its Flow makes the Flow re-lay out itself forever
    Text { Layout.fillWidth: true; text: Tr.t("Common times:"); color: Theme.faint; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: ["07:00", "09:00", "17:00", "19:00", "21:00", "22:00"]
            Choice {
                required property string modelData
                text: modelData
                selected: root.value === modelData
                onClicked: root.set(modelData.split(":")[0], modelData.split(":")[1])
            }
        }
    }
}
