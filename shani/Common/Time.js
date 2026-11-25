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
