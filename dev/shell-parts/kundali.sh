# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=kundali)
# ---- Kundali: the chart sections against the real local astronomy module,
#      then the window with its section chips. No network, no clock defaults.
TOOL=/work/bridge/kundali.py
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
WHEN=1990-01-01T12:00:00Z
LAT=28.6139
LON=77.2090

for spec in dasha:periods ashtakavarga:rows dignity:planets aspects:aspects nakshatra:nakshatra eclipse:lunar_eclipse; do
    section=${spec%%:*}; key=${spec#*:}
    out=$(python3 "$TOOL" details "$section" "$WHEN" "$LAT" "$LON" 2>/dev/null)
    if printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if not d.get("error") and (d.get(sys.argv[1]) is not None) else 1)' "$key"; then
        result "kundali-$section-data" PASS
    else
        result "kundali-$section-data" FAIL "$(printf '%s' "$out" | head -c 180)"
    fi
done

# a missing place is an error, not a silent trip to New Delhi
out=$(python3 "$TOOL" panchang 2024-01-01 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '"error": "missing' \
    && result kundali-missing-args PASS || result kundali-missing-args FAIL "$out"

# the window opens
ipc kundaliOpen
waitfor "d['kundali']" 6 && result kundali-opens PASS || result kundali-opens FAIL "$(q "['kundali']")"
shot kundali-sections 0.8
ipc kundaliClose

# a birth charted at once (IPC kundaliChart): Pune, 1 January 1990, 12:00 there
ipc kundaliChart 1990-01-01 12:00 18.5204 73.8567 Asia/Kolkata Pune
waitfor "d['kundali']" 6 && result kundali-chart-opens PASS || result kundali-chart-opens FAIL "$(q "['kundali']")"
shot kundali-chart 4
# every section is a tab beside the chart (once there is one, the birth form
# folds away and the tabs are on screen)
labels='Chart|Dasha periods|Ashtakavarga|Planetary dignity|Aspects|Nakshatra details|Eclipses'
if [ -f "$A11Y" ]; then
    printf '%s\n' "$labels" | tr '|' '\n' | while read -r label; do
        timeout 20 python3 "$A11Y" find "radio button:^$label$" >/dev/null 2>&1 \
            && result "kundali-chip-$(printf %s "$label" | tr ' ' -)" PASS \
            || result "kundali-chip-$(printf %s "$label" | tr ' ' -)" FAIL "no chip: $label"
    done
    # the three ways India draws a chart
    timeout 20 python3 "$A11Y" press "radio button:^South Indian chart$" >/dev/null 2>&1; shot kundali-chart-south 1.5
    timeout 20 python3 "$A11Y" press "radio button:^East Indian chart$" >/dev/null 2>&1; shot kundali-chart-east 1.5
    timeout 20 python3 "$A11Y" press "radio button:^North Indian chart$" >/dev/null 2>&1
    timeout 20 python3 "$A11Y" press "radio button:^Ashtakavarga$" >/dev/null 2>&1; shot kundali-ashtakavarga 2.5
    timeout 20 python3 "$A11Y" press "radio button:^Every calculation$" >/dev/null 2>&1
    timeout 20 python3 "$A11Y" press "radio button:^Strength$" >/dev/null 2>&1
    timeout 20 python3 "$A11Y" press "radio button:^Shadbala$" >/dev/null 2>&1; shot kundali-calculation 3
else
    printf '%s\n' "$labels" | tr '|' '\n' | while read -r label; do
        result "kundali-chip-$(printf %s "$label" | tr ' ' -)" SKIP "no accessibility client"
    done
fi
ipc kundaliClose

# a saved chart gets a notice before a hard day: 2 December 2026 (the
# harness's today) is chandrashtama for this birth (Moon in Virgo, the 8th
# from its Aquarius Moon)
ipc kundaliSave 1990-01-01 12:00 18.5204 73.8567 Asia/Kolkata Asha
waitfor "d['kundaliSaved'] == 1" 5 && result kundali-saved PASS || result kundali-saved FAIL "$(q "['kundaliSaved']")"
waitfor "any('Asha' in s and 'hard' in s for s in d['kundaliNotices'])" 15 \
    && result kundali-hard-day-notice PASS || result kundali-hard-day-notice FAIL "$(q "['kundaliNotices']")"
shot kundali-notice 0.5
ipc kundaliChart 1990-01-01 12:00 18.5204 73.8567 Asia/Kolkata Pune
waitfor "d['kundali']" 6
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "radio button:^Days ahead$" >/dev/null 2>&1; shot kundali-ahead 3
fi
ipc kundaliClose

# the day's panchang, as the calendar asks for it
ipc kundaliPanchang 2026-10-19 18.5204 73.8567 Asia/Kolkata Pune
waitfor "d['kundali']" 6 && result kundali-panchang-opens PASS || result kundali-panchang-opens FAIL "$(q "['kundali']")"
shot kundali-panchang 4
ipc kundaliClose
ipc closeAll
