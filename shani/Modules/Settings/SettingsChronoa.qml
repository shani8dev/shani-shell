// Settings > Chronoa: the assistant's own settings live in Chronoa (model,
// voice, wake word, what it may do) — opened from here; the Island's part of
// it is the shell's.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    readonly property var d: Settings.data

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Chronoa") }
    Text {
        Layout.fillWidth: true
        text: Chronoa.state !== "offline" ? "Chronoa is running." : "Chronoa is not running — the Island waits for it."
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Button {
        text: Tr.t("Chronoa's settings — model, voice, wake word, permissions")
        // its own window, through its GApplication action; started first if needed
        onClicked: {
            Ui.closeAll();
            Quickshell.execDetached(["sh", "-c", 'gapplication action dev.shani.chronoa open-settings 2>/dev/null || { (shani-chronoa >/dev/null 2>&1 &); sleep 3; gapplication action dev.shani.chronoa open-settings; }']);
        }
    }
    SectionTitle { Layout.fillWidth: true; text: Tr.t("The Island") }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Show what is going on")
        hint: Tr.t("a timer, music, a recording, a suggestion after copying — in the Island while Chronoa is idle")
        checked: page.d.islandActivities
        onToggled: on => page.d.islandActivities = on
    }
    Text {
        Layout.fillWidth: true
        text: Tr.t("Super+A opens Chronoa; Super+S reads part of the screen with Lens; Ctrl+Enter in the launcher asks it anything.")
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
