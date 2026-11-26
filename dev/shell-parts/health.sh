# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=health)
# ---- Health: the local journal and an optional paired watch, both behind
#      bridge/health.py. dev/fake-watch.py writes the watch answer the bridge
#      overlays; a few journal rows are logged through the real bridge CLI.
#      No account, no cloud and no hardware in the dev container.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
WATCH_FAKE=/work/dev/fake-watch.py
HEALTH_TOOL=/work/bridge/health.py
export SHANI_WATCH_FAKE=/tmp/fake-watch.json
export SHANI_FITNESS_TOOL=${SHANI_FITNESS_TOOL:-/work/bridge/health.py}
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/shani-shell"
HEALTH_DB="$DATA_HOME/health.sqlite3"
FULL_DB=/tmp/health-part-full.sqlite3
OLD_DB=/tmp/health-part-old.sqlite3

health_press() {
    for label in "$@"; do
        timeout 20 python3 "$A11Y" press "$label" >/dev/null 2>&1 && return 0
    done
    return 1
}

# one watch, the same fields every run
python3 "$WATCH_FAKE" seed >/dev/null
python3 "$HEALTH_TOOL" summary 2>/dev/null | grep -q '"device_model": "Pulse Watch 2"' \
    && result health-watch-stand-in PASS \
    || result health-watch-stand-in FAIL "$(python3 "$HEALTH_TOOL" summary 2>&1 | tail -1)"

# a clean journal with three days of steps, one sleep and one workout
rm -f "$FULL_DB" "$OLD_DB"
had_db=0
if [ -f "$HEALTH_DB" ]; then mv "$HEALTH_DB" "$OLD_DB"; had_db=1; fi
today=$(date +%F)
yesterday=$(date -d '1 day ago' +%F)
two_days=$(date -d '2 days ago' +%F)
python3 "$HEALTH_TOOL" log step 8432 "$today" >/dev/null
python3 "$HEALTH_TOOL" log step 7120 "$yesterday" >/dev/null
python3 "$HEALTH_TOOL" log step 5980 "$two_days" >/dev/null
python3 "$HEALTH_TOOL" log sleep 92 240 18 "$today" >/dev/null
python3 "$HEALTH_TOOL" log workout Walking 35 3200 180 "$today" >/dev/null
python3 "$HEALTH_TOOL" history 3 2>/dev/null | grep -q '"steps": 5980' \
    && result health-journal-seeded PASS || result health-journal-seeded FAIL "$(python3 "$HEALTH_TOOL" history 3 2>&1)"
python3 "$HEALTH_TOOL" workouts 2>/dev/null | grep -q '"kind": "Walking"' \
    && result health-workout-seeded PASS || result health-workout-seeded FAIL "$(python3 "$HEALTH_TOOL" workouts 2>&1)"

# ---- the dashboard ------------------------------------------------------------
ipc healthOpen
waitfor "d['healthShown'] == True" 8 \
    && result health-opens PASS || result health-opens FAIL "$(q "['healthShown']")"
waitfor "d['healthModel'] == 'Pulse Watch 2'" 20 \
    && result health-header PASS || result health-header FAIL "$(q "['healthModel']")"
waitfor "d['healthBattery'] == 76 and d['healthSteps'] == 8432" 10 \
    && result health-readings PASS || result health-readings FAIL "$(q "['healthBattery'], d['healthSteps']")"
waitfor "'09:30' in d['healthLastRead']" 8 \
    && result health-last-read PASS || result health-last-read FAIL "$(q "['healthLastRead']")"
waitfor "d['healthSleepStages'] == 4 and d['healthStressPoints'] == 8" 10 \
    && result health-charts-data PASS || result health-charts-data FAIL "$(q "['healthSleepStages'], d['healthStressPoints']")"

if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" find "Pulse Watch 2" >/dev/null 2>&1 \
        && result health-header-model PASS || result health-header-model FAIL "no model in the header"
    timeout 20 python3 "$A11Y" find "76 percent" >/dev/null 2>&1 \
        && result health-header-battery PASS || result health-header-battery FAIL "no battery in the header"
    timeout 20 python3 "$A11Y" find "Read at 09:30" >/dev/null 2>&1 \
        && result health-header-time PASS || result health-header-time FAIL "no read time in the header"
    timeout 20 python3 "$A11Y" find "8432 of 10000 steps" >/dev/null 2>&1 \
        && result health-activity-ring PASS || result health-activity-ring FAIL "the activity ring has no reading"
    timeout 20 python3 "$A11Y" find "2 days ago: 5980 steps" >/dev/null 2>&1 \
        && result health-three-day-bars PASS || result health-three-day-bars FAIL "the last three days are not drawn"
    timeout 20 python3 "$A11Y" find "Deep:" >/dev/null 2>&1 \
        && result health-sleep-stages PASS || result health-sleep-stages FAIL "no sleep stages drawn"
    timeout 20 python3 "$A11Y" find "Stress over today" >/dev/null 2>&1 \
        && result health-stress-chart PASS || result health-stress-chart FAIL "no stress chart"
    timeout 20 python3 "$A11Y" find "Walking" >/dev/null 2>&1 \
        && result health-workouts PASS || result health-workouts FAIL "the workout is not listed"

    health_press "button:^Read the watch again$" \
        && result health-refresh-button PASS || result health-refresh-button FAIL "no watch refresh button"
    waitfor "d['healthBattery'] == 76" 8 \
        && result health-refresh PASS || result health-refresh FAIL "$(q "['healthBattery']")"

    # the companion switch is a real read/write, not a decoration
    health_press "switch:^Keep my watch connected to this computer$" "check box:^Keep my watch connected to this computer$" \
        && result health-connected-switch PASS || result health-connected-switch FAIL "no companion switch"
    waitfor "d['healthConnected'] == False" 8 \
        && result health-disconnect PASS || result health-disconnect FAIL "$(q "['healthConnected']")"
    health_press "switch:^Keep my watch connected to this computer$" "check box:^Keep my watch connected to this computer$"
    waitfor "d['healthConnected'] == True" 8 \
        && result health-reconnect PASS || result health-reconnect FAIL "$(q "['healthConnected']")"
else
    for n in header-model header-battery header-time activity-ring \
             three-day-bars sleep-stages stress-chart workouts refresh-button refresh \
             connected-switch disconnect reconnect; do
        result health-$n SKIP "no accessibility client"
    done
fi
shot health-dashboard 0.4

# ---- no watch, no journal: one honest empty state -----------------------------
ipc healthClose
python3 "$WATCH_FAKE" empty >/dev/null
[ -f "$HEALTH_DB" ] && mv "$HEALTH_DB" "$FULL_DB"
ipc healthOpen
waitfor "d['healthShown'] and not d['healthConnected'] and d['healthModel'] == ''" 10 \
    && result health-empty-data PASS || result health-empty-data FAIL "$(q "['healthConnected'], d['healthModel']")"
waitfor "d['healthSteps'] == 0" 8
if [ -f "$A11Y" ]; then
    sleep 0.6
    timeout 20 python3 "$A11Y" find "No watch yet" >/dev/null 2>&1 \
        && result health-empty-state PASS || result health-empty-state FAIL "no empty state"
    timeout 20 python3 "$A11Y" find "Connect a watch" >/dev/null 2>&1 \
        && result health-empty-action PASS || result health-empty-action FAIL "the empty state has no way forward"
else
    result health-empty-state SKIP "no accessibility client"
    result health-empty-action SKIP "no accessibility client"
fi
shot health-empty 0.4
ipc healthClose

# leave the session as it was found
[ -f "$FULL_DB" ] && mv "$FULL_DB" "$HEALTH_DB"
[ "$had_db" = 0 ] && rm -f "$HEALTH_DB"
[ "$had_db" = 1 ] && [ -f "$OLD_DB" ] && mv "$OLD_DB" "$HEALTH_DB"
python3 "$WATCH_FAKE" seed >/dev/null
