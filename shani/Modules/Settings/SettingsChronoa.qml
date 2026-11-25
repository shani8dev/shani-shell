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
    spacing: Theme.px(12)
    readonly property var d: Settings.data

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Chronoa")
        hint: Chronoa.state !== "offline" ? "Chronoa is running." : "Chronoa is not running — the Island waits for it."

        SwitchRow {
            Layout.fillWidth: true
            text: Tr.t("Enable Chronoa")
            hint: Tr.t("Start the local assistant at login. When off, the Island still shows what is going on but Chronoa does not answer.")
            checked: Settings.data.chronoaEnabled !== false
            onToggled: on => {
                Settings.data.chronoaEnabled = on;
                if (on) Quickshell.execDetached(["shani-chronoa"]);
                else Quickshell.execDetached(["pkill", "-f", "shani-chronoa"]);
            }
        }
        Button {
            kind: "outline"
            text: Tr.t("Chronoa's settings — model, voice, wake word, permissions")
            // its own window, through its GApplication action; started first if needed
            onClicked: {
                Ui.closeAll();
                Quickshell.execDetached(["sh", "-c", 'gapplication action dev.shani.chronoa open-settings 2>/dev/null || { (shani-chronoa >/dev/null 2>&1 &); sleep 3; gapplication action dev.shani.chronoa open-settings; }']);
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("The Island")

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
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
    }
}
