pragma Singleton
// The graphics cards (switcheroo-control): on a machine with two, an app can
// be opened on the one that is not the default — a game, a 3D or video tool.
// switcherooctl names each card and the environment that selects it.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property var gpus: []                 // [{ name, isDefault, env: ["DRI_PRIME=…", …] }]
    readonly property var other: gpus.find(g => !g.isDefault) || null
    readonly property bool hasChoice: gpus.length > 1 && other !== null

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
    // an installed app (its desktop id) on the other card
    function launchOnOther(desktopId) {
        if (!other)
            return;
        Quickshell.execDetached(["env"].concat(other.env, ["gtk-launch", desktopId]));
    }
}
