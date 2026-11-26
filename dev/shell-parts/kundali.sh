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

# the window offers every section as a chip beside the chart
ipc kundaliOpen
waitfor "d['kundali']" 6 && result kundali-opens PASS || result kundali-opens FAIL "$(q "['kundali']")"
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "radio button:^Kundali$" >/dev/null 2>&1
    for label in Chart "Dasha periods" Ashtakavarga "Planetary dignity" Aspects "Nakshatra details" Eclipses; do
        timeout 20 python3 "$A11Y" find "radio button:^$label$" >/dev/null 2>&1 \
            && result "kundali-chip-${label// /-}" PASS \
            || result "kundali-chip-${label// /-}" FAIL "no chip: $label"
    done
else
    for label in Chart "Dasha periods" Ashtakavarga "Planetary dignity" Aspects "Nakshatra details" Eclipses; do
        result "kundali-chip-${label// /-}" SKIP "no accessibility client"
    done
fi
shot kundali-sections 0.3
ipc kundaliClose
ipc closeAll
