// Network Tools: a Wi-Fi scan (the networks in range: nmcli/iw - shown as
// "Wi-Fi scan"; its id stays "LAN scan"), ping, DNS (dig +short) and whois, in one
// window. Every command runs through a fixed "sh -c" script with the person's
// input passed as positional arguments ($1, $2); the script text is a literal,
// so a host like "example.com; rm -rf ~" can never become shell code. Hosts are
// checked by validHost() before any command starts, ping counts are clamped,
// and whois/dig/nmcli missing is a note rather than a failure.
// Keyboard: Enter in the host field runs, Ctrl+F / Ctrl+L focus it, Ctrl+R
// reruns the current tool, Esc / Ctrl+W close.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Network Tools"
    visible: Ui.netTools
    onGone: Ui.netTools = false
    implicitWidth: Theme.px(860)
    implicitHeight: Theme.px(640)
    shortcutSearch: hostField.input   // Ctrl+F; Ctrl+L below is the older alias for the same field
    shortcutRefresh: win.refresh      // Ctrl+R reruns the active tool

    property string tool: "LAN scan"    // LAN scan | Ping | DNS | Whois
    property string host: ""
    property int count: 4               // ping packets, 1..10
    property var results: []            // newest first: { tool, target, title, subtitle, detail, when }
    property var history: []            // recent hosts, newest first (kept for compatibility)
    property var toolHistory: ({})      // per-tool recent hosts: tool -> [host], newest first
    property var selected: null
    property string error: ""
    property string note: ""            // "tool not installed" and other graceful notes
    property bool loading: false
    property string activeTool: ""

    // Only a hostname or IPv4 address: letters, digits, dots and internal
    // hyphens. No spaces, quotes, semicolons, $, backticks, slashes or colons
    // can pass, so the value is safe even before it is handed over as $1.
    function validHost(s) {
        const v = String(s || "").trim();
        if (v === "" || v.length > 253) return false;
        if (!/^[A-Za-z0-9.-]+$/.test(v)) return false;
        return v.split(".").every(l => /^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(l));
    }
    function boundedCount(n) {
        const v = parseInt(n, 10);
        return isNaN(v) ? 4 : Math.max(1, Math.min(10, v));
    }
    function addHistory(target) {
        const h = win.history.filter(x => x !== target);
        win.history = [target].concat(h).slice(0, 10);
    }
    function historyFor(tool) { return win.toolHistory[tool] || []; }
    function addToolHistory(tool, target) {
        const kept = win.historyFor(tool).filter(x => x !== target);
        const m = Object.assign({}, win.toolHistory);
        m[tool] = [target].concat(kept).slice(0, 10);
        win.toolHistory = m;
    }
    // We own no the Ui singleton source file flag or shell.qml IPC function, so the prefill travels by
    // clipboard: a caller writes "shani-nettools:<host>" and sets Ui.netTools
    // (the flag shell.qml's netToolsOpen() sets). The marker, not arbitrary
    // clipboard text, is the handoff. Arm only after construction so a shell
    // launch with a stale marker never consumes it: the handoff is taken only
    // when Ui.netTools goes false -> true (visible flips) after completion.
    // The clipboard is left intact — it belongs to the person.
    property bool handoffArmed: false
    function takeHandoff() {
        const marker = "shani-nettools:";
        const raw = String(Quickshell.clipboardText || "").trim();
        if (raw.indexOf(marker) !== 0) return;
        const host = raw.slice(marker.length).trim();
        if (!win.validHost(host)) return;
        win.host = host;
        win.tool = "Ping";
        win.error = "";
    }
    Component.onCompleted: win.handoffArmed = true
    onVisibleChanged: { if (visible && win.handoffArmed) win.takeHandoff(); }
    function collect(kind, target, output) {
        const text = String(output || "");
        const trimmed = text.trim();
        if (trimmed === "NO_TOOLS") { win.note = Tr.t("Neither nmcli nor iw is installed — a Wi-Fi scan needs one of them"); return; }
        if (trimmed === "NO_DIG") { win.note = Tr.t("dig is not installed (install bind to resolve names)"); return; }
        if (trimmed === "NO_WHOIS") { win.note = Tr.t("whois is not installed — install it to look up registrations"); return; }
        if (trimmed === "") return;
        const when = Qt.formatDateTime(new Date(), "HH:mm:ss");
        const rows = [];
        for (const raw of text.split("\n")) {
            if (raw.trim() === "") continue;
            let title = raw.trim(), subtitle = kind;
            if (kind === "LAN scan") {
                const f = raw.split(":");
                title = f[0] || "(hidden network)";
                subtitle = "signal " + (f[1] || "?") + " · " + (f[2] || "unknown") + (f[3] ? " · ch " + f[3] : "");
            }
            rows.push({ tool: kind, target: target, title: title, subtitle: subtitle, detail: raw.trim(), when: when });
        }
        win.results = rows.concat(win.results).slice(0, 200);
    }
    function run(kind) {
        if (win.loading) return;
        win.error = "";
        win.note = "";
        win.selected = null;
        win.activeTool = kind;
        if (kind === "LAN scan") { win.runScan(); return; }
        const target = String(win.host || "").trim();
        if (!win.validHost(target)) { win.error = "Enter a hostname or IPv4 address (letters, digits, dots and hyphens only)"; return; }
        win.addHistory(target);
        win.addToolHistory(kind, target);
        win.loading = true;
        if (kind === "Ping") {
            ping.command = ["sh", "-c", 'timeout 12 ping -c "$1" -W 2 -- "$2" 2>&1 || true', "sh", String(win.boundedCount(win.count)), target];
            ping.running = true;
        } else if (kind === "DNS") {
            dns.command = ["sh", "-c", 'if command -v dig >/dev/null 2>&1; then timeout 8 dig +short "$1" A 2>/dev/null || true; else echo NO_DIG; fi', "sh", target];
            dns.running = true;
        } else if (kind === "Whois") {
            whois.command = ["sh", "-c", 'if command -v whois >/dev/null 2>&1; then timeout 10 whois -- "$1" 2>/dev/null | head -80 || true; else echo NO_WHOIS; fi', "sh", target];
            whois.running = true;
        }
    }
    function runScan() {
        win.loading = true;
        // Fixed script, no interpolated text: only the tools on this machine.
        scan.command = ["sh", "-c", 'if command -v nmcli >/dev/null 2>&1; then nmcli -t -f SSID,SIGNAL,SECURITY,CHAN device wifi list 2>/dev/null | head -60; elif command -v iw >/dev/null 2>&1; then iw dev 2>/dev/null | sed -n "s/^[[:space:]]*SSID: //p" | head -40; else echo NO_TOOLS; fi'];
        scan.running = true;
    }
    function finished(code) {
        win.loading = false;
        if (code !== 0 && win.results.length === 0 && win.note === "")
            win.error = win.activeTool + " failed (exit " + code + ")";
    }
    function exportText() {
        const lines = ["Shani Network Tools — " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss"), ""];
        for (const r of win.results) lines.push("[" + r.tool + "] " + r.target + " (" + r.when + ")\n" + r.detail);
        return lines.join("\n");
    }
    function copyResults() {
        if (win.results.length === 0) return;
        Quickshell.clipboardText = win.results.map(r => "[" + r.tool + "] " + r.target + " — " + r.detail).join("\n");
    }
    // the handoff opens with a host but no results yet: copy the prefilled host
    // so "Copy all" still does something useful from Terminal, Maps or Files
    function copyAll() {
        if (win.results.length === 0) {
            if (win.host) Quickshell.clipboardText = win.host;
            return;
        }
        win.copyResults();
    }
    function copyOne(r) { if (r) Quickshell.clipboardText = r.detail; }
    function exportResults() {
        if (win.results.length === 0) return;
        FilePicker.open({ mode: "save", title: "Export network results", defaultName: "shani-nettools.txt",
                          onPicked: paths => { if (paths.length) { exportView.path = paths[0]; exportView.setText(win.exportText()); } } });
    }
    function focusHost() { hostField.input.forceActiveFocus(); }
    function refresh() { win.run(win.tool); }
    function shortcut(e) {
        // Ctrl+L predates the standard Ctrl+F and is kept as an alias; Escape
        // and Ctrl+W are handled by AppWindow through requestClose().
        if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_L) { win.focusHost(); e.accepted = true; return true; }
        return false;
    }

    Process {
        id: scan
        stdout: StdioCollector { onStreamFinished: win.collect("LAN scan", "local", text) }
        stderr: StdioCollector {}
        onExited: code => win.finished(code)
    }
    Process {
        id: ping
        stdout: StdioCollector { onStreamFinished: win.collect("Ping", String(win.host || "").trim(), text) }
        stderr: StdioCollector {}
        onExited: code => win.finished(code)
    }
    Process {
        id: dns
        stdout: StdioCollector { onStreamFinished: win.collect("DNS", String(win.host || "").trim(), text) }
        stderr: StdioCollector {}
        onExited: code => win.finished(code)
    }
    Process {
        id: whois
        stdout: StdioCollector { onStreamFinished: win.collect("Whois", String(win.host || "").trim(), text) }
        stderr: StdioCollector {}
        onExited: code => win.finished(code)
    }
    FileView {
        id: exportView
        path: ""
        atomicWrites: true
        printErrors: false
    }

    tools: [
        IconButton { size: Theme.px(30); icon: "edit-copy"; tip: "Copy all"; accessibleName: "Copy all results"; enabled: win.results.length > 0 || win.host !== ""; onClicked: win.copyAll() },
        IconButton { size: Theme.px(30); icon: "document-save"; tip: "Export results"; accessibleName: "Export results"; enabled: win.results.length > 0; onClicked: win.exportResults() }
    ]

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onPressed: e => { if (win.shortcut(e)) e.accepted = true; }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            spacing: Theme.px(8)

            InfoBanner {
                Layout.fillWidth: true
                visible: win.error !== ""
                tone: "error"
                text: win.error
                accessibleRole: Accessible.AlertMessage
                Button { text: Tr.t("Dismiss"); flat: true; onClicked: win.error = "" }
            }
            InfoBanner {
                Layout.fillWidth: true
                visible: win.note !== ""
                tone: "warn"
                text: win.note
                accessibleRole: Accessible.AlertMessage
                Button { text: Tr.t("Dismiss"); flat: true; onClicked: win.note = "" }
            }
            BusyNote {
                Layout.fillWidth: true
                visible: win.loading
                note: win.activeTool + "…"
                iconSize: Theme.px(16)
            }

            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [{ id: "LAN scan", label: Tr.t("Wi-Fi scan") }, { id: "Ping", label: "Ping" }, { id: "DNS", label: "DNS" }, { id: "Whois", label: "Whois" }]
                    Choice {
                        required property var modelData
                        text: modelData.label
                        selected: win.tool === modelData.id
                        onClicked: win.tool = modelData.id
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: win.tool !== "LAN scan"
                spacing: Theme.px(8)
                TextField {
                    id: hostField
                    Layout.fillWidth: true
                    placeholder: "hostname or IPv4 address"
                    label: "Host name or IPv4 address"
                    text: win.host
                    error: win.error !== "" && !win.validHost(win.host) ? "Use letters, digits, dots and hyphens" : ""
                    onTextChanged: win.host = text
                    onAccepted: win.run(win.tool)
                }
                TextField {
                    visible: win.tool === "Ping"
                    Layout.preferredWidth: Theme.px(80)
                    placeholder: "count"
                    label: "Ping count, 1 to 10"
                    mode: "digits"
                    text: String(win.count)
                    input.validator: IntValidator { bottom: 1; top: 10 }
                    onTextChanged: win.count = win.boundedCount(text)
                    onAccepted: win.run("Ping")
                }
                Button {
                    text: "Run " + win.tool
                    kind: "primary"
                    enabled: !win.loading
                    busy: win.loading
                    onClicked: win.run(win.tool)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: win.historyFor(win.tool).length > 0
                spacing: Theme.px(6)
                Text {
                    text: "Recent:"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                Flickable {
                    Layout.fillWidth: true
                    contentWidth: historyRow.implicitWidth
                    contentHeight: Math.max(height, historyRow.implicitHeight)
                    height: Math.max(Theme.px(30), Theme.touchTarget)
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    Row {
                        id: historyRow
                        spacing: Theme.px(6)
                        Repeater {
                            model: win.historyFor(win.tool)
                            Choice {
                                required property var modelData
                                text: modelData
                                selected: false
                                onClicked: { win.host = modelData; win.run(win.tool); }
                            }
                        }
                    }
                }
            }

            EmptyState {
                visible: win.results.length === 0 && !win.loading && win.error === ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                icon: "network-workgroup"
                title: "No results yet"
                subtitle: Tr.t("See the Wi-Fi networks in range, or run a ping, DNS or whois lookup")
                actionText: "Run " + win.tool
                onAction: win.run(win.tool)
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.results.length > 0
                clip: true
                contentHeight: resultCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: resultCol
                    width: parent.width
                    spacing: Theme.px(4)
                    Repeater {
                        model: win.results
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: modelData.tool === "Ping" ? "network-transmit-receive"
                                : modelData.tool === "DNS" ? "network-server"
                                : modelData.tool === "Whois" ? "contact-new" : "network-wireless"
                            title: modelData.title
                            subtitle: modelData.tool + " · " + modelData.target + " · " + modelData.when + (modelData.subtitle !== modelData.tool ? " · " + modelData.subtitle : "")
                            selected: win.selected && win.selected.detail === modelData.detail && win.selected.when === modelData.when
                            onClicked: win.selected = modelData
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: win.selected !== null
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.stroke
                implicitHeight: detailCol.implicitHeight + Theme.px(16)
                ColumnLayout {
                    id: detailCol
                    anchors.fill: parent
                    anchors.margins: Theme.px(8)
                    spacing: Theme.px(6)
                    Text {
                        Layout.fillWidth: true
                        text: win.selected ? win.selected.tool + " · " + win.selected.target : ""
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: win.selected ? win.selected.detail : ""
                        color: Theme.dim
                        wrapMode: Text.Wrap
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Button { text: Tr.t("Copy this result"); flat: true; onClicked: win.copyOne(win.selected) }
                        Button { text: Tr.t("Close details"); flat: true; onClicked: win.selected = null }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: win.results.length + " results · Enter runs · Ctrl+F/L focuses the host · Ctrl+R reruns · Esc closes"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
        }
    }
}
