# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=battery)
# ---- Settings > Power > Battery: health, history, what is busy ----
# upowerd in the container reads the host's /sys/class/power_supply: on a laptop
# this is the real battery; with none, the page stays hidden and that is checked
out=$(python3 /work/bridge/battery.py info)
if echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('present') else 1)"; then
    echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if 0 < d['health'] <= 110 and d['energyDesign'] > 0 else 1)" \
        && result battery-health-read PASS "$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['health'], '%,', d['cycles'], 'cycles')")" \
        || result battery-health-read FAIL "$out"
    n=$(python3 /work/bridge/battery.py history 604800 | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    [ "${n:-0}" -gt 0 ] && result battery-history-read PASS "$n points" || result battery-history-read FAIL "no history"
    ipc settingsCategory power; sleep 3; shot settings-battery 0.3
    ipc closeAll
else
    result battery-health-read SKIP "no battery here: $(echo "$out" | head -c 100)"
fi
