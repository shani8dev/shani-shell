# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=background)
# ---- Background: this part opens Ui.backgroundServices with `ipc backgroundOpen`
#      below, so the suite covers the surface the same way a person would.
#      Same PhoneTools switches as Settings, grouped in their own page. The
#      stand-in is dev/fake-phone-tools.py; a toggle must reach its state file.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
press() {
    for label in "$@"; do
        timeout 20 python3 "$A11Y" press "$label" >/dev/null 2>&1 && return 0
    done
    return 1
}
seen() { timeout 20 python3 "$A11Y" find "$1" >/dev/null 2>&1; }

ipc backgroundOpen
waitfor "d['backgroundShown'] == True" 8 \
    && result background-opens PASS || result background-opens FAIL "$(q "['backgroundShown']")"
waitfor "d['backgroundSwitches'] == 14" 10 \
    && result background-switches-listed PASS "$(q "['backgroundSwitches'], d['backgroundOn']")" \
    || result background-switches-listed FAIL "$(q "['backgroundSwitches'], d['backgroundOn']")"
shot background-page 0.5
before=$(q "['backgroundOn']")

if [ -f "$A11Y" ]; then
    for group in Phone Watch Music; do
        seen "$group" && result background-group-$group PASS \
            || result background-group-$group FAIL "no $group group"
    done
    press "switch:^Receive files$" "check box:^Receive files$" \
        && result background-switch-pickable PASS \
        || result background-switch-pickable FAIL "the Receive files switch was not pressable"
    # the stand-in's starting value depends on the state file left by earlier
    # parts, so prove the click changed the count and a second click restored it
    waitfor "d['backgroundOn'] != $before" 8 \
        && result background-switch-toggles PASS "$(q "['backgroundOn']") (was $before)" \
        || result background-switch-toggles FAIL "$(q "['backgroundOn']")"
    press "switch:^Receive files$" "check box:^Receive files$"
    waitfor "d['backgroundOn'] == $before" 8 \
        && result background-switch-restores PASS "$(q "['backgroundOn']")" \
        || result background-switch-restores FAIL "$(q "['backgroundOn']")"
else
    for n in group-Phone group-Watch group-Music switch-pickable switch-toggles switch-restores; do
        result background-$n SKIP "no accessibility client"
    done
fi

ipc backgroundClose
waitfor "d['backgroundShown'] == False" 6 \
    && result background-closes PASS || result background-closes FAIL "$(q "['backgroundShown']")"
