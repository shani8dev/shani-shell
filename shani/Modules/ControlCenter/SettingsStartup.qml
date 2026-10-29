// Settings > Default apps > Startup apps: what starts at login (XDG
// autostart, which niri's session runs) — the system's and the person's.
// Turning a system one off writes a copy with Hidden=true into
// ~/.config/autostart (the XDG way, as GNOME does); adding one copies the
// app's own desktop file there. Also: where screenshots are saved.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    readonly property var d: Settings.data
    readonly property string userDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/autostart"
    property var entries: []              // [{ file, name, on, mine }]
    onActiveChanged: if (active) refresh()
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) refresh()
    function refresh() { list.running = true; }

    // one line each: file<TAB>name<TAB>hidden(true|false)<TAB>user|system — the user's copy wins
    Process {
        id: list
        command: ["sh", "-c", 'u="$1"; for f in "$u"/*.desktop /etc/xdg/autostart/*.desktop; do [ -f "$f" ] || continue
                b=${f##*/}; case "$f" in /etc/*) [ -f "$u/$b" ] && continue; src=system;; *) src=user;; esac
                n=$(sed -n "s/^Name=//p" "$f" | head -1); h=$(grep -qiE "^Hidden=true|^X-GNOME-Autostart-enabled=false" "$f" && echo true || echo false)
                printf "%s\\t%s\\t%s\\t%s\\n" "$b" "${n:-$b}" "$h" "$src"; done', "sh", page.userDir]
        stdout: StdioCollector {
            onStreamFinished: page.entries = text.trim().split("\n").filter(x => x).map(l => {
                const f = l.split("\t");
                return { file: f[0], name: f[1], on: f[2] !== "true", mine: f[3] === "user" };
            }).sort((a, b) => a.name.localeCompare(b.name))
        }
    }
    Process { id: change; onExited: page.refresh() }
    function setOn(e, on) {
        // a system entry: a user copy, hidden or not; a user entry: edited in place
        change.command = ["sh", "-c", 'u="$1"; f="$2"; mkdir -p "$u"; [ -f "$u/$f" ] || cp "/etc/xdg/autostart/$f" "$u/$f"
            sed -i "/^Hidden=/d; /^X-GNOME-Autostart-enabled=/d" "$u/$f"; [ "$3" = off ] && printf "Hidden=true\\n" >> "$u/$f"; true', "sh", userDir, e.file, on ? "on" : "off"];
        change.running = true;
    }
    function remove(e) {
        change.command = ["rm", "-f", userDir + "/" + e.file];
        change.running = true;
    }
    function add(app) {
        // the app's own desktop file, wherever XDG keeps it
        change.command = ["sh", "-c", 'u="$1"; id="$2"; mkdir -p "$u"; for d in "${XDG_DATA_HOME:-$HOME/.local/share}" $(echo "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | tr ":" " "); do
                f="$d/applications/$id.desktop"; [ -f "$f" ] && { cp "$f" "$u/$id.desktop"; exit 0; }; done; exit 1', "sh", userDir, app.id];
        change.running = true;
        find.text = "";
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Apps open when you signed out") }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [{ id: "ask", label: Tr.t("Offer to reopen them") }, { id: "always", label: Tr.t("Reopen them") }, { id: "never", label: Tr.t("Start fresh") }]
            Choice {
                required property var modelData
                text: modelData.label
                selected: page.d.reopenApps === modelData.id
                onClicked: page.d.reopenApps = modelData.id
            }
        }
    }
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Startup apps") }
    Repeater {
        model: page.entries
        RowLayout {
            id: row
            required property var modelData
            Layout.fillWidth: true
            SwitchRow {
                Layout.fillWidth: true
                text: row.modelData.name
                hint: row.modelData.mine ? "added by you" : "the system's"
                checked: row.modelData.on
                onToggled: on => page.setOn(row.modelData, on)
            }
            IconButton {
                visible: row.modelData.mine
                icon: "edit-delete"
                size: 24
                Accessible.name: "Remove " + row.modelData.name + " from startup"
                onClicked: page.remove(row.modelData)
            }
        }
    }
    TextField { id: find; Layout.fillWidth: true; placeholder: Tr.t("Add an app to start at login…") }
    Repeater {
        model: find.text.trim().length < 2 ? [] : DesktopEntries.applications.values
            .filter(a => !a.noDisplay && a.name.toLowerCase().indexOf(find.text.trim().toLowerCase()) >= 0).slice(0, 6)
        ListRow {
            required property var modelData
            Layout.fillWidth: true
            icon: modelData.icon || "application-x-executable"
            title: modelData.name
            subtitle: Tr.t("start at login")
            onClicked: page.add(modelData)
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Screenshots") }
    TextField {
        Layout.fillWidth: true
        placeholder: "Saved to " + page.d.screenshotDir + " — type another folder"
        onAccepted: if (text.trim() !== "") { page.d.screenshotDir = text.trim().replace(/\/$/, ""); text = ""; }
    }
}
