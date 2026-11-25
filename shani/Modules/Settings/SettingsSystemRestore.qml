// System Restore: the blue-green slot switch shani-deploy already owns.
// This panel reads its status and asks for a two-tap confirmation before
// handing the rollback to `pkexec shani-deploy --rollback`. It never restores
// individual files - that stays in Backup's snapshot timeline.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: panel
    objectName: "system-restore-panel"
    // the label search uses (SettingsIndex's "System restore") names this panel
    Accessible.name: Tr.t("System restore")
    property bool active: false
    property int selected: -1
    property string confirming: ""        // a slot armed by the first tap
    focus: active
    spacing: Theme.px(10)

    onActiveChanged: if (active) SystemRestore.refresh()
    Component.onCompleted: if (active) SystemRestore.refresh()

    function stateLabel(slot) {
        return slot.state === "active" ? Tr.t("Running now")
            : slot.state === "passive" ? Tr.t("Previous system · kept for rollback")
            : Tr.t("Other system");
    }
    function labelFor(slot) {
        return Tr.t("Slot %1, %2%3", slot.id, stateLabel(slot),
            slot.date ? ", " + slot.date : "");
    }
    function arm(slot) {
        panel.selected = SystemRestore.slots.indexOf(slot);
        if (panel.confirming === slot.id) {
            panel.confirming = "";
            SystemRestore.switchSlot(slot.id);
        } else {
            panel.confirming = slot.id;   // first tap only arms; nothing runs yet
        }
    }
    function armPrevious() {
        const id = SystemRestore.previousSlot;
        if (!id) return;
        if (panel.confirming === id) {
            panel.confirming = "";
            SystemRestore.restorePrevious();
        } else {
            panel.confirming = id;
        }
    }
    // A panel, not an AppWindow: Escape unwinds the armed tap here, Ctrl+R
    // refreshes the slots. Ctrl+F (search) and Ctrl+W (close) belong to the
    // hosting Settings window — a Ctrl+W here would close that whole window.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { panel.confirming = ""; event.accepted = true; }
        else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
            SystemRestore.refresh(); event.accepted = true;
        }
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && panel.selected >= 0
                 && panel.selected < SystemRestore.slots.length) {
            const slot = SystemRestore.slots[panel.selected];
            if (slot.state === "passive") panel.arm(slot);
            event.accepted = true;
        }
        else if (event.key === Qt.Key_1 && SystemRestore.slots.length > 0) {
            panel.selected = 0; event.accepted = true;
        }
        else if (event.key === Qt.Key_2 && SystemRestore.slots.length > 1) {
            panel.selected = 1; event.accepted = true;
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        spacing: Theme.px(10)
        title: Tr.t("Roll back to the previous slot")
        Text {
            objectName: "system-restore-scope"
            Layout.fillWidth: true
            text: Tr.t("Restoring here means a blue-green slot switch: the next boot starts from the other system. It does not restore individual files — that stays in Backup.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }

    // read states: error / offline / empty all say plainly what happened
    InfoBanner {
        objectName: "system-restore-error"
        Layout.fillWidth: true
        visible: SystemRestore.error !== ""
        tone: "error"
        iconName: "dialog-error"
        title: Tr.t("Could not load slots")
        text: SystemRestore.error
        accessibleRole: Accessible.StatusBar
    }
    InfoBanner {
        objectName: "system-restore-offline"
        Layout.fillWidth: true
        visible: SystemRestore.error !== "" && panel.active
        tone: "warn"
        text: Tr.t("System slots are unavailable; nothing here can be switched until shani-deploy answers.")
    }
    EmptyState {
        objectName: "system-restore-empty"
        Layout.fillWidth: true
        visible: !SystemRestore.loading && SystemRestore.error === "" && SystemRestore.slots.length === 0
        icon: "system-software-update"
        title: Tr.t("Nothing yet")
        subtitle: SystemRestore.note || Tr.t("No installed slots were reported.")
        actionText: Tr.t("Refresh slots")
        onAction: SystemRestore.refresh()
    }
    InfoBanner {
        objectName: "system-restore-note"
        Layout.fillWidth: true
        visible: SystemRestore.note !== ""
        tone: "accent"
        text: SystemRestore.note
        accessibleRole: Accessible.StatusBar
    }
    // restart/update status lives in SettingsUpdates (Services/Updates) above;
    // this panel only owns the slot switch and its rollback actions

    // slot cards: active / inactive / passive, with whatever metadata exists
    Repeater {
        model: SystemRestore.slots
        delegate: Rectangle {
            required property var modelData
            required property int index
            objectName: "system-restore-slot-" + modelData.id
            Layout.fillWidth: true
            height: Theme.px(74)
            radius: Theme.radiusSmall
            color: panel.selected === index ? Theme.hover : "transparent"
            border.width: panel.selected === index ? 2 : 1
            border.color: modelData.state === "active" ? Theme.accent : Theme.dim
            Accessible.name: panel.labelFor(modelData)

            MouseArea {
                anchors.fill: parent
                onClicked: { panel.selected = index; panel.forceActiveFocus(); }
            }
            KeyFocus { onActivated: { panel.selected = index; } }
            ColumnLayout {
                anchors { fill: parent; margins: Theme.px(10) }
                spacing: Theme.px(2)
                Text {
                    Layout.fillWidth: true
                    text: panel.stateLabel(modelData) + (modelData.id ? "  ·  " + modelData.id : "")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    visible: modelData.date !== "" || modelData.size !== "" || modelData.health !== ""
                    text: [modelData.date, modelData.size, modelData.health,
                        modelData.pending ? Tr.t("starts after restart") : ""].filter(function (x) { return x; }).join("  ·  ")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                Button {
                    Layout.alignment: Qt.AlignLeft
                    visible: modelData.state === "passive"
                    enabled: !SystemRestore.busy && !SystemRestore.error
                    busy: SystemRestore.busy
                    kind: panel.confirming === modelData.id ? "danger" : "outline"
                    text: panel.confirming === modelData.id
                        ? Tr.t("Tap again to switch to slot %1", modelData.id)
                        : Tr.t("Go back to slot %1", modelData.id)
                    Accessible.name: text
                    onClicked: panel.arm(modelData)
                }
            }
        }
    }

    // progress / busy; the action streams shani-deploy's own lines
    InfoBanner {
        objectName: "system-restore-busy"
        Layout.fillWidth: true
        visible: SystemRestore.busy
        tone: "accent"
        text: Tr.t("Asking shani-deploy to switch slots…")
    }
    InfoBanner {
        objectName: "system-restore-action-error"
        Layout.fillWidth: true
        visible: SystemRestore.actionError !== ""
        tone: "error"
        title: Tr.t("Could not switch slots")
        text: SystemRestore.actionError
        accessibleRole: Accessible.StatusBar
    }
    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(120, SystemRestore.progress.length * 16 + 8)
        visible: SystemRestore.progress.length > 0
        clip: true
        model: SystemRestore.progress
        delegate: Text {
            required property string modelData
            width: ListView.view.width
            text: modelData
            color: Theme.dim
            elide: Text.ElideLeft
            font.family: Theme.mono
            font.pixelSize: Theme.px(10) * Theme.fontScale
        }
    }

    // dry-run preview only when the tool actually advertises one
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        visible: SystemRestore.dryRunSupported || SystemRestore.previewLines.length > 0
        Button {
            text: Tr.t("Preview (dry run)")
            enabled: !SystemRestore.busy
            onClicked: SystemRestore.preview()
        }
        Item { Layout.fillWidth: true }
    }
    InfoBanner {
        objectName: "system-restore-no-dry-run"
        Layout.fillWidth: true
        visible: !SystemRestore.dryRunSupported
        tone: "info"
        text: Tr.t("This shani-deploy has no dry run for a slot switch; the target and confirmation above are the preview.")
    }
    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(120, SystemRestore.previewLines.length * 16 + 8)
        visible: SystemRestore.previewLines.length > 0
        clip: true
        model: SystemRestore.previewLines
        delegate: Text {
            required property string modelData
            width: ListView.view.width
            text: modelData
            color: Theme.dim
            elide: Text.ElideLeft
            font.family: Theme.mono
            font.pixelSize: Theme.px(10) * Theme.fontScale
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Button {
            text: Tr.t("Refresh slots")
            enabled: !SystemRestore.busy && !SystemRestore.loading
            onClicked: SystemRestore.refresh()
        }
        Item { Layout.fillWidth: true }
        Button {
            objectName: "system-restore-go-back"
            enabled: SystemRestore.previousSlot !== "" && !SystemRestore.busy && !SystemRestore.error
            busy: SystemRestore.busy
            kind: panel.confirming === SystemRestore.previousSlot ? "danger" : "primary"
            text: panel.confirming === SystemRestore.previousSlot
                ? Tr.t("Tap again to go back")
                : Tr.t("Go back to previous system")
            Accessible.name: text
            onClicked: panel.armPrevious()
        }
    }
    }
}
