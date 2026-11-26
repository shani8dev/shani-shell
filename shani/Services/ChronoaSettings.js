.pragma library
// Plain words for the engine's setting rows. The engine owns the keys, the
// kinds and the secret flag; this file owns only how a row reads on screen.
// No other product's name may appear in a label.

var GROUPS = [
    { id: "answers", label: "Answers" },
    { id: "access", label: "What it may do" },
    { id: "keys", label: "Access keys" },
    { id: "other", label: "Other" }
];

function groups() { return GROUPS; }

function isOn(value) {
    return value === true || value === "true" || value === 1 || value === "1";
}

function group(row) {
    if (row.secret) return "keys";
    if (row.consent_key) return "access";
    if (row.name === "privacy-mode" || String(row.name).indexOf("cloud-") === 0) return "answers";
    return "other";
}

function label(row) {
    var known = {
        "privacy-mode": "How private answers are",
        "cloud-stt-enabled": "Spoken words sent away to be written down",
        "input-control-enabled": "Let it act on this computer",
        "ollama-host": "Local answer service address",
        "openai-api-key": "Key for a cloud answer service"
    };
    return known[row.name] || String(row.name || "").replace(/-/g, " ");
}

function choices(name) {
    return {
        "privacy-mode": [
            { label: "Private", value: "private" },
            { label: "Balanced", value: "balanced" }
        ]
    }[name] || null;
}

function presets() {
    return [
        { label: "Just answers", value: "chat" },
        { label: "Everyday help", value: "everyday" },
        { label: "Full control", value: "full" }
    ];
}

function describe(row) {
    return {
        name: row.name,
        label: label(row),
        group: group(row),
        kind: row.kind,
        secret: !!row.secret,
        consent: !!row.consent_key,
        value: row.secret ? "" : row.value,
        choices: choices(row.name)
    };
}
