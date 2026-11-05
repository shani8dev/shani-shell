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
