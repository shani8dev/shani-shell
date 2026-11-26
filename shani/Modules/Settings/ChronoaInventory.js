.pragma library
// Chronoa inventory: presentation data only. One function per shape the
// engine's read-only inventory returns; each gives plain { title, subtitle,
// icon } rows. No reads, no writes, no widgets here - the page only calls it.

function text(value) {
    return value === null || value === undefined ? "" : String(value);
}

function onOff(value) {
    return value === true ? "Yes" : value === false ? "No" : text(value);
}

function words(value) {
    return Array.isArray(value) ? value.map(text).filter(Boolean).join(", ") : text(value);
}

function labelValue(label, value) {
    return text(value) === "" ? "" : label + ": " + text(value);
}

function when(value) {
    var n = Number(value);
    if (value && isFinite(n) && n > 0) {
        var d = new Date(n > 100000000000 ? n : n * 1000);
        if (!isNaN(d.getTime())) return d.toLocaleDateString();
    }
    return text(value);
}

function row(title, subtitle, icon) {
    return { described: true, title: text(title), subtitle: text(subtitle), icon: text(icon) || "preferences-system" };
}

function conversations(item) {
    var i = item || {};
    var count = i.message_count !== undefined && i.message_count !== null ? i.message_count : i.messages;
    var stamp = when(i.updated_at || i.updated || i.created_at || i.created);
    var bits = [stamp, text(count) === "" ? "" : text(count) + " messages"];
    return {
        title: text(i.title || i.name || i.id || "Conversation"),
        subtitle: bits.filter(Boolean).join(" · "),
        icon: "chat-message-new"
    };
}

function models(item) {
    var i = item || {};
    return {
        title: text(i.task || i.model || "Model"),
        subtitle: [text(i.model), text(i.why)].filter(Boolean).join(" · "),
        icon: "preferences-system"
    };
}

function skills(item) {
    var i = item || {};
    return {
        title: text(i.name || i.tool || "Skill"),
        subtitle: [text(i.description), labelValue("Gate", i.gate)].filter(Boolean).join(" · "),
        icon: "applications-utilities"
    };
}

function routines(item) {
    var i = item || {};
    return {
        title: text(i.name || "Routine"),
        subtitle: text(words(i.phrases)),
        icon: "alarm-symbolic"
    };
}

function triggers(item) {
    var i = item || {};
    var bits = [
        text(i.sense),
        text(i.match_mode),
        labelValue("keywords", words(i.keywords)),
        labelValue("acts", i.actuator),
        onOff(i.enabled),
        text(i.last_fired_at)
    ];
    return {
        title: text(i.name || "Trigger"),
        subtitle: bits.filter(Boolean).join(" · "),
        icon: "preferences-system"
    };
}

function senses(item) {
    var i = item || {};
    return {
        title: text(i.name || "Sense"),
        subtitle: [text(i.key), onOff(i.enabled)].filter(Boolean).join(" · "),
        icon: "audio-input-microphone"
    };
}

function privacy(item) {
    return senses(item);
}

function memory(item) {
    var i = item || {};
    var content = text(i.content);
    var count = i.metadata && typeof i.metadata === "object" ? Object.keys(i.metadata).length : 0;
    var bits = [
        text(i.source),
        when(i.created_at),
        count ? count + (count === 1 ? " detail" : " details") : ""
    ];
    return {
        title: content.length > 120 ? content.slice(0, 117) + "…" : content,
        subtitle: bits.filter(Boolean).join(" · "),
        icon: "edit-undo-symbolic"
    };
}

function capabilities(item) {
    var i = item || {};
    return {
        title: text(i.label || i.tool || "Capability"),
        subtitle: [text(i.group), text(i.description), labelValue("consent", i.consent_key),
                   labelValue("try", i.example)].filter(Boolean).join(" · "),
        icon: "applications-utilities"
    };
}

function status(item) {
    var i = item || {};
    return {
        title: text(i.key || i.label || "Status"),
        subtitle: text(i.value !== undefined ? i.value : i.description),
        icon: "preferences-system"
    };
}

function describe(section, item) {
    if (item && typeof item === "object" && item.described === true)
        return row(item.title, item.subtitle, item.icon);
    var functions = {
        conversations: conversations,
        models: models,
        skills: skills,
        routines: routines,
        triggers: triggers,
        privacy: privacy,
        senses: senses,
        memory: memory,
        capabilities: capabilities,
        status: status
    };
    var fn = functions[String(section)];
    if (fn) return fn(item);
    if (!item || typeof item !== "object") return row(text(item), "", "preferences-system");
    return row(text(item.title || item.name), text(item.description), "preferences-system");
}

// A dict section becomes a few top rows; a list section stays as it came.
// `extra` carries { ready, service }, which the status page shows as rows.
function expand(section, data, extra) {
    var e = extra || {};
    if (section === "status") {
        var s = data && typeof data === "object" && !Array.isArray(data) ? data : {};
        return [
            row("Engine running", e.service === "active" ? "Yes" : "No", "preferences-system"),
            row("Service", text(e.service || "unknown"), "preferences-system"),
            row("Answer model", text(s.llm_model || "Not set"), "preferences-system"),
            row("Local model installed", onOff(s.llm_installed), "preferences-system"),
            row("Speech to text", onOff(s.stt_available), "audio-input-microphone"),
            row("Speech output", text(s.tts_engine || "Not set"), "audio-speakers"),
            row("Privacy mode", text(s.privacy_mode || "Not set"), "preferences-system")
        ];
    }
    if (section === "privacy") {
        var p = data && typeof data === "object" && !Array.isArray(data) ? data : {};
        var out = [
            row("Privacy mode", text(p.privacy_mode || "Not set"), "preferences-system"),
            row("Consent key", text(p.granted_consent_key || "None"), "preferences-system"),
            row("Recent outgoing", text(p.recent_egress === undefined ? 0 : p.recent_egress) + " events", "network-transmit")
        ];
        var list = Array.isArray(p.senses) ? p.senses : [];
        for (var i = 0; i < list.length; i++) out.push(list[i]);
        return out;
    }
    return Array.isArray(data) ? data : (data === null || data === undefined ? [] : [data]);
}
