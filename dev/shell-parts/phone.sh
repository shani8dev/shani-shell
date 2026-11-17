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
    shot phone-quick-settings 0.4
    ipc closeAll
    settings '{}'
    waitfor "d['formFactor'] == 'computer' and not d['barNarrow']" 5 \
        && result phone-wide-screen-keeps-everything PASS || result phone-wide-screen-keeps-everything FAIL "$(q "['formFactor'], d['barNarrow']")"
fi
