pragma Singleton
// Battery (UPower), power profiles (power-profiles-daemon) and the session's
// power actions. logind authorises suspend/reboot/poweroff for the active
// session, so these need no root and no prompt.
import Quickshell
import Quickshell.Services.UPower
import QtQuick

Singleton {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isLaptopBattery && battery.isPresent
    readonly property real percent: hasBattery ? battery.percentage : 1
    readonly property bool charging: hasBattery && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: hasBattery && battery.state === UPowerDeviceState.FullyCharged
    readonly property bool onBattery: UPower.onBattery
    readonly property int profile: PowerProfiles.profile
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile

    readonly property string batteryIcon: {
        if (!hasBattery)
            return "battery-missing";
        if (full)
            return "battery-full-charged";
        const lvl = Math.min(100, Math.round(percent * 10) * 10);
        return "battery-level-" + lvl + (charging ? "-charging" : "");
    }
    readonly property string timeLeft: {
        if (!hasBattery)
            return "";
        const s = charging ? battery.timeToFull : battery.timeToEmpty;
        if (!s || s <= 0)
            return "";
        const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
        return (h > 0 ? h + " h " : "") + m + " min" + (charging ? " to full" : " left");
    }
    readonly property string profileName: profile === PowerProfile.PowerSaver ? "Power saver"
        : profile === PowerProfile.Performance ? "Performance" : "Balanced"
    readonly property string profileIcon: profile === PowerProfile.PowerSaver ? "power-profile-power-saver"
        : profile === PowerProfile.Performance ? "power-profile-performance" : "power-profile-balanced"

    // warn once per discharge at 15 % and 7 %; the 7 % one is critical (it
    // passes Do Not Disturb). logind's own critical action still applies.
    property int warned: 100
    onPercentChanged: {
        if (!hasBattery || charging) {
            warned = 100;
            return;
        }
        const p = Math.round(percent * 100);
        if (p <= 7 && warned > 7) {
            warned = 7;
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Power", "-i", "battery-level-0", "Battery critically low", p + "% left — plug in now"]);
        } else if (p <= 15 && warned > 15) {
            warned = 15;
            Quickshell.execDetached(["notify-send", "-a", "Power", "-i", "battery-level-10", "Battery low", p + "% left" + (timeLeft ? " · " + timeLeft : "")]);
        }
    }

    function cycleProfile() {
        const order = [PowerProfile.PowerSaver, PowerProfile.Balanced];
        if (hasPerformance)
            order.push(PowerProfile.Performance);
        PowerProfiles.profile = order[(order.indexOf(profile) + 1) % order.length];
    }

    function suspend() { Quickshell.execDetached(["systemctl", "suspend"]); }
    function reboot() { Quickshell.execDetached(["systemctl", "reboot"]); }
    function poweroff() { Quickshell.execDetached(["systemctl", "poweroff"]); }
    function logout() { Niri.action("quit", "--skip-confirmation"); }
}
