pragma Singleton

// Moon phases for the calendar: the synodic month from a known new moon. There
// is no ephemeris here - the phase is good to the day, which is what a month
// grid shows, and it is the same arithmetic every calendar uses.
//
//   Moon.glyph(today)   "🌕"
//
// The glyph is the only thing the calendar uses: the *tithi* is Kundali's
// (NASA JPL DE440s), and the calendar's Panchang button opens it for the day
// rather than repeating the astronomy.
//
// The epoch is the new moon of 2000-01-06 18:14 UTC; the month is 29.530588853
// days. Eight phases, each about 3.7 days, so the label flips with the day.
import QtQuick

QtObject {
    readonly property real synodic: 29.530588853
    readonly property date epoch: new Date(Date.UTC(2000, 0, 6, 18, 14))
    readonly property var glyphs: ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]

    /// Days since the epoch, wrapped into one synodic month.
    function age(date) {
        const days = (date.getTime() - epoch.getTime()) / 86400000
        const wrapped = days % synodic
        return wrapped < 0 ? wrapped + synodic : wrapped
    }

    /// 0 (new) through 7 (waning crescent), rounded to the nearest eighth.
    function phase(date) {
        return Math.round(age(date) / synodic * 8) % 8
    }

    function glyph(date) {
        return glyphs[phase(date)]
    }
}