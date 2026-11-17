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
