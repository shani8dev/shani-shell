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
        { name: "phi3:3.8b",       size: "2.2 GB",  description: Tr.t("Microsoft's small model"), source: "ollama" },
        { name: "gemma2:2b",       size: "1.6 GB",  description: Tr.t("Google's lightweight model"), source: "ollama" },
    ]

    // system resources for fit-on-computer check
    readonly property real ramTotal: SysStats.ramTotal / (1024 * 1024 * 1024)   // GB
    readonly property real ramAvailable: SysStats.ramAvailable / (1024 * 1024 * 1024)  // GB
    // Gpu exposes the cards in `gpus` and the live one in `stats`, not flat
    // name/vram properties: read those (the default card, else the first)
    readonly property string gpuName: (Gpu.gpus.find(g => g.isDefault) || Gpu.gpus[0] || {}).name || ""
    readonly property real vram: (Gpu.stats && Gpu.stats.memTotal ? Gpu.stats.memTotal : 0) / (1024 * 1024 * 1024)   // GB

    // check if a model fits in available memory
    function fitsInRam(sizeStr) {
        const m = /([\d.]+)\s*GB/.exec(sizeStr || "");
        if (!m) return true;
        const gb = parseFloat(m[1]);
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
                        // ollama list format: "NAME  ID  SIZE  MODIFIED"
                        const parts = line.trim().split(/\s+/);
                        if (parts.length >= 3 && parts[0] !== "NAME") {
                            models.push({
                                name: parts[0],
                                size: parts[2],
                                source: "ollama",
                                path: parts[0],
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
    function remove(name) {
        Quickshell.execDetached(["sh", "-c",
            'ollama rm "$1" 2>&1 && notify-send -a Models "Removed $1"'
        , "sh", name]);
        Qt.callLater(root.refresh);
    }
}
