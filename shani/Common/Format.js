.pragma library
// The few pure formatters more than one surface shows. Kept here so the same
// helper is maintained in one place, while each surface keeps the byte format
// it already showed people: dedup must not silently restyle what they read.
//
// Files and Disk Usage use binary sizes with one decimal (B/KB/MB/GB). Quick
// Look, Archives and Settings > Storage use SI (1000, kB..MB..TB). File Meta
// keeps TB as a unit, and Backup shows whole MB/KB. Theme.bytes is a separate,
// deliberately SI formatter for network traffic, not for files on disk.

// The canonical entry point. `style` names one of the formats below; callers
// with no style get Files' binary, one-decimal format.
function humanSize(bytes, style) {
    if (style === "si") return humanSizeSI(bytes);
    if (style === "tb") return humanSizeTB(bytes);
    if (style === "whole") return humanSizeWhole(bytes);
    const n = Number(bytes) || 0;
    if (n >= 1073741824) return (n / 1073741824).toFixed(1) + " GB";
    if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB";
    if (n >= 1024) return (n / 1024).toFixed(1) + " KB";
    return n + " B";
}

// SI, lowercase kB, adaptive decimals: Quick Look, Archives, Settings > Storage.
function humanSizeSI(bytes) {
    const units = ["B", "kB", "MB", "GB", "TB"];
    let v = Number(bytes) || 0, i = 0;
    while (v >= 1000 && i < units.length - 1) { v /= 1000; i++; }
    return (i === 0 ? v : v.toFixed(v < 10 ? 1 : 0)) + " " + units[i];
}

// Binary through to TB, adaptive decimals: File Meta.
function humanSizeTB(bytes) {
    let n = Number(bytes) || 0;
    const units = ["B", "KB", "MB", "GB", "TB"];
    let i = 0;
    while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; }
    return (i ? n.toFixed(n < 10 ? 1 : 0) : n) + " " + units[i];
}

// Binary, whole MB/KB: Backup.
function humanSizeWhole(bytes) {
    const m = parseFloat(bytes) || 0;
    if (m >= 1024 * 1024 * 1024) return (m / (1024 * 1024 * 1024)).toFixed(1) + " GB";
    if (m >= 1024 * 1024) return (m / (1024 * 1024)).toFixed(0) + " MB";
    if (m >= 1024) return (m / 1024).toFixed(0) + " KB";
    return m + " B";
}

// Milliseconds to the next wall-clock minute, a little past the boundary so
// a timer re-armed from this never catches the same minute twice.
function msToNextMinute() {
    const n = new Date();
    return Math.max(1000, 60000 - (n.getSeconds() * 1000 + n.getMilliseconds()) + 250);
}

// ISO 8601 week number: the week holding the year's first Thursday is week 1.
function isoWeek(d) {
    const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
    t.setUTCDate(t.getUTCDate() + 3 - (t.getUTCDay() + 6) % 7);
    const y = new Date(Date.UTC(t.getUTCFullYear(), 0, 4));
    return 1 + Math.round(((t - y) / 86400000 - 3 + (y.getUTCDay() + 6) % 7) / 7);
}

// "HH:MM" to minutes past midnight, -1 when it is not a time.
function minutes(s) {
    const m = /^(\d\d?):(\d\d)$/.exec(s || "");
    return m ? parseInt(m[1]) * 60 + parseInt(m[2]) : -1;
}
