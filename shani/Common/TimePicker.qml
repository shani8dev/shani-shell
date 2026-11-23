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
    spacing: Theme.px(6)

    readonly property string hour: value.split(":")[0] || "19"
    readonly property string minute: value.split(":")[1] || "00"
    readonly property bool ampm: !Settings.data.use24h
    readonly property int hour24: parseInt(hour, 10) || 0
    readonly property int ampmHour: hour24 % 12 === 0 ? 12 : hour24 % 12
    readonly property bool isPm: hour24 >= 12

    // HH:MM or a spoken time: "9am", "9:30 pm", "21:00". Returns [hour, minute]
    // or null when it is not a time; no date is stored by this picker.
    function parseTime(text) {
        const s = String(text || "").trim().toLowerCase().replace(/\s+/g, "");
        let m = /^(\d{1,2})(?::(\d{2}))?(am|pm)$/.exec(s);
        if (!m) m = /^(\d{1,2}):(\d{2})$/.exec(s);
        if (!m) return null;
        let h = parseInt(m[1], 10), mi = m[2] ? parseInt(m[2], 10) : 0;
        if (m[3]) {
            if (h < 1 || h > 12) return null;
            h = (h % 12) + (m[3] === "pm" ? 12 : 0);
        }
        return h <= 23 && mi <= 59 ? [h, mi] : null;
    }

    function set(h, m) {
        const time = String(h).padStart(2, "0") + ":" + String(m).padStart(2, "0");
        root.value = time;
        root.picked(time);
    }
    // what the picker shows: 12h with AM/PM when the clock preference is 12h,
    // but value/set() stay 24h "HH:MM" throughout
    function display() {
        if (!ampm) return value;
        return ampmHour + ":" + String(minute).padStart(2, "0") + (isPm ? " " + Tr.t("PM") : " " + Tr.t("AM"));
    }
    function formatPreset(p) {
        if (!ampm) return p;
        const parts = p.split(":");
        const h = parseInt(parts[0], 10);
        const hh = h % 12 === 0 ? 12 : h % 12;
        return hh + ":" + parts[1] + (h >= 12 ? " " + Tr.t("PM") : " " + Tr.t("AM"));
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
        spacing: Theme.px(8)

        ColumnLayout {
            spacing: Theme.px(4)
            Layout.fillWidth: true
            Text { text: Tr.t("Hour"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Repeater {
                    model: root.ampm ? [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
                                     : [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]
                    Choice {
                        required property int modelData
                        text: root.ampm ? String(modelData) : String(modelData).padStart(2, "0")
                        selected: root.ampm ? root.ampmHour === modelData : parseInt(root.hour, 10) === modelData
                        onClicked: {
                            const h = root.ampm ? (modelData % 12) + (root.isPm ? 12 : 0) : modelData;
                            root.set(h, parseInt(root.minute, 10) || 0);
                        }
                    }
                }
            }
            RowLayout {
                visible: root.ampm
                spacing: Theme.px(6)
                Choice {
                    text: Tr.t("AM"); selected: !root.isPm
                    onClicked: root.set(root.hour24 % 12, parseInt(root.minute, 10) || 0)
                }
                Choice {
                    text: Tr.t("PM"); selected: root.isPm
                    onClicked: root.set((root.hour24 % 12) + 12, parseInt(root.minute, 10) || 0)
                }
            }
        }

        ColumnLayout {
            spacing: Theme.px(4)
            Layout.fillWidth: true
            Text { text: Tr.t("Minute"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(4)
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
        spacing: Theme.px(6)
        Text { text: root.display(); color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; font.weight: Font.DemiBold }
        Text { text: Tr.t("· tap to change"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
    }

    // Custom: type your own (validated)
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        TextField {
            id: customField
            Layout.fillWidth: true
            placeholder: Tr.t("Custom — HH:MM or 9am")
            onAccepted: {
                const parsed = root.parseTime(customField.text);
                if (parsed) {
                    root.set(parsed[0], parsed[1]);
                    customField.text = "";
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
    Text { Layout.fillWidth: true; text: Tr.t("Common times:"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Repeater {
            model: ["07:00", "09:00", "17:00", "19:00", "21:00", "22:00"]
            Choice {
                required property string modelData
                text: root.formatPreset(modelData)
                selected: root.value === modelData
                onClicked: root.set(modelData.split(":")[0], modelData.split(":")[1])
            }
        }
    }
}
