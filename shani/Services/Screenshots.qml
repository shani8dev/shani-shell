pragma Singleton
// After every screenshot (niri announces each on its event stream), a
// notification that can do something with it: annotate it (the configured tool),
// ask Chronoa about it (it looks at the picture with look_at_image), or copy the
// path. notify-send -A waits for the button pressed and prints its name.
// Capture modes and the delay mirror macOS Screenshot / GNOME Screenshot /
// Snipping Tool: pick screen, window or region, then shoot on a countdown.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property string last: ""
    readonly property bool hasCapture: last !== ""
    // the whole screen after a countdown (the OSD counts; it is gone before the shot)
    property int countdown: 0
    // pin the last screenshot in an always-on-top window (Slate-style "pin capture")
    property bool pinned: false
    property string pinnedPath: ""
    // pin presentation lives for this session only (no new settings keys)
    property real pinOpacity: 1.0
    property real pinZoom: 1.0
    function cyclePinOpacity() {
        const steps = [1.0, 0.8, 0.6];
        const i = steps.indexOf(Math.round(pinOpacity * 10) / 10);
        pinOpacity = steps[(i + 1) % steps.length];
        notifySend(Tr.t("Pin opacity %1%").arg(Math.round(pinOpacity * 100)));
    }
    function resetPinZoom() { pinZoom = 1.0; }
    function togglePin(path) {
        if (!path && !last) { notifySend(Tr.t("No screenshot to pin")); return; }
        if (pinned && pinnedPath === (path || last)) { pinned = false; pinnedPath = ""; }
        else { pinned = true; pinnedPath = path || last; }
    }

    // capture modes: niri owns the selection UI for each of these actions
    readonly property var captureModes: ["screen", "window", "region"]
    readonly property var captureDelays: [0, 3, 5, 10]
    property string captureMode: "screen"
    property int captureDelay: 0
    property string captureState: "idle"   // idle | countdown | capturing
    function setCaptureMode(m) {
        if (captureModes.indexOf(m) === -1) return;
        captureMode = m;
    }
    function setCaptureDelay(s) {
        const n = Number(s);
        if (captureDelays.indexOf(n) === -1) return;
        captureDelay = n;
    }
    // shared entry point for the capture tiles, the launcher and keyboard shortcuts
    function startCapture(mode, delay) {
        if (mode !== undefined) setCaptureMode(mode);
        if (delay !== undefined) setCaptureDelay(delay);
        if (captureDelay > 0) {
            captureState = "countdown";
            later(captureDelay);
            notifySend(Tr.t("Screenshot in %1 seconds").arg(captureDelay));
        } else {
            captureState = "capturing";
            shoot.restart();
        }
    }

    // scrolling capture: capture a long page by stitching multiple screenshots
    // uses grim + slop for region selection, then stitches with ImageMagick
    function scrollingCapture() {
        // Select a region, capture a series of parts while scrolling, and stitch
        // them into one tall image. bridge/scroll-capture.py handles slop/grim/
        // ydotool/PIL. The result is announced like any screenshot.
        const tool = Quickshell.env("SHANI_SCROLL_CAPTURE_TOOL") || "/usr/lib/shani-shell/scroll-capture.py";
        scrollSelect.command = ["python3", tool, "select"];
        scrollSelect.running = true;
    }
    Process {
        id: scrollSelect
        stdout: StdioCollector {
            onStreamFinished: {
                const geom = text.trim().split(/\s+/);
                if (geom.length !== 4) { return; }  // user cancelled
                const tool = Quickshell.env("SHANI_SCROLL_CAPTURE_TOOL") || "/usr/lib/shani-shell/scroll-capture.py";
                scrollCap.command = ["python3", tool, "capture", geom[0], geom[1], geom[2], geom[3], "8"];
                scrollCap.running = true;
            }
        }
    }
    Process {
        id: scrollCap
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p !== "") root.offer(p);
            }
        }
        onExited: code => { if (code !== 0) notifyFail.running = true; }
    }
    Process { id: notifyFail; command: ["notify-send", "-a", "Screenshot", "Scrolling capture failed — is grim, slop, ydotool and PIL installed?"] }
    // encrypted capture history: encrypt screenshots at rest after the
    // notification actions have had time to use the plaintext.
    readonly property bool encryptedHistory: Settings.data.screenshotEncrypted === true
    property string lastCapture: ""
    Timer { id: encryptTimer; interval: 120000; onTriggered: if (root.encryptedHistory && root.lastCapture !== "") root.encryptCapture(root.lastCapture); }
    function setEncryptedHistory(on) {
        Settings.data.screenshotEncrypted = on;
        if (on) {
            Keyring.get("screenshot-passphrase", pass => {
                if (!pass) {
                    // use the system's entropy (not Math.random) for the key
                    const p = genProc.createObject(root, {});
                    p.onFinished = key => { if (key) Keyring.set("screenshot-passphrase", key); notifySend("Screenshot encryption is on — captures are encrypted 2 minutes after they are taken"); };
                    p.command = ["sh", "-c", "head -c 24 /dev/urandom | base64 | tr -d '\\n'"];
                    p.running = true;
                }
                else notifySend("Screenshot encryption is on — captures are encrypted 2 minutes after they are taken");
            });
        }
    }
    function notifySend(msg) { Quickshell.execDetached(["notify-send", "-a", "Screenshot", msg]); }
    property Component genProc: Component {
        Process {
            property var onFinished: null
            stdout: StdioCollector { onStreamFinished: { if (onFinished) onFinished(text.trim()); destroy(); } }
        }
    }
    function encryptCapture(path) {
        Keyring.get("screenshot-passphrase", pass => {
            if (!pass) return;
            const tool = Quickshell.env("SHANI_ENCRYPT_CAPTURE_TOOL") || "/usr/lib/shani-shell/encrypt-capture.py";
            encProc.command = ["python3", tool, "encrypt", path, pass];
            encProc.running = true;
            root.lastCapture = "";
        });
    }
    Process {
        id: encProc
        stdout: StdioCollector { onStreamFinished: { if (text.trim() !== "") root.last = text.trim(); } }
    }
    function later(seconds) {
        countdown = seconds;
        tick.restart();
    }
    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0) {
                stop();
                root.captureState = "capturing";
                shoot.restart();
            }
        }
    }
    Timer {
        id: shoot
        interval: 300
        onTriggered: {
            const action = root.captureMode === "window" ? "screenshot-window"
                         : root.captureMode === "region" ? "screenshot" : "screenshot-screen";
            Quickshell.execDetached(["niri", "msg", "action", action]);
            root.captureState = "idle";
        }
    }
    property string annTool: (Settings.loaded && Settings.data.screenshotAnnotationTool) || "satty"
    property bool canAnnotate: false
    property bool canSatty: false

    // post-capture actions with a confirmation; an empty history is reported
    function copyImage(path) {
        const p = path || last;
        if (!p) { notifySend(Tr.t("No screenshot to copy")); return false; }
        Quickshell.execDetached(["sh", "-c",
            'p="$1"; case "$p" in *.jpg|*.jpeg) t=image/jpeg;; *.webp) t=image/webp;; *) t=image/png;; esac; wl-copy --type "$t" < "$p"', "sh", p]);
        notifySend(Tr.t("Screenshot copied to clipboard"));
        return true;
    }
    function shareImage(path) {
        const p = path || last;
        if (!p) { notifySend(Tr.t("No screenshot to share")); return false; }
        Share.open(p);
        notifySend(Tr.t("Sharing screenshot"));
        return true;
    }
    function saveImage(path) {
        const p = path || last;
        if (!p) { notifySend(Tr.t("No screenshot to save")); return false; }
        const d = (Settings.data.screenshotDir || "~/Pictures/Screenshots").replace(/^~/, Quickshell.env("HOME") || "~");
        const ext = p.slice(p.lastIndexOf("."));
        const dest = d + "/Screenshot " + new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-") + "-" + Date.now() + ext;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$2" && cp "$1" "$3"', "sh", p, d, dest]);
        notifySend(Tr.t("Screenshot saved to %1").arg(dest.split("/").pop()));
        return true;
    }

    function offer(path) {
        last = path;
        if (root.encryptedHistory) { root.lastCapture = path; encryptTimer.restart(); }
        if (Settings.data.screenshotCopyImage)
            Quickshell.execDetached(["sh", "-c", 'p="$1"; case "$p" in *.png) t=image/png;; *.jpg|*.jpeg) t=image/jpeg;; *.webp) t=image/webp;; *) t=image/png;; esac; wl-copy --type "$t" < "$p"', "sh", path]);
        // "default": a click on the notification itself opens the picture (Pantheon, GNOME)
        const args = ["notify-send", "-a", "Screenshot", "-i", path, "-A", "default=Open", "-A", "ask=Ask Chronoa", "-A", "share=Share…", "-A", "ocr=Copy text", "-A", "pin=Pin", "-A", "copy=Copy image"];
        if (canAnnotate)
            args.push("-A", "annotate=Annotate");
        prompt.command = args.concat(["Screenshot saved", path.replace(Quickshell.env("HOME"), "~")]);
        prompt.running = true;
    }

    Process {
        id: prompt
        stdout: StdioCollector {
            onStreamFinished: {
                const a = text.trim();
                if (a === "default")
                    Quickshell.execDetached(["xdg-open", root.last]);
                else if (a === "annotate")
                    root.annotate();
                else if (a === "ask")
                    Chronoa.ask("I just took a screenshot. Look at it with look_at_image: " + root.last + "\nWhat is on it, and is there anything I should do?");
                else if (a === "share")
                    Share.open(root.last);
                else if (a === "copy")
                    root.copyImage();
                else if (a === "ocr") {
                    ocr.command = ["sh", "-c", 'tesseract "$1" stdout 2>/dev/null | wl-copy', "sh", root.last];
                    ocr.running = true;
                }
                else if (a === "pin") {
                    root.togglePin(root.last);
                }
            }
        }
    }
    Process { id: ocr }
    Process {
        running: true
        command: ["sh", "-c", root.annTool === "native"
            ? 'echo yes'   // the shell's own Viewer is always available
            : 'command -v "' + root.annTool + '" >/dev/null 2>&1 && echo yes || echo no']
        stdout: StdioCollector { onStreamFinished: root.canAnnotate = text.trim() === "yes" }
    }
    Process {
        id: sattyProbe
        running: true
        command: ["sh", "-c", "command -v satty >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector { onStreamFinished: root.canSatty = text.trim() === "yes" }
        onCommandChanged: running = true
    }
    Connections {
        target: Niri
        function onScreenshotSaved(path) { root.offer(path); }
    }
    // the Media Player already writes each saved frame here (Ui.mediaFrameSaved):
    // treat it like any other screenshot, so the same share / annotate / pin
    // actions are offered for it. No second capture or copy of the file.
    Connections {
        target: Ui
        function onMediaFrameSavedChanged() {
            if (Ui.mediaFrameSaved !== "")
                root.offer(Ui.mediaFrameSaved);
        }
    }

    function annotate() {
        if (!root.last) { notifySend(Tr.t("No screenshot to annotate")); return; }
        // "native": use the shell's own image Viewer, which has pen, highlighter,
        // line, arrow, box, text and blur (Loupe-style) — no external install.
        if (root.annTool === "native") {
            Viewer.open(root.last);
            Viewer.startEdit();
            return;
        }
        // swappy edits PNG pictures only; a JPEG picture falls back to satty if available
        if (root.annTool === "swappy" && !root.last.endsWith(".png") && root.canSatty) {
            Quickshell.execDetached(["sh", "-c", 'command -v satty >/dev/null 2>&1 && exec satty --filename "$1" --output-filename "$1"; exec swappy -f "$1"', "sh", root.last]);
            return;
        }
        if (root.annTool === "swappy")
            Quickshell.execDetached(["swappy", "-f", root.last]);
        else
            Quickshell.execDetached(["satty", "--filename", root.last, "--output-filename", root.last]);
    }
}
