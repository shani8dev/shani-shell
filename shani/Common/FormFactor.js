.pragma library
// What kind of screen this is, for the shell's layout and size (docs/FORM-FACTORS.md).
// One answer per screen: a laptop with a TV on HDMI is a laptop on its panel
// and a TV on the TV, at once. Pure functions, run in node by the tests.
//
// What decides it, in order:
//   - the owner's choice for that screen (Settings > Displays), always first
//   - a big touch panel                      -> board   (a classroom board)
//   - a big screen that is not built in      -> tv
//   - built in, small, with a built-in pad   -> handheld (Deck, Ally, Legion Go)
//   - built in, phone-sized                  -> phone
//   - built in, touch, folded or no keyboard -> tablet
//   - built in otherwise                     -> laptop
//   - anything else                          -> computer
// A screen that does not say how big it is (physical size 0) is a computer
// unless it is built in: guessing "tv" from a resolution would be wrong for
// every 4K monitor.

var PROFILES = ["computer", "laptop", "tablet", "handheld", "phone", "tv", "board"];

// how much bigger than the desktop design everything is drawn: type, targets,
// gaps. On top of the screen's own scale (which fixes density); this is for
// viewing distance and fingers.
var SCALE = { computer: 1.0, laptop: 1.0, tablet: 1.2, handheld: 1.25, phone: 1.15, tv: 1.6, board: 1.4 };

function diagonalInches(physical) {
    if (!physical || physical.length < 2 || !(physical[0] > 0) || !(physical[1] > 0))
        return 0;
    return Math.sqrt(physical[0] * physical[0] + physical[1] * physical[1]) / 25.4;
}

// a panel inside the machine (eDP, LVDS, DSI), not one plugged in
function builtIn(name) {
    return /^(eDP|LVDS|DSI)/i.test(name || "");
}

// screen: { name, physical: [mm, mm] }; input: { touch, tabletMode, keyboard,
// builtinPad }; chosen: the owner's choice ("" or "auto" for none)
function detect(screen, input, chosen) {
    if (chosen && PROFILES.indexOf(chosen) >= 0)
        return chosen;
    input = input || {};
    var d = diagonalInches(screen && screen.physical);
    var internal = builtIn(screen && screen.name);
    if (!internal) {
        if (d >= 50 && input.touch)
            return "board";
        if (d >= 37)
            return "tv";
        return "computer";
    }
    if (d > 0 && d <= 9.5 && input.builtinPad)
        return "handheld";
    if (d > 0 && d < 7.2)
        return "phone";
    if (input.touch && (input.tabletMode || !input.keyboard))
        return "tablet";
    return "laptop";
}

function scale(profile) {
    return SCALE[profile] || 1.0;
}

// what the owner sees in Settings for each choice
function label(profile) {
    return ({ computer: "Computer", laptop: "Laptop", tablet: "Tablet", handheld: "Handheld",
              phone: "Phone", tv: "TV", board: "Classroom board" })[profile] || "Automatic";
}
