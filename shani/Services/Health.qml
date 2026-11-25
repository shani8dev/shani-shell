pragma Singleton
// Health: a local-first fitness journal. bridge/health.py keeps the sqlite
// store under XDG_DATA_HOME and is the only reader of the watch, so the window
// cannot disagree with what is on disk. shani-link is optional: the bridge
// still answers with the local journal when there is no watch to read.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_HEALTH_TOOL"), "health.py")

    property bool loaded: false
    property bool busy: false
    property string note: ""
    property string error: ""           // why the watch could not be read ("" when fine)

    property int stepsToday: 0
    property int stepsYesterday: 0
    property int stepsGoal: 10000
    property var stepsWeek: []          // last seven days, oldest first
    property var sleep: ({ deep: 0, light: 0, awake: 0, rem: 0, asleep: 0 })
    property var stress: []             // [{ when, value }]
    property var workouts: []           // [{ day, kind, minutes, steps, calories, source }]
    property var measures: []           // [{ when, kind, value, unit }]
    property var history: []            // [{ day, steps, deep_min, light_min, ... }]
    property string device: ""
    property int battery: -1

    function refresh() {
        root.run("summary", []);
        root.run("history", ["7"]);
    }
    function logStep(count) {
        const n = Math.max(0, parseInt(count, 10) || 0);
        if (n <= 0) { root.note = Tr.t("Enter a step count"); return; }
        root.say(Tr.t("Steps saved"));
        root.run("log", ["step", String(n)]);
    }
    function logSleep(deep, light, awake) {
        const d = Math.max(0, parseInt(deep, 10) || 0);
        const l = Math.max(0, parseInt(light, 10) || 0);
        const a = Math.max(0, parseInt(awake, 10) || 0);
        if (d + l + a <= 0) { root.note = Tr.t("Enter at least one sleep stage"); return; }
        root.say(Tr.t("Sleep saved"));
        root.run("log", ["sleep", String(d), String(l), String(a)]);
    }
    function logWorkout(kind, minutes) {
        const k = String(kind || "").trim();
        const m = Math.max(0, parseInt(minutes, 10) || 0);
        if (k === "" || m <= 0) { root.note = Tr.t("Name the workout and its minutes"); return; }
        root.say(Tr.t("Workout saved"));
        root.run("log", ["workout", k, String(m)]);
    }
    function importFile(path) {
        if (!path) { root.note = Tr.t("No file was chosen"); return; }
        root.say(Tr.t("Importing…"));
        root.run("import", [String(path)]);
    }
    function spot(kind) {
        root.say(Tr.t("Measuring…"));
        root.run("spot", [String(kind || "hr")]);
    }
    function say(message) { root.note = message || ""; }

    // "Mon 24" for a YYYY-MM-DD day, never a UTC-shifted Date.
    function dayLabel(day) {
        const parts = String(day || "").split("-");
        if (parts.length !== 3) return "";
        const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        if (isNaN(d.getTime())) return "";
        return Qt.formatDate(d, "d MMM");
    }
    // 355 -> "5 h 55 min"; short enough for a tile
    function duration(minutes) {
        const n = Math.max(0, Math.floor(minutes || 0));
        if (n === 0) return "0 min";
        const h = Math.floor(n / 60), m = n % 60;
        return h ? (h + " h " + (m ? m + " min" : "")) : (m + " min");
    }
    function reading(item) {
        const v = (item && Array.isArray(item.value)) ? item.value.join("/") : "";
        if (!v) return "";
        return v + " " + (item.unit || "");
    }

    // one Process, reused; `what` names the answer so a queued log cannot
    // overwrite a freshly arrived summary. busy mirrors that single in-flight
    // Process so callers can queue on one guard.
    function run(what, args) {
        if (job.running || root.busy) { root.pending = root.pending.concat([{ what: what, args: args }]); return; }
        start(what, args);
    }
    function start(what, args) {
        root.busy = true;
        job.what = what;
        job.command = ["python3", root.tool, what].concat(args);
        job.running = false;
        job.running = true;
    }
    property var pending: []

    function finished(what, text) {
        root.busy = false;
        let data = null;
        try { data = JSON.parse(text); } catch (e) {
            root.error = Tr.t("Health could not answer");
            return;
        }
        if (what === "summary") {
            root.loaded = true;
            root.stepsToday = Math.max(0, Math.floor((data && data.steps_today) || 0));
            root.stepsYesterday = Math.max(0, Math.floor((data && data.steps_yesterday) || 0));
            root.stepsGoal = Math.max(1, Math.floor((data && data.step_goal) || 10000));
            root.stepsWeek = Array.isArray(data && data.steps_week) ? data.steps_week : [];
            root.sleep = (data && data.sleep) || { deep: 0, light: 0, awake: 0, rem: 0, asleep: 0 };
            root.stress = Array.isArray(data && data.stress) ? data.stress : [];
            root.workouts = Array.isArray(data && data.workouts) ? data.workouts : [];
            root.measures = Array.isArray(data && data.measures) ? data.measures : [];
            root.device = (data && data.device) || "";
            root.battery = typeof (data && data.battery) === "number" ? data.battery : -1;
            root.error = (data && data.error) || "";
        } else if (what === "history") {
            root.history = Array.isArray(data) ? data : [];
        } else if (what === "log") {
            root.note = data && data.error ? data.error : Tr.t("Saved");
            if (!data || !data.error) root.refresh();
        } else if (what === "import") {
            root.note = data && data.error ? data.error
                : Tr.t("Imported %1 entries", (data && data.imported) || 0);
            if (!data || !data.error) root.refresh();
        } else if (what === "spot") {
            if (data && data.error) {
                root.note = data.error;
            } else {
                const label = data.kind === "blood_pressure" ? Tr.t("Blood pressure")
                    : data.kind === "blood_oxygen" ? Tr.t("Oxygen") : Tr.t("Heart rate");
                root.note = label + ": " + root.reading(data);
                root.refresh();
            }
        }
    }

    Process {
        id: job
        property string what: ""
        stdout: StdioCollector { id: out }
        onExited: code => {
            if (code === 127) {
                root.busy = false;
                root.loaded = true;
                root.error = Tr.t("The health service is not installed");
            } else if (code === 0) root.finished(job.what, out.text);
            else if (job.what === "summary") { root.busy = false; root.loaded = true; root.error = Tr.t("Health could not answer"); }
            if (root.pending.length) {
                const next = root.pending[0];
                root.pending = root.pending.slice(1);
                root.start(next.what, next.args);
            }
        }
    }

    Component.onCompleted: refresh()
}
