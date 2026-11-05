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
    property var seen: ({})               // kind + key: greeted this session
    property int greeted: 0               // for the tests
    property string last: ""              // the last greeting's title
    // bumped when a controller or a security key comes or goes: pages re-read
    property int controllerRev: 0
    property int keyRev: 0
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
            actions = [["extend", Tr.t("Extend")], ["mirror", Tr.t("Mirror")], ["only", Tr.t("Only this screen")]];
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
        } else
            return;
        greeted++;
        last = title;
        const argv = ["notify-send", "-a", Tr.t("Devices"), "-i", icon];
        for (const a of actions)
            argv.push("-A", a[0] + "=" + a[1]);
        asker.createObject(root, { command: argv.concat([title, body]), kind: kind, key: key, running: true });
    }

    function act(kind, key, action) {
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
        } else if (kind === "tablet" && action === "here")
            Settings.data.tabletOutput = Niri.focusedOutput || (Displays.outputs[0] || {}).name || "";
        else if (kind === "controller" && action === "test")
            Ui.openSettings("input");
        else if (kind === "security-key" && action === "signin")
            Ui.openSettings("account");
        else if (kind === "scanner" && action === "scan")
            Launch.app("org.gnome.SimpleScan");
    }

    Component {
        id: asker
        Process {
            id: proc
            property string kind
            property string key
            stdout: StdioCollector {
                onStreamFinished: {
                    const a = text.trim();
                    if (a)
                        root.act(proc.kind, proc.key, a);
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
