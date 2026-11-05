pragma Singleton
// Battery (UPower), power profiles (power-profiles-daemon) and the session's
// power actions. logind authorises suspend/reboot/poweroff for the active
// session, so these need no root and no prompt.
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import qs.Common
import "Charger.js" as Charger

Singleton {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isLaptopBattery && battery.isPresent
    readonly property real percent: hasBattery ? battery.percentage : 1
    readonly property bool charging: hasBattery && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: hasBattery && battery.state === UPowerDeviceState.FullyCharged
    readonly property bool onBattery: UPower.onBattery
    // the batteries of things around the computer — a mouse, a keyboard,
    // headphones, a controller, a phone — that UPower reads (Bluetooth, HID++)
    readonly property var peripherals: UPower.devices.values.filter(d => !d.isLaptopBattery && !d.powerSupply && d.isPresent !== false && d.percentage > 0
        && d.model !== "")
    // Glass cannot import Services (Common → Services would be a cycle), so the
    // battery state for it is mirrored into Common/PowerState
    onOnBatteryChanged: { PowerState.onBattery = onBattery; if (onBattery) slowToldThisPlug = false; }
    Component.onCompleted: PowerState.onBattery = onBattery
    // a charger too slow for this computer (Charger.js): told once each time it is
    // plugged in. Event-driven: UPower's state changes start a one-shot check, no polling.
    readonly property bool drainingPluggedIn: hasBattery && !onBattery && battery.state === UPowerDeviceState.Discharging
    property real drainSince: 0
    property bool slowToldThisPlug: false
    onDrainingPluggedInChanged: {
        drainSince = drainingPluggedIn ? Date.now() : 0;
        if (drainingPluggedIn) {
            slowCheck.restart();
            checkSlow();                  // a real draw reading says it at once
        } else
            slowCheck.stop();
    }
    function checkSlow() {
        if (slowToldThisPlug || !drainingPluggedIn)
            return;
        if (Charger.tooSlow(onBattery, true, (Date.now() - drainSince) / 1000, Math.abs(battery.changeRate || 0))) {
            slowToldThisPlug = true;
            Quickshell.execDetached(["notify-send", "-a", Tr.t("Power"), "-i", "battery-caution",
                Tr.t("This charger is too slow"), Tr.t("The battery is still running down. A stronger charger (the one that came with this computer) will charge it.")]);
        }
    }
    Timer { id: slowCheck; interval: Charger.SUSTAINED_S * 1000 + 500; onTriggered: root.checkSlow() }
    // low: told once per device per discharge, below 15 %
    property var peripheralsWarned: ({})
    Timer {
        interval: 60000
        running: root.peripherals.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const w = Object.assign({}, root.peripheralsWarned);
            for (const d of root.peripherals) {
                const pct = d.percentage <= 1 ? d.percentage * 100 : d.percentage;
                if (pct < 15 && !w[d.nativePath]) {
                    w[d.nativePath] = true;
                    Quickshell.execDetached(["notify-send", "-a", "Power", "-i", d.iconName || "battery-caution", d.model + " is low on battery", Math.round(pct) + "% left"]);
                } else if (pct >= 25)
                    delete w[d.nativePath];
            }
            root.peripheralsWarned = w;
        }
    }
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
            if (Settings.data.autoLockOnLowBattery && !Lock.locked)
                Lock.lock();
        } else if (p <= 15 && warned > 15) {
            warned = 15;
            Quickshell.execDetached(["notify-send", "-a", "Power", "-i", "battery-level-10", "Battery low", p + "% left" + (timeLeft ? " · " + timeLeft : "")]);
        }
    }

    // battery saver (after Android): power saver at the set % on battery, the
    // previous profile back once charging — unless the person changed it since
    property int savedProfile: -1
    readonly property bool lowAndDischarging: hasBattery && !charging && Math.round(percent * 100) <= Settings.data.powerSaverAt
    onLowAndDischargingChanged: {
        if (!Settings.data.autoPowerSaver)
            return;
        if (lowAndDischarging && profile !== PowerProfile.PowerSaver) {
            savedProfile = GameMode.savedProfile >= 0 ? GameMode.savedProfile : profile;
            GameMode.savedProfile = -1;          // the game's profile ends here: the saver outranks it
            PowerProfiles.profile = PowerProfile.PowerSaver;
            Quickshell.execDetached(["notify-send", "-a", "Power", "-i", "power-profile-power-saver", "Battery saver on", "Power saver until you plug in"]);
        } else if (!lowAndDischarging && savedProfile >= 0) {
            // back: what the charger rule wants now, or else what was there before
            if (profile === PowerProfile.PowerSaver)
                PowerProfiles.profile = chargerWanted >= 0 ? chargerWanted : savedProfile;
            savedProfile = -1;
        }
    }

    // ---- the profile follows the charger (Settings > Power, off by default) --
    // Who decides, first to last:
    //   1. battery saver (at the set %, on battery): power saver until plugged in
    //   2. a game in fullscreen (GameMode): performance while it plays
    //   3. this rule: the chosen profile at each plug in and unplug
    //   4. the person's own pick (the tile, the bar): it holds until the next
    //      plug in or unplug - the rule acts at those moments only, never in between
    // So the saver is never undone by a plug event while it holds, a game keeps
    // performance, and each of them hands back to this rule (not to a stale
    // profile) when it ends.
    readonly property int chargerWanted: {
        const w = Charger.wantedProfile(Settings.data.profileFollowsCharger, hasBattery, onBattery,
                                        Settings.data.profileOnBattery, Settings.data.profilePluggedIn, hasPerformance);
        return w === "power-saver" ? PowerProfile.PowerSaver
             : w === "performance" ? PowerProfile.Performance
             : w === "balanced" ? PowerProfile.Balanced : -1;
    }
    property int chargerApplied: 0           // times the rule set the profile (for tests)
    function applyChargerRule() {
        if (chargerWanted < 0 || savedProfile >= 0 || GameMode.savedProfile >= 0)
            return;                          // off, or the saver or a game holds it
        if (profile !== chargerWanted) {
            PowerProfiles.profile = chargerWanted;
            chargerApplied++;
        }
    }
    // the moments it acts: plugged in or out, and the switch turned on or a choice made
    Connections {
        target: UPower
        function onOnBatteryChanged() { Qt.callLater(root.applyChargerRule); }
    }
    Connections {
        target: Settings.data
        function onProfileFollowsChargerChanged() { root.applyChargerRule(); }
        function onProfileOnBatteryChanged() { root.applyChargerRule(); }
        function onProfilePluggedInChanged() { root.applyChargerRule(); }
    }

    function cycleProfile() {
        const order = [PowerProfile.PowerSaver, PowerProfile.Balanced];
        if (hasPerformance)
            order.push(PowerProfile.Performance);
        PowerProfiles.profile = order[(order.indexOf(profile) + 1) % order.length];
    }

    // what logind can do here: suspend-then-hibernate (sleep, then hibernate after a
    // while or when the battery runs low - nothing lost to a flat battery) and
    // hybrid sleep (sleep with a copy on disk - safe from a power cut) both need
    // hibernation to work: swap large enough, resume configured
    property bool canSuspendThenHibernate: false
    property bool canHybridSleep: false
    readonly property string sleepVerb: {
        const s = Settings.loaded ? Settings.data.sleepStyle : "auto";
        if (s === "suspend-then-hibernate" && canSuspendThenHibernate) return s;
        if (s === "hybrid-sleep" && canHybridSleep) return s;
        if (s === "auto" && hasBattery && canSuspendThenHibernate) return "suspend-then-hibernate";
        return "suspend";
    }
    function suspend() { Quickshell.execDetached(["systemctl", root.sleepVerb]); }
    Process {
        running: true
        command: ["sh", "-c", 'for m in CanSuspendThenHibernate CanHybridSleep; do busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager $m 2>/dev/null || echo no; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                root.canSuspendThenHibernate = (l[0] || "").trim() === 's "yes"';
                root.canHybridSleep = (l[1] || "").trim() === 's "yes"';
            }
        }
    }
    // hibernate only where logind says it can (swap large enough, resume configured)
    property bool canHibernate: false
    function hibernate() { Quickshell.execDetached(["systemctl", "hibernate"]); }
    // into the firmware's own setup (UEFI) — where logind says it can
    property bool canFirmwareSetup: false
    function rebootToFirmware() { Quickshell.execDetached(["systemctl", "reboot", "--firmware-setup"]); }
    Process {
        running: true
        command: ["sh", "-c", 'busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanRebootToFirmwareSetup 2>/dev/null']
        stdout: StdioCollector { onStreamFinished: root.canFirmwareSetup = text.trim() === 's "yes"' }
    }
    Process {
        running: true
        command: ["sh", "-c", 'busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate 2>/dev/null']
        stdout: StdioCollector { onStreamFinished: root.canHibernate = text.trim() === 's "yes"' }
    }
    function reboot() { Quickshell.execDetached(["systemctl", "reboot"]); }
    function poweroff() { Quickshell.execDetached(["systemctl", "poweroff"]); }
    function logout() { Niri.action("quit", "--skip-confirmation"); }
}
