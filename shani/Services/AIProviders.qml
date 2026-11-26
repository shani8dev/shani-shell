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
        { id: "google",    name: "Google Gemini",  endpoint: "https://generativelanguage.googleapis.com", keyHint: "…", docs: "aistudio.google.com/apikey" },
        { id: "groq",      name: "Groq",           endpoint: "https://api.groq.com/openai/v1", keyHint: "gsk_…", docs: "console.groq.com/keys" },
        { id: "openrouter",name: "OpenRouter",     endpoint: "https://openrouter.ai/api/v1", keyHint: "sk-or-…", docs: "openrouter.ai/keys" },
        // note: Mistral models are reachable through OpenRouter — the local
        // Chronoa backend has no dedicated Mistral endpoint (shani-chronoa
        // cloud_llm.py supports OpenAI/Anthropic/Google/Groq/OpenRouter only).
        { id: "custom",    name: Tr.t("Custom endpoint"), endpoint: "",                           keyHint: "…",  docs: "" },
    ]

    // is a provider connected?
    function isConnected(id) {
        return providers.some(p => p.id === id);
    }

    // Chronoa's own key name for a provider id (config.py API_KEY_SETTINGS).
    // The engine writes it to its keyring; the shell never touches GSettings.
    function chronoaKeyFor(id) {
        return ({ openai: "openai-api-key", anthropic: "anthropic-api-key",
                  google: "google-api-key", groq: "groq-api-key",
                  openrouter: "openrouter-api-key", custom: "custom-llm-api-key" })[id] || "";
    }
    // A refused write is shown, never swallowed. Only the key's name is kept
    // here; the secret itself goes over the socket and is not stored in QML.
    property int syncSeq: 0
    property string syncError: ""
    property string lastSync: ""

    function publish() {
        const o = Object.assign({}, Ui.chronoaState || {});
        o.keys = { last: root.lastSync, error: root.syncError };
        Ui.chronoaState = o;
    }

    function syncKeyToChronoa(id, key) {
        const k = chronoaKeyFor(id);
        if (k === "") return;
        root.syncError = "";
        root.syncSeq += 1;
        root.lastSync = k;
        if (!Bridge.send({ op: "settings-set", id: "keyset" + root.syncSeq,
                           name: k, value: key, confirm: true }))
            root.syncError = Tr.t("Could not reach the answer engine to save the key");
        root.publish();
    }

    Connections {
        target: Bridge
        function onMessage(msg) {
            if (!msg || msg.type !== "settings" || msg.op !== "set") return;
            if (String(msg.id || "").indexOf("keyset") !== 0) return;
            root.syncError = msg.error ? String(msg.error) : "";
            root.publish();
        }
    }

    // connect a provider: save the API key to Passwords, store metadata here
    function connect(id, name, key, endpoint) {
        // store the key in the desktop keyring (encrypted, never in plain settings)
        Keyring.set("ai-provider-" + id, key);
        // and in Chronoa's own settings so its cloud fallback can use it
        syncKeyToChronoa(id, key);

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
        // if this is the first provider, attribute answers to it until the
        // bridge reports a different one
        if (all.length === 1) {
            root.lastProvider = id;
            root.lastModel = name || id;
        }
    }

    // disconnect a provider: remove metadata and delete the key from Passwords
    function disconnect(id) {
        const all = providers.filter(p => p.id !== id);
        Settings.data.aiProviders = all;
        Keyring.remove("ai-provider-" + id);
        syncKeyToChronoa(id, "");   // clear Chronoa's copy too
    }

    // get the API key for a provider (from the keyring, by attribute).
    // Keyring.get is asynchronous (a Process), so callers pass a callback.
    function getKey(id, cb) {
        return Keyring.get("ai-provider-" + id, cb || (() => {}));
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
