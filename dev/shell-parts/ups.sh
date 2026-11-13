# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=ups)
# ---- the UPS a desktop runs on (Services/Ups, NUT via bridge/ups.py) ----
# dev/fake-upsc.sh stands in for `upsc`: /tmp/fake-ups holds its variables.
ups() { printf 'device.mfr: APC\ndevice.model: Back-UPS 1100\nups.status: %s\nbattery.charge: %s\nbattery.runtime: %s\nups.load: 23\n' "$1" "$2" "$3" > /tmp/fake-ups; ipc upsRefresh; }
[ "$(q "['upsPresent']")" = False ] && result ups-none-nothing-shown PASS || result ups-none-nothing-shown FAIL
ups OL 100 2700
waitfor "d['upsPresent'] and not d['upsOnBattery'] and d['upsCharge'] == 100" 5 \
    && result ups-found-on-mains PASS || result ups-found-on-mains FAIL "$(q "['upsPresent'], d['upsOnBattery'], d['upsCharge']")"
# a power cut: said at once, with the charge and the minutes left
ups "OB DISCHRG" 82 1500
waitfor "d['upsOnBattery'] and any(s.startswith('Power cut') for s in d['popupSummaries'])" 5 \
    && result ups-power-cut-said PASS || result ups-power-cut-said FAIL "$(q "['popupSummaries']")"
ipc settingsAt power ups; sleep 1.2; shot ups-settings 0.2; ipc closeAll
# low: critical; power back: said
ups "OB LB" 9 180
waitfor "d['upsLow'] and any('UPS battery is low' in s for s in d['popupSummaries'])" 5 \
    && result ups-low-is-critical PASS || result ups-low-is-critical FAIL "$(q "['popupSummaries']")"
ups "OL CHRG" 12 200
waitfor "not d['upsOnBattery'] and any(s.startswith('Power is back') for s in d['popupSummaries'])" 5 \
    && result ups-power-back-said PASS || result ups-power-back-said FAIL "$(q "['popupSummaries']")"
rm -f /tmp/fake-ups; ipc upsRefresh
