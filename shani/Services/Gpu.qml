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
    // Multi-GPU (ArchWiki/Niri): niri may pick the discrete GPU for both the
    // compositor and apps, draining battery on laptops. The person can pin a
    // render node here; InputConfig writes `debug { render-drm-device "…" }`.
    property var renderDevices: []        // [{ path, pci, name }]
    readonly property string chosenRenderDevice: Settings.data.niriRenderDevice || ""
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
    // /dev/dri/by-path/pci-0000:c1:00.0-render -> ../renderD129 — the PCI
    // address identifies the card (lspci -s c1:00.0), so the picker can name it.
    Process {
        running: true
        command: ["sh", "-c", 'for f in /dev/dri/by-path/*-render; do [ -e "$f" ] || continue; t=$(readlink -f "$f"); pci=$(basename "$f" -render); pci=${pci#pci-}; name=$(lspci -s "$pci" 2>/dev/null | sed "s/.*: //"); echo "$t|$pci|$name"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                root.renderDevices = text.trim().split("\n").filter(l => l.indexOf("|") > 0).map(l => {
                    const [path, pci, name] = l.split("|");
                    return { path: path, pci: pci, name: name || pci };
                });
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
