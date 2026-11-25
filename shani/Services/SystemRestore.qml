pragma Singleton
// System restore is a blue-green slot switch owned by shani-deploy. This
// service only reads `shani-deploy --status` (no root, no deploy lock) and
// hands a confirmed action back to `pkexec shani-deploy --rollback`. It does
// not restore files - that stays in Backup.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    property bool available: false
    property bool loading: false
    property string error: ""                 // the read failed (tool missing / non-zero)
    property string note: ""                  // an honest, non-fatal explanation
    property var slots: []                    // [{id, date, size, health, state, pending}]
    property string activeSlot: ""            // the slot this machine booted from
    property string previousSlot: ""          // the known-good slot kept for rollback
    property string currentSlot: ""           // the slot shani-deploy will boot next
    property string version: ""
    property string channel: ""
    property bool rebootNeeded: false
    property bool upgradePending: false
    property string bootFailure: ""

    // ---- action state -------------------------------------------------------
    property bool busy: false
    property var progress: []                 // last lines of shani-deploy, newest last
    property string actionError: ""
    property bool dryRunSupported: false
    property var previewLines: []

    function refresh() {
        root.loading = true;
        root.error = "";
        root.note = "";
        root.slots = [];
        status.running = false;
        status.running = true;
    }

    // ---- parser:begin -------------------------------------------------------
    // Tolerant on purpose: shani-deploy's --status is a human-readable table
    // today and `--status --json` a machine-readable contract. Unknown lines
    // are ignored; nothing is guessed from a slot's mere existence.
    function parseStatus(text) {
        const s = String(text == null ? "" : text).trim();
        const out = {
            slots: [], activeSlot: "", previousSlot: "", currentSlot: "",
            version: "", channel: "", rebootNeeded: false, upgradePending: false,
            bootFailure: "", parsed: false, note: ""
        };
        if (s === "") return out;

        let d = null;
        if (/^\s*\{/.test(s)) {
            try { d = JSON.parse(s); } catch (e) { d = null; }
        }
        if (d && !Array.isArray(d)) {
            out.parsed = true;
            out.activeSlot = String(d.booted_slot || "");
            out.previousSlot = String(d.previous_slot || "");
            out.currentSlot = String(d.current_slot || "");
            out.version = String(d.version || "");
            out.channel = String(d.channel || "");
            out.rebootNeeded = !!(d.reboot_needed || (d.boot_markers && d.boot_markers.reboot_needed));
            out.upgradePending = !!(d.update_available || d.candidate_boot || out.rebootNeeded);
            out.bootFailure = String(d.boot_failure || "");
            [out.activeSlot, out.previousSlot, out.currentSlot].forEach(function (id) {
                if (id && !out.slots.some(function (x) { return x.id === id; }))
                    out.slots.push({ id: id, date: "", size: "", health: "", state: "inactive", pending: false });
            });
        } else {
            String(s).split("\n").forEach(function (raw) {
                const line = String(raw).replace(/\r$/, "");
                const m = line.match(/^\s*slot\s+([A-Za-z0-9][A-Za-z0-9._-]*)\b(.*)$/i);
                if (m) {
                    const rest = m[2] || "";
                    const slot = {
                        id: m[1],
                        date: (rest.match(/\d{4}[.-]\d{1,2}[.-]\d{1,2}/) || [""])[0],
                        size: (rest.match(/\d+(?:\.\d+)?\s*(?:[KMGT]i?B)\b/i) || [""])[0],
                        health: (rest.match(/\b(?:verified|healthy|good|ok)\b/i) || [""])[0],
                        state: "inactive",
                        pending: false
                    };
                    if (/\bactive\b/i.test(rest)) out.activeSlot = m[1];
                    if (!out.slots.some(function (x) { return x.id === slot.id; })) out.slots.push(slot);
                    out.parsed = true;
                }
                const pv = line.match(/^\s*previous\s+slot\s*[:\s]?\s*([A-Za-z0-9][A-Za-z0-9._-]*)\b/i);
                if (pv) out.previousSlot = pv[1];
                const cu = line.match(/^\s*boot(?:ed)?\s+slot\s*[:\s]?\s*([A-Za-z0-9][A-Za-z0-9._-]*)\b/i);
                if (cu) out.activeSlot = cu[1];
                const cs = line.match(/^\s*current\s+slot\s*[:\s]?\s*([A-Za-z0-9][A-Za-z0-9._-]*)\b/i);
                if (cs) out.currentSlot = cs[1];
                if (/^\s*(next|upgrade|update)\b/i.test(line) && /\b(ready|available|pending|waiting)\b/i.test(line))
                    out.upgradePending = true;
                if (/\breboot|restart\b/i.test(line) && /\bneeded|required|pending|finish\b/i.test(line))
                    out.rebootNeeded = true;
            });
        }
        out.slots.forEach(function (x) {
            x.state = x.id === out.activeSlot ? "active"
                : x.id === out.previousSlot ? "passive" : "inactive";
            x.pending = x.id === out.currentSlot && out.currentSlot !== out.activeSlot;
        });
        if (!out.parsed) out.note = "shani-deploy did not report any installed slots.";
        return out;
    }
    // ---- parser:end ---------------------------------------------------------

    Process {
        id: status
        command: ["sh", "-c", "command -v shani-deploy >/dev/null || exit 3; exec shani-deploy --status"]
        stdout: StdioCollector { id: statusOut }
        stderr: StdioCollector { id: statusErr }
        onExited: code => {
            root.loading = false;
            if (code !== 0) {
                root.available = false;
                root.error = code === 3
                    ? Tr.t("shani-deploy is not installed; system slots cannot be read.")
                    : (statusErr.text.trim().split("\n").pop() || Tr.t("shani-deploy could not report the system slots."));
                return;
            }
            const p = root.parseStatus(statusOut.text);
            root.available = p.parsed;
            root.slots = p.slots;
            root.activeSlot = p.activeSlot;
            root.previousSlot = p.previousSlot;
            root.currentSlot = p.currentSlot;
            root.version = p.version;
            root.channel = p.channel;
            root.rebootNeeded = p.rebootNeeded;
            root.upgradePending = p.upgradePending;
            root.bootFailure = p.bootFailure;
            root.error = "";
            root.note = p.note;
        }
    }

    // ---- actions ------------------------------------------------------------
    // There is no arbitrary "boot this named slot" verb: shani-deploy's
    // restore path is `--rollback`, which switches to the sibling slot. A
    // request for any other slot is refused rather than turned into a guess.
    function startRollback(message) {
        if (root.busy) return;
        root.busy = true;
        root.progress = [];
        root.actionError = "";
        root.note = message;
        rollback.command = ["sh", "-c",
            "command -v shani-deploy >/dev/null || exit 3; exec pkexec /usr/local/bin/shani-deploy --rollback"];
        rollback.running = false;
        rollback.running = true;
    }

    function switchSlot(slot) {
        const target = String(slot || "");
        if (root.busy) return;
        if (!target) { root.actionError = Tr.t("No slot was named."); return; }
        if (target === root.activeSlot) {
            root.note = Tr.t("This is already the running system.");
            return;
        }
        if (target !== root.previousSlot || !root.slots.some(function (x) { return x.id === target; })) {
            root.actionError = Tr.t("shani-deploy can only switch back to the previous slot.");
            return;
        }
        root.startRollback(Tr.t("Switching back to slot %1…", target));
    }

    function restorePrevious() {
        if (root.busy) return;
        if (!root.previousSlot) {
            root.actionError = Tr.t("No previous slot was reported; nothing to roll back to.");
            return;
        }
        root.startRollback(Tr.t("Going back to the previous system…"));
    }

    Process {
        id: rollback
        stdout: SplitParser {
            onRead: line => {
                const l = String(line).trim();
                if (l !== "") root.progress = root.progress.concat([l]).slice(-40);
            }
        }
        stderr: StdioCollector { id: rollbackErr }
        onExited: code => {
            root.busy = false;
            if (code === 0) {
                root.note = Tr.t("The slot switch is set. Restart to finish; no files were restored.");
                root.refresh();
            } else if (code === 3) {
                root.actionError = Tr.t("shani-deploy is not installed.");
            } else if (code === 126 || code === 127) {
                root.actionError = Tr.t("That needed administrator rights and was not given.");
            } else {
                root.actionError = (rollbackErr.text.trim().split("\n").pop()
                    || (root.progress.length ? root.progress[root.progress.length - 1] : ""))
                    || Tr.t("The slot switch did not finish.");
            }
        }
    }

    // ---- optional dry run ----------------------------------------------------
    function probeDryRun() {
        probe.command = ["sh", "-c",
            "command -v shani-deploy >/dev/null && shani-deploy --help 2>&1 | grep -q -- '--dry-run'"];
        probe.running = false;
        probe.running = true;
    }

    function preview() {
        if (!root.dryRunSupported) {
            root.note = Tr.t("This shani-deploy has no dry run for a slot switch; the target above is the preview.");
            return;
        }
        root.previewLines = [];
        previewProc.command = ["sh", "-c", "command -v shani-deploy >/dev/null || exit 3; exec shani-deploy --dry-run"];
        previewProc.running = false;
        previewProc.running = true;
    }

    Process {
        id: probe
        onExited: code => { root.dryRunSupported = (code === 0); }
    }
    Process {
        id: previewProc
        stdout: SplitParser {
            onRead: line => {
                const l = String(line).trim();
                if (l !== "") root.previewLines = root.previewLines.concat([l]).slice(-40);
            }
        }
        onExited: code => {
            if (code === 3) root.note = Tr.t("shani-deploy is not installed.");
            else if (code !== 0) root.note = Tr.t("The dry run did not finish.");
        }
    }
}
