# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=phone)
# ---- the phone (docs/FORM-FACTORS.md step 7) ----
# The dev screen chosen as a phone: one column. The bar keeps the launcher, the
# status cluster and the clock, and drops the workspaces, the world clock and
# the date - they are what overflows a 412-point screen.
if [ -z "${SHANI_FORM_FACTOR:-}" ]; then
    settings '{"formFactors": {"winit": "phone"}}'
    waitfor "d['formFactor'] == 'phone' and abs(d['uiScale'] - 1.15) < 0.01" 5 \
        && result phone-scale PASS || result phone-scale FAIL "$(q "['formFactor'], d['uiScale']")"
    waitfor "d['barNarrow']" 5 && result phone-bar-is-one-column PASS \
        || result phone-bar-is-one-column FAIL "$(q "['barNarrow']")"
    # at a phone's width the two clusters must still leave a gap between them
    waitfor "not d['barOverlap']" 5 && result phone-bar-fits PASS \
        || result phone-bar-fits FAIL "the clusters meet at this width"
    shot phone-bar 0.4
    # one app at a time: niri opens every window fullscreen on a phone. The rule
    # is read back from the file the shell writes, checked with niri's own parser,
    # and then with a real window - a fullscreen one is as tall as the screen.
    kdl="${XDG_CONFIG_HOME:-$HOME/.config}/niri/shani-windows.kdl"
    i=0; until grep -q "open-fullscreen" "$kdl" 2>/dev/null || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
    grep -q "open-fullscreen" "$kdl" 2>/dev/null && result phone-windows-open-fullscreen PASS \
        || result phone-windows-open-fullscreen FAIL "niri was not told"
    niri validate -c "$kdl" >/dev/null 2>&1 && result phone-niri-accepts-the-rule PASS \
        || result phone-niri-accepts-the-rule FAIL "niri cannot read what was written"
    foot --app-id=fs-test sh -c 'sleep 25' >/dev/null 2>&1 &
    i=0; until [ -n "$(niri msg -j windows | python3 -c 'import json,sys
print(next((w["id"] for w in json.load(sys.stdin) if w["app_id"] == "fs-test"), ""))' 2>/dev/null)" ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
    tall=$(niri msg -j windows | python3 -c 'import json,sys
for w in json.load(sys.stdin):
    if w["app_id"] == "fs-test":
        print(int(w["layout"]["tile_size"][1])); break' 2>/dev/null)
    [ "${tall:-0}" -ge 800 ] && result phone-a-window-is-fullscreen PASS "$tall px" \
        || result phone-a-window-is-fullscreen FAIL "a window opened ${tall:-0} px tall"
    niri msg action close-window --id "$(niri msg -j windows | python3 -c 'import json,sys
print(next((w["id"] for w in json.load(sys.stdin) if w["app_id"] == "fs-test"), ""))' 2>/dev/null)" 2>/dev/null
    # the two surfaces a phone opens most still open at this width
    ipc launcher ""
    waitfor "d['launcher']" 4 && result phone-launcher-opens PASS || result phone-launcher-opens FAIL
    waitfor "d['launcherNarrow']" 4 && result phone-launcher-is-one-column PASS \
        || result phone-launcher-is-one-column FAIL "$(q "['launcherNarrow']")"
    shot phone-launcher 0.4
    ipc closeAll
    ipc toggleControlCenter
    waitfor "d['controlCenter']" 4 && result phone-quick-settings-opens PASS || result phone-quick-settings-opens FAIL
    waitfor "d['sidebarShade']" 4 && result phone-quick-settings-is-a-shade PASS \
        || result phone-quick-settings-is-a-shade FAIL "$(q "['sidebarShade']")"
    shot phone-quick-settings 0.4
    ipc closeAll
    # a notification is a card the width of the screen, not 437 of 412
    notify-send -a shani-test "Hello" "a card the width of the phone"
    sleep 1
    shot phone-notification 0.4
    # the lock screen, at a phone's width: the password has to exist first - the
    # suite sets it before its own lock checks, and a part runs before those
    echo 'root:shani-test' | chpasswd
    ipc lock
    waitfor "d['locked']" 6 && result phone-lock-screen PASS || result phone-lock-screen FAIL
    shot phone-lock 0.4
    unlock
    waitfor "not d['locked']" 8 && result phone-unlocks PASS || result phone-unlocks FAIL "$(q "['locked']")"
    settings '{}'
    waitfor "d['formFactor'] == 'computer' and not d['barNarrow']" 5 \
        && result phone-wide-screen-keeps-everything PASS || result phone-wide-screen-keeps-everything FAIL "$(q "['formFactor'], d['barNarrow']")"
fi
