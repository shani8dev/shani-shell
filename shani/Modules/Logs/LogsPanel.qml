// The Logs surface: the systemd journal (journalctl --no-pager -o json) in a
// panel. Category filter (all / kernel / user / app / hardware), text search,
// click a row for the full entry, tail-follow toggle. Lazy: the journal is
// only read while the panel is open — nothing runs while it is closed.
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.logs && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-logs"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurRegion : null
    Region { id: blurRegion; item: card; radius: Theme.radiusLarge }

    // parsed journal entries: [{ time, pri, cat, unit, id, msg, cursor, raw }]
    property var entries: []
    property string journalError: ""        // "" when the last read worked
    property string filter: "all"           // all | kernel | user | app | hardware
    property string query: ""
    property bool follow: true
    property var selected: null             // the entry shown in the details area

    // --- categorisation (heuristic, documented): -----------------------------
    //   kernel   — the journal's _TRANSPORT is "kernel"
    //   hardware — udev / device-ish units and services (udevd, udisks,
    //              NetworkManager, bluetoothd, alsa, drm, firmware, nvme…):
    //              the system side of devices, rather than an application
    //   user     — a per-user / session unit (_SYSTEMD_USER_UNIT set) or a
    //              session scope; everything a session runs as the person
    //   app      — everything else (system services and apps logging here)
    function categorize(e) {
        const transport = e._TRANSPORT || "";
        const id = String(e.SYSLOG_IDENTIFIER || "");
        const unit = String(e._SYSTEMD_UNIT || e._SYSTEMD_USER_UNIT || "");
        const msg = String(e.MESSAGE || "");
        if (transport === "kernel")
            return "kernel";
        if (/udev|udisks|NetworkManager|bluetooth|alsa|pulse|drm|firmware|nvme|ahci|usb|pci|acpi|i2c|gpu/i.test(id + " " + unit + " " + msg))
            return "hardware";
        if (e._SYSTEMD_USER_UNIT !== undefined && e._SYSTEMD_USER_UNIT !== "" && e._SYSTEMD_USER_UNIT !== null)
            return "user";
        if (/session-|user\.slice|user-\d+\.slice|graphical-session|desktop|wayland|niri|chrome|firefox|vivaldi|foot|bash|zsh/i.test(unit + " " + id))
            return "user";
        return "app";
    }
    function priLabel(p) {
        return p === "0" || p === "1" || p === "2" ? "error" : p === "3" ? "warning"
            : p === "4" ? "notice" : p === "5" || p === "6" ? "info" : "debug";
    }
    function priColor(p) {
        return p === "0" || p === "1" || p === "2" ? Theme.red : p === "3" ? Theme.amber : Theme.dim;
    }
    function fmtTime(e) {
        const us = Number(e.__REALTIME_TIMESTAMP || 0);
        if (!us) return "--:--:--";
        const d = new Date(us / 1000);
        return Qt.formatDateTime(d, "HH:mm:ss");
    }
    readonly property var shown: {
        const q = String(win.query || "").toLowerCase();
        return win.entries.filter(e =>
            (win.filter === "all" || e.cat === win.filter)
            && (q === "" || (String(e.msg || "") + " " + String(e.id || "") + " " + String(e.unit || "")).toLowerCase().indexOf(q) >= 0));
    }

    function readJournal() {
        if (!win.visible)
            return;
        // 200 most recent entries; the Process is the only thing that runs,
        // and only while the panel is open (onVisibleChanged + follow timer).
        journal.command = ["journalctl", "--no-pager", "--no-hostname", "-n", "200", "-o", "json"];
        journal.running = true;
    }
    onVisibleChanged: if (visible) { readJournal(); Qt.callLater(() => searchInput.input.forceActiveFocus(Qt.TabFocusReason)); }
    Timer {
        interval: 3000
        running: win.visible && win.follow
        repeat: true
        onTriggered: win.readJournal()
    }

    Process {
        id: journal
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const out = [];
                    const body = String(text || "").trim();
                    if (body !== "") {
                        for (const line of body.split("\n")) {
                            if (!line.trim()) continue;
                            try {
                                const e = JSON.parse(line);
                                out.push({
                                    time: win.fmtTime(e),
                                    pri: String(e.PRIORITY === undefined ? "6" : e.PRIORITY),
                                    cat: win.categorize(e),
                                    unit: e._SYSTEMD_UNIT || e._SYSTEMD_USER_UNIT || "",
                                    id: e.SYSLOG_IDENTIFIER || "",
                                    msg: e.MESSAGE || "",
                                    cursor: e.__CURSOR || "",
                                    raw: e
                                });
                            } catch (err) {}
                        }
                    }
                    win.entries = out;
                    win.journalError = out.length ? "" : "empty";
                } catch (e) {
                    win.entries = [];
                    win.journalError = "unreadable";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: { if (String(text || "").trim() !== "") win.journalError = String(text || "").trim().split("\n")[0]; }
        }
        onExited: code => { if (code !== 0 && win.journalError === "") win.journalError = "unreadable"; }
    }

    MouseArea { anchors.fill: parent; onClicked: Ui.logs = false }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.logs = false }

    Glass {
        id: card
        anchors.centerIn: parent
        width: 460
        implicitHeight: Math.min(parent.height - 80, col.implicitHeight + 32)
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Logs — systemd journal") }
                IconButton { icon: "view-refresh"; size: 28; tip: Tr.t("Refresh"); onClicked: win.readJournal() }
                IconButton { icon: "window-close"; size: 28; tip: Tr.t("Close"); onClicked: Ui.logs = false }
            }

            // category filter: all | kernel | user | app | hardware
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [{ id: "all", label: "All" }, { id: "kernel", label: "Kernel" }, { id: "user", label: "User" }, { id: "app", label: "App" }, { id: "hardware", label: "Hardware" }]
                    Choice {
                        required property var modelData
                        text: modelData.label
                        selected: win.filter === modelData.id
                        onClicked: win.filter = modelData.id
                    }
                }
            }

            TextField {
                id: searchInput
                Layout.fillWidth: true
                placeholder: Tr.t("Search the journal…")
                label: Tr.t("Search the journal")
                text: win.query
                onTextChanged: win.query = text
            }

            SwitchRow {
                Layout.fillWidth: true
                text: Tr.t("Follow (tail)")
                hint: Tr.t("Keep reading new entries while this is open")
                checked: win.follow
                onToggled: on => win.follow = on
            }

            // fallback: journal empty or unreadable
            EmptyState {
                Layout.fillWidth: true
                visible: win.entries.length === 0
                icon: "dialog-warning-symbolic"
                title: Tr.t("No logs available")
                subtitle: win.journalError === "empty" ? Tr.t("The journal is empty right now — entries appear as the system logs them")
                    : win.journalError !== "" ? Tr.t("The journal could not be read: %1").arg(win.journalError)
                    : Tr.t("The journal is empty or unreadable — try Refresh")
                actionText: Tr.t("Refresh")
                onAction: win.readJournal()
            }

            Flickable {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(260, Math.max(60, listCol.implicitHeight + 4))
                Layout.minimumHeight: 60
                contentHeight: listCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: listCol
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: win.shown.slice(0, 100)
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: modelData.pri === "0" || modelData.pri === "1" || modelData.pri === "2" ? "dialog-error"
                                : modelData.pri === "3" ? "dialog-warning" : "log-viewer"
                            title: modelData.time + "  " + (modelData.id || modelData.unit || "—") + "  " + win.priLabel(modelData.pri)
                            subtitle: String(modelData.msg || "").slice(0, 140)
                            selected: win.selected && win.selected.cursor === modelData.cursor
                            onClicked: win.selected = modelData
                        }
                    }
                }
            }

            // details for the clicked row
            Rectangle {
                visible: win.selected !== null
                Layout.fillWidth: true
                implicitHeight: detailCol.implicitHeight + 16
                radius: 10
                color: Theme.surface1
                border.width: 1
                border.color: Theme.stroke
                Column {
                    id: detailCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4
                    Text {
                        width: parent.width
                        text: win.selected ? (win.selected.time + " · " + win.selected.cat + " · " + win.selected.unit + " · " + win.selected.id) : ""
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        text: win.selected ? String(win.selected.msg || "") : ""
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        text: win.selected ? JSON.stringify(win.selected.raw || {}) : ""
                        color: Theme.dim
                        font.family: Theme.mono
                        font.pixelSize: 9 * Theme.fontScale
                        wrapMode: Text.Wrap
                    }
                    Button {
                        text: Tr.t("Close details")
                        kind: "plain"
                        onClicked: win.selected = null
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("%1 shown · Esc closes").arg(win.shown.length)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: Ui.logs = false }
}
