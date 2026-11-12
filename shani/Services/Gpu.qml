pragma Singleton
// The graphics cards (switcheroo-control): on a machine with two, an app can
// be opened on the one that is not the default — a game, a 3D or video tool.
// switcherooctl names each card and the environment that selects it.
// `stats` is the System Monitor's GPU line: nvidia-smi's utilisation and
// memory when nvidia-smi is present, else null — shown as "no GPU".
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property var gpus: []                 // [{ name, isDefault, env: ["DRI_PRIME=…", …] }]
    readonly property var other: gpus.find(g => !g.isDefault) || null
    // two cards to choose from: switcheroo-control's list, or (without it) the
    // NVIDIA driver loaded, or a second render node - what launch-app.py uses
    property int renderNodes: 1
    property bool nvidia: false
    readonly property bool hasChoice: (gpus.length > 1 && other !== null) || nvidia || renderNodes > 1
    property var stats: null              // { name, util, memUsed, memTotal } or null
    Process {
        running: true
        command: ["sh", "-c", 'ls /dev/dri/renderD* 2>/dev/null | wc -l; [ -e /proc/driver/nvidia/version ] && echo nvidia']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                root.renderNodes = parseInt(l[0]) || 1;
                root.nvidia = l.indexOf("nvidia") >= 0;
            }
        }
    }

    // "Device: 1 / Name: NVIDIA … / Default: no / Environment: DRI_PRIME=pci-0000_01_00_0 …"
    Process {
        running: true
        command: ["sh", "-c", "command -v switcherooctl >/dev/null && switcherooctl list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                let cur = null;
                for (const line of text.split("\n")) {
                    const m = /^\s*(Device|Name|Default|Environment):\s*(.*)$/.exec(line);
                    if (!m) continue;
                    if (m[1] === "Device") { cur = { name: "", isDefault: false, env: [] }; out.push(cur); }
                    else if (cur && m[1] === "Name") cur.name = m[2].trim();
                    else if (cur && m[1] === "Default") cur.isDefault = /yes/i.test(m[2]);
                    else if (cur && m[1] === "Environment") cur.env = m[2].trim().split(/\s+/).filter(x => x.indexOf("=") > 0);
                }
                root.gpus = out;
            }
        }
    }
    // nvidia-smi utilisation, throttled (2s) and only while the System Monitor
    // is open; absent => stats stays null and the panel says "no GPU"
    Timer {
        interval: 2000
        running: Ui.processes
        repeat: true
        triggeredOnStart: true
        onTriggered: smi.running = true
    }
    Process {
        id: smi
        command: ["sh", "-c", "command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = String(text || "").trim().split("\n")[0] || "";
                if (line === "") { root.stats = null; return; }
                const f = line.split(",").map(x => x.trim());
                if (f.length < 4) { root.stats = null; return; }
                root.stats = { name: f[0], util: Number(f[1]), memUsed: Number(f[2]), memTotal: Number(f[3]) };
            }
        }
    }
    // an installed app (its desktop id) on the other card
    function launchOnOther(desktopId) {
        Launch.app(desktopId, { gpu: "discrete" });
    }
}
