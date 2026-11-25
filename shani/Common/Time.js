.pragma library
// The seconds → clock text the player surfaces all showed by hand. One copy,
// so a seek bar and a screenshot name cannot drift apart.
// All three use the same Math.floor + padStart logic as the old duplicates.

// m:ss — the elapsed/remaining/total labels beside a seek bar.
function clock(seconds) {
    const s = Number(seconds) || 0;
    return Math.floor(s / 60) + ":" + String(Math.floor(s % 60)).padStart(2, "0");
}

// h:mm:ss once the track passes an hour, m:ss before it. Used where a screen
// reader needs the hours spelled out, not just the two low digits.
function clockLong(seconds) {
    const s = Number(seconds) || 0;
    if (s < 3600) return clock(s);
    return Math.floor(s / 3600) + ":" + String(Math.floor(s % 3600 / 60)).padStart(2, "0")
        + ":" + String(Math.floor(s % 60)).padStart(2, "0");
}

// h-mm-ss with dashes: the frame filename "Showtime's Take screenshot" writes
// (a colon in a filename is awkward), kept byte-for-byte from Media Player.
function duration(seconds) {
    const s = Number(seconds) || 0;
    return Math.floor(s / 3600) + "-" + String(Math.floor(s % 3600 / 60)).padStart(2, "0")
        + "-" + String(Math.floor(s % 60)).padStart(2, "0");
}

// ---- calendar-day labels -------------------------------------------------
// One place decides "Today" / "Yesterday" / "d MMM", so the launcher's
// recent-files groups, the calendar and any dated list cannot disagree.

// Local calendar-day key (YYYY-MM-DD) for a Date, ms timestamp or ISO string.
function dayKey(when) {
    const d = when instanceof Date ? when
            : typeof when === "string" ? new Date(when)
            : new Date(Number(when) || Date.now());
    if (!d || isNaN(d.getTime())) return "";
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0")
        + "-" + String(d.getDate()).padStart(2, "0");
}

// "Today" / "Yesterday" / "21 Nov" — local time, newest-first callers sort by
// dayKey separately. `now` is injectable for tests.
function dayLabel(when, now) {
    const d = when instanceof Date ? when : new Date(Number(when) || Date.now());
    const n = now instanceof Date ? now : new Date();
    const key = dayKey(d), nkey = dayKey(n);
    if (key === nkey) return "Today";
    const y = new Date(n.getFullYear(), n.getMonth(), n.getDate() - 1);
    if (key === dayKey(y)) return "Yesterday";
    const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
    return d.getDate() + " " + months[d.getMonth()];
}

// Full date for detail views: "Tue 25 Nov 2026" (locale-independent, matches
// the shell's English-first UI; Tr.t wraps the surrounding sentence).
function fullDate(when) {
    const d = when instanceof Date ? when : new Date(Number(when) || Date.now());
    const days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
    const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
    return days[d.getDay()] + " " + d.getDate() + " " + months[d.getMonth()] + " " + d.getFullYear();
}

// "HH:MM" — a 24-hour clock string zero-padded to five chars ("9:05" → "09:05").
// Alarm pickers and the calendar's natural-language parser both need it.
function clockPadded(t) {
    return String(t).padStart(5, "0");
}

// "HH:MM:SS" with the hours zero-padded too (a voice-recorder counter, where
// "0:00" would look broken). Hours past 99 keep their digits.
function hhmmss(seconds) {
    const s = Number(seconds) || 0;
    return String(Math.floor(s / 3600)).padStart(2, "0")
        + ":" + String(Math.floor(s % 3600 / 60)).padStart(2, "0")
        + ":" + String(Math.floor(s % 60)).padStart(2, "0");
}

// Stopwatch "MM:SS.cc", or "H:MM:SS.cc" past an hour — the World Clock's
// running split, with centiseconds.
function stopwatch(ms) {
    const t = Number(ms) || 0;
    const cs = Math.floor(t / 10) % 100;
    const s = Math.floor(t / 1000) % 60;
    const m = Math.floor(t / 60000) % 60;
    const h = Math.floor(t / 3600000);
    return (h > 0 ? h + ":" : "") + String(m).padStart(2, "0")
        + ":" + String(s).padStart(2, "0") + "." + String(cs).padStart(2, "0");
}

// "YYYY-MM-DD-HH-MM-SS" (UTC) for a filename — a colon is awkward in a path, so
// the recorder stamps use dashes. `when` defaults to now.
function fileStamp(when) {
    const d = when instanceof Date ? when : new Date(Number(when) || Date.now());
    return d.toISOString().slice(0, 19).replace(/[T:]/g, "-");
}

// "HH:MM" minutes-of-day → minutes since midnight, or -1 when unparseable.
// Used by DND schedules and dark-mode windows so both agree.
function minutes(hhmm) {
    const m = /^(\d{1,2}):(\d{2})$/.exec(String(hhmm || "").trim());
    if (!m) return -1;
    const h = Number(m[1]), mi = Number(m[2]);
    if (h > 23 || mi > 59) return -1;
    return h * 60 + mi;
}
