.pragma library
// A charger too weak for this computer: plugged in (UPower: not on battery), yet the
// battery is still running down, for long enough not to be a moment's dip (a game
// starting, the screen at full brightness) - or UPower's own reading of the
// battery's draw while plugged in says so. Plain JS, so tests/test_charger.py runs it.

var SUSTAINED_S = 90;

// onBattery: UPower.onBattery; discharging: the battery's state is Discharging;
// since: seconds it has been so while plugged in; rate: watts out of the battery (UPower's
// energy-rate, > 0 while discharging), 0 when unknown
function tooSlow(onBattery, discharging, since, rate) {
    if (onBattery || !discharging)
        return false;
    return since >= SUSTAINED_S || rate >= 2;
}

// The power profile follows the charger (Settings > Power, off by default):
// the profile the rule wants right now, as "power-saver" | "balanced" |
// "performance", or null when the rule is off / does not apply. Plain JS so
// tests/test_charger.py runs it; Power.qml maps it onto PowerProfile enums.
//   follows: the switch; hasBattery: a laptop battery is present (desktops
//   have no battery to follow); onBattery: UPower.onBattery right now;
//   onBatteryChoice: "power-saver" | "balanced"; pluggedChoice: "balanced" |
//   "performance"; hasPerformance: the machine has a performance profile
//   (without one, "performance" falls back to "balanced", never an error).
function wantedProfile(follows, hasBattery, onBattery, onBatteryChoice, pluggedChoice, hasPerformance) {
    if (!follows || !hasBattery)
        return null;
    if (onBattery)
        return onBatteryChoice === "balanced" ? "balanced" : "power-saver";
    return pluggedChoice === "performance" && hasPerformance ? "performance" : "balanced";
}
