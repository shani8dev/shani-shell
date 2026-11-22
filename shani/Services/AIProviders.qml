pragma Singleton
// AI provider connections: API keys for OpenAI, Anthropic, Mistral, and
// custom endpoints. Keys are stored in Passwords (encrypted), not here.
// The shell uses these to route Chronoa requests to the right provider.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    // connected providers: [{ id, name, keyLength, endpoint, models }]
    // The actual keys are in Passwords.keychain, not here.
    readonly property var providers: Settings.data.aiProviders || []

    // available provider definitions
    readonly property var available: [
        { id: "openai",    name: "OpenAI",         endpoint: "https://api.openai.com/v1",  keyHint: "sk-…",  docs: "platform.openai.com/api-keys" },
        { id: "anthropic", name: "Anthropic",      endpoint: "https://api.anthropic.com",  keyHint: "sk-ant-…", docs: "console.anthropic.com/settings/keys" },
        { id: "mistral",   name: "Mistral",        endpoint: "https://api.mistral.ai/v1",  keyHint: "…",  docs: "console.mistral.ai/api-keys" },
        { id: "custom",    name: Tr.t("Custom endpoint"), endpoint: "",                           keyHint: "…",  docs: "" },
    ]

    // is a provider connected?
    function isConnected(id) {
        return providers.some(p => p.id === id);
    }

    // connect a provider: save the API key to Passwords, store metadata here
    function connect(id, name, key, endpoint) {
        // store the key in Passwords (encrypted)
        Passwords.setKey("ai-provider-" + id, key);

        // store metadata (no key) in settings
        const all = providers.filter(p => p.id !== id);
        all.push({
            id: id,
            name: name || id,
            keyLength: key.length,       // just the length, not the key itself
            endpoint: endpoint || (available.find(p => p.id === id) || {}).endpoint || "",
            connectedAt: Date.now(),
        });
        Settings.data.aiProviders = all;
    }

    // disconnect a provider: remove metadata and delete the key from Passwords
    function disconnect(id) {
        const all = providers.filter(p => p.id !== id);
        Settings.data.aiProviders = all;
        Passwords.deleteKey("ai-provider-" + id);
    }

    // get the API key for a provider (from Passwords)
    function getKey(id) {
        return Passwords.getKey("ai-provider-" + id) || "";
    }

    // the default provider for Chronoa (local first, then cloud)
    readonly property string defaultProvider: {
        if (providers.length > 0) return providers[0].id;
        return "local";
    }

    // source attribution: which provider answered
    property string lastProvider: "local"
    property string lastModel: ""
}