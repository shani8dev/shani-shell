pragma Singleton
// Something plugged in while the session runs: one notification saying what it
// is, with the one obvious next step as its button(s).
//   a monitor           Extend / Mirror / Only this screen (Displays, on probation)
//   a drawing tablet    Use it on this screen (tabletOutput)
//   a game controller   its name and battery (UPower)
//   a security key      Use it to sign in (Settings > Your account)
//   a scanner           Scan a document (Simple Scan)
// Event-driven: bridge/plugwatch.py is one `udevadm monitor` (udev's own events,
// so what was there at login is never news), and monitors come from Displays,
// which follows wl_outputs and drm hotplugs. Each device is greeted once a session.
// The greeting is a notify-send with actions: it waits for the click and prints
// the action's id - the shell's own notification card, DND and history included.
// Settings > Notifications turns greetings off; the watcher keeps running for
// the pages that follow devices (controllers, security keys) and GamepadNav.
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_PLUGWATCH_TOOL") || "/usr/lib/shani-shell/plugwatch.py"
    readonly property string mountsTool: Quickshell.env("SHANI_MOUNTS_TOOL") || "/usr/lib/shani-shell/mounts.py"
    property var seen: ({})               // kind + key: greeted this session
    property int greeted: 0               // for the tests
    property string last: ""              // the last greeting's title
    // bumped when a controller or a security key comes or goes: pages re-read
    property int controllerRev: 0
    property int keyRev: 0
    property int inputRev: 0              // a keyboard, touchscreen or switch came or went
    signal controllerArrived()

    // UPower's battery for a controller: by its name, or the only one there is
    function controllerBattery(name) {
        const pads = UPower.devices.values.filter(d => d.type === UPowerDeviceType.GamingInput && d.isPresent);
        const d = pads.find(x => x.model && (name.indexOf(x.model) >= 0 || x.model.indexOf(name) >= 0)) || (pads.length === 1 ? pads[0] : null);
        return d ? Math.round(d.percentage * 100) : -1;
    }

    function handle(e) {
        if (e.event === "screens") {
            Displays.rescan();
            return;
        }
        if (e.kind === "controller") {
            controllerRev++;
            if (e.event === "add")
                controllerArrived();
        }
        if (e.kind === "security-key")
            keyRev++;
        if (e.kind === "input" || e.kind === "clicker") {
            inputRev++;
            if (e.kind === "input")
                return;
        }
        if (e.event === "add")
            greet(e.kind, e.name, e.key);
    }

    function greet(kind, name, key) {
        const id = kind + "\n" + key;
        if (seen[id] || !Settings.data.plugGreetings || Lock.locked)
            return;
        const s = Object.assign({}, seen);
        s[id] = true;
        seen = s;
        let title = "", body = "", icon = "", actions = [];
        if (kind === "monitor") {
            title = Tr.t("%1 plugged in", name);
            body = Tr.t("Extend, mirror, or only this screen?");
            icon = "video-display";
            // a projector or a TV is just a new external screen: Presenting is offered for any
            actions = [["extend", Tr.t("Extend")], ["mirror", Tr.t("Mirror")], ["only", Tr.t("Only this screen")], ["present", Tr.t("Presenting")]];
        } else if (kind === "tablet") {
            title = Tr.t("%1 plugged in", name);
            body = Tr.t("A drawing tablet. It draws on every screen until you choose one.");
            icon = "input-tablet";
            actions = [["here", Tr.t("Use it on this screen")]];
        } else if (kind === "controller") {
            const b = controllerBattery(name);
            title = name;
            body = b >= 0 ? Tr.t("Connected. Battery %1 %", b) : Tr.t("Connected.");
            icon = "input-gaming";
            actions = [["test", Tr.t("Test the buttons")]];
        } else if (kind === "security-key") {
            title = Tr.t("%1 plugged in", name);
            body = Tr.t("A security key. Touch it to sign in instead of typing your password.");
            icon = "auth-smartcard";
            actions = [["signin", Tr.t("Use it to sign in")]];
        } else if (kind === "scanner") {
            title = Tr.t("%1 plugged in", name);
            body = Tr.t("A scanner, ready.");
            icon = "scanner";
            actions = [["scan", Tr.t("Scan a document")]];
        } else if (more[kind]) {
            const m = more[kind];
            title = Tr.t("%1 plugged in", name);
            body = typeof m.body === "function" ? m.body(name) : m.body;
            icon = m.icon;
            actions = m.action ? [m.action] : [];
            if (m.arrived)
                m.arrived(name);
        } else
            return;
        greeted++;
        last = title;
        const argv = ["notify-send", "-a", Tr.t("Devices"), "-i", icon];
        for (const a of actions)
            argv.push("-A", a[0] + "=" + a[1]);
        asker.createObject(root, { command: argv.concat([title, body]), kind: kind, key: key, name: name, running: true });
    }

    // the rest: one sentence and (at most) one action each
    readonly property var more: ({
        "camera": { icon: "camera-photo", body: Tr.t("A camera. Its photos are in Files."), action: ["files", Tr.t("Import photos")] },
        "phone": { icon: "phone", body: Tr.t("A phone, as storage. Unlock it and allow file transfer if it asks."), action: ["files", Tr.t("Open the phone's files")] },
        "iphone": { icon: "phone-apple-iphone", action: ["files", Tr.t("Open its files")],
            // said once, ever: what an iPhone cannot do here
            body: () => Settings.data.iphoneNoteDone ? Tr.t("An iPhone. Trust this computer on it to see its files.")
                : Tr.t("An iPhone. Trust this computer on it to see its files. Calls and texts are not available for iPhone."),
            arrived: () => Settings.data.iphoneNoteDone = true },
        "clicker": { icon: "x-office-presentation", body: Tr.t("Your clicker moves slides.") },
        "capture": { icon: "camera-video", body: Tr.t("A capture card: what it receives can be shown and recorded."), action: ["camera", Tr.t("Open in Camera")] },
        "midi": { icon: "audio-midi", body: Tr.t("A MIDI device. Apps can use it now.") },
        "serial": { icon: "utilities-terminal", body: name => Tr.t("Arduino or serial device connected - %1", name.split(" - ").pop()), action: ["copy", Tr.t("Copy the port name")] },
        "cardreader": { icon: "auth-smartcard", body: Tr.t("Card reader ready.") },
        // a braille display is a person who reads by touch: the screen reader comes on at once
        "braille": { icon: "preferences-desktop-accessibility", action: ["undo", Tr.t("Undo")],
            body: () => Settings.data.screenReader ? Tr.t("A braille display. The screen reader is on.") : Tr.t("A braille display. The screen reader is now on."),
            arrived: () => { root.readerWas = Settings.data.screenReader; Settings.data.screenReader = true; } },
        "egpu": { icon: "video-display", body: Tr.t("An external graphics card. Apps can run on it - right-click an app, Run on the faster GPU.") }
    })
    property bool readerWas: false

    // Presenting: a screen mirrored, Do Not Disturb and caffeine on - and all of it
    // put back the moment that screen is unplugged
    property var presenting: null         // { output, dnd, caffeine }
    function present(output) {
        const others = Displays.outputs.filter(o => o.name !== output && o.on);
        presenting = { output: output, dnd: Notifs.dnd, caffeine: Settings.data.caffeine };
        if (others.length)
            Displays.mirrorOnto(output, (others.find(o => o.name === Niri.focusedOutput) || others[0]).name);
        Notifs.setDnd(true);
        Settings.data.caffeine = true;
    }
    Connections {
        target: Displays
        function onDeparted(name) {
            if (!root.presenting || root.presenting.output !== name)
                return;
            Displays.stopMirror();
            Notifs.setDnd(root.presenting.dnd);
            Settings.data.caffeine = root.presenting.caffeine;
            root.presenting = null;
        }
    }

    function act(kind, key, action, label) {
        const name = key;                // a monitor's key is its connector
        if (kind === "monitor") {
            const others = Displays.outputs.filter(o => o.name !== name && o.on);
            if (action === "extend") {
                // to the right of what is there, the way most desks are laid out
                const x = others.reduce((m, o) => Math.max(m, o.x + o.width), 0);
                Displays.apply(name, { off: false, x: x, y: 0 });
            } else if (action === "only")
                Displays.apply_all([{ name: name, patch: { off: false } }].concat(others.map(o => ({ name: o.name, patch: { off: true } }))));
            else if (action === "mirror" && others.length)
                Displays.mirrorOnto(name, (others.find(o => o.name === Niri.focusedOutput) || others[0]).name);
            else if (action === "present")
                present(name);
        } else if (kind === "tablet" && action === "here")
            Settings.data.tabletOutput = Niri.focusedOutput || (Displays.outputs[0] || {}).name || "";
        else if (kind === "controller" && action === "test")
            Ui.openSettings("input");
        else if (kind === "security-key" && action === "signin")
            Ui.openSettings("account");
        else if (kind === "scanner" && action === "scan")
            Launch.app("org.gnome.SimpleScan");
        else if (action === "files")
            Quickshell.execDetached(["python3", root.mountsTool, "open", kind === "camera" ? "gphoto2" : kind === "iphone" ? "afc" : "mtp"]);
        else if (kind === "capture" && action === "camera")
            Launch.app("org.gnome.Snapshot");
        else if (kind === "serial" && action === "copy")
            Quickshell.execDetached(["wl-copy", String(label).split(" - ").pop()]);
        else if (kind === "braille" && action === "undo")
            Settings.data.screenReader = root.readerWas;
    }

    Component {
        id: asker
        Process {
            id: proc
            property string kind
            property string key
            property string name
            stdout: StdioCollector {
                onStreamFinished: {
                    const a = text.trim();
                    if (a)
                        root.act(proc.kind, proc.key, a, proc.name);
                }
            }
            onExited: destroy()
        }
    }

    Connections {
        target: Displays
        function onArrived(o) { root.greet("monitor", o.label !== o.name ? o.label : o.name, o.name); }
    }

    Process {
        running: true
        command: ["python3", root.tool]
        stdout: SplitParser {
            onRead: line => {
                try { root.handle(JSON.parse(line)); } catch (e) {}
            }
        }
    }
}
