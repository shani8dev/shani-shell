pragma Singleton
// AI model discovery and management: what models are installed on this
// computer (ollama, llama.cpp, GGUF files), what fits in the available
// RAM/VRAM, and what can be downloaded. The shell doesn't run models
// itself — Chronoa does — but this service tells the user what's available
// and lets them install/remove models.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    // installed models: [{ name, size, format, source, path }]
    property var installed: []
    // available models to download: [{ name, size, description, source }]
    property var available: [
        { name: "llama3.2:3b",     size: "2.0 GB",  description: Tr.t("Fast, good for everyday tasks"), source: "ollama" },
        { name: "llama3.2:1b",     size: "1.3 GB",  description: Tr.t("Very fast, lightweight"), source: "ollama" },
        { name: "qwen2.5:7b",      size: "4.7 GB",  description: Tr.t("Good multilingual model"), source: "ollama" },
        { name: "qwen2.5:3b",      size: "1.9 GB",  description: Tr.t("Fast multilingual model"), source: "ollama" },
        { name: "mistral:7b",      size: "4.1 GB",  description: Tr.t("Strong reasoning, 7B"), source: "ollama" },
        { name: "phi3:3.8b",       size: "2.2 GB",  description: Tr.t("Small model, good at reasoning"), source: "ollama" },
        { name: "gemma2:2b",       size: "1.6 GB",  description: Tr.t("Google's lightweight model"), source: "ollama" },
    ]

    // system resources for fit-on-computer check
    readonly property real ramTotal: SysStats.memTotalGb   // GB
    readonly property real ramAvailable: SysStats.memTotalGb * (1 - SysStats.mem)  // GB
    // Gpu exposes the cards in `gpus` and the live one in `stats`, not flat
    // name/vram properties: read those (the default card, else the first)
    readonly property string gpuName: (Gpu.gpus.find(g => g.isDefault) || Gpu.gpus[0] || {}).name || ""
    readonly property real vram: (Gpu.stats && Gpu.stats.memTotal ? Gpu.stats.memTotal : 0) / (1024 * 1024 * 1024)   // GB

    // check if a model fits in available memory
    function fitsInRam(sizeStr) {
        const m = /([\d.]+)\s*(GB|MB|GiB|MiB)/i.exec(String(sizeStr || ""));
        if (!m) return false; // unknown size: don't claim it fits
        if (!(root.ramAvailable > 0)) return true; // RAM unknown: don't block downloads
        const gb = parseFloat(m[1]) / (/^(MB|MiB)$/i.test(m[2]) ? 1024 : 1);
        // model needs ~1.5x its size in RAM (weights + context)
        return gb * 1.5 <= root.ramAvailable;
    }

    function refresh() {
        list.running = true;
    }

    // discover installed ollama models
    Process {
        id: list
        command: ["sh", "-c", "command -v ollama >/dev/null 2>&1 && ollama list 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const lines = text.trim().split("\n");
                    const models = [];
                    for (const line of lines) {
                        // ollama list: "NAME  ID  SIZE  MODIFIED" — SIZE is
                        // two tokens ("2.0 GB"), so split() alone truncates it.
                        const m = /^(\S+)\s+\S+\s+([\d.]+\s*(?:GB|MB|GiB|MiB|B))\b/i.exec(line.trim());
                        if (m) {
                            models.push({
                                name: m[1],
                                size: m[2].replace(/\s+/g, " "),
                                source: "ollama",
                                path: m[1],
                            });
                        }
                    }
                    root.installed = models;
                } catch (e) {
                    root.installed = [];
                }
            }
        }
    }

    // download a model via ollama
    function download(name) {
        Quickshell.execDetached(["sh", "-c",
            'notify-send -a Models "Downloading $1…"'
            + '; ollama pull "$1" 2>&1 | while read line; do notify-send -a Models "Downloading $1..." "$line"; done'
            + '; notify-send -a Models "Downloaded $1" "Ready to use"'
        , "sh", name]);
    }

    // remove an installed model
    Timer { id: removeRefresh; interval: 1500; onTriggered: root.refresh() }

    function remove(name) {
        Quickshell.execDetached(["sh", "-c",
            'ollama rm "$1" 2>&1 && notify-send -a Models "Removed $1"'
        , "sh", name]);
        // shortcut: a 1.5s re-read can be too slow on slow disks, use a rm
        // Process onStreamFinished callback instead; refreshing immediately
        // leaves the deleted row on screen until the next manual refresh
        root.installed = root.installed.filter(m => m.name !== name);
        removeRefresh.restart();
    }
}
