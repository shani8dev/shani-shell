.pragma library
.import "Format.js" as Format
// One month as a calendar grid draws it: the blanks before the 1st, the days,
// optional ISO week numbers, and the weekday header. DatePicker, the sidebar
// calendar and the Calendar app each computed this themselves; the header was
// English ("Mo Tu We") in every language. Pure, tested in node
// (tests/test_month.py).

/// Blank cells before the 1st: Monday-first or Sunday-first.
function lead(month, sundayFirst) {
    return sundayFirst ? month.getDay() : (month.getDay() + 6) % 7;
}

/// Number of days in the month of `month`.
function daysIn(month) {
    return new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
}

/// The grid row by row: [{ week }] (when weekNumbers) then up to seven { day },
/// day <= 0 for the blanks before the 1st. The last row stops at the last day.
function cells(month, sundayFirst, weekNumbers) {
    const out = [];
    const before = lead(month, sundayFirst), days = daysIn(month);
    const rows = Math.ceil((before + days) / 7);
    for (let r = 0; r < rows; r++) {
        if (weekNumbers) {
            // the row's Thursday-anchored week: any day of the row inside the month will do
            const first = Math.max(1, r * 7 - before + 1);
            out.push({ week: Format.isoWeek(new Date(month.getFullYear(), month.getMonth(), first)) });
        }
        for (let c = 0; c < 7; c++) {
            const day = r * 7 + c - before + 1;
            if (day > days)
                break;
            out.push({ day: day });
        }
    }
    return out;
}

/// The header in grid order, from seven names that start on Sunday
/// (what Qt's Locale.dayName gives for 0..6).
function weekNames(sundayFirst, namesFromSunday) {
    return sundayFirst ? namesFromSunday.slice() : namesFromSunday.slice(1).concat(namesFromSunday.slice(0, 1));
}
