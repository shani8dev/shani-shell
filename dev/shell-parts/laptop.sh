# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=laptop)
# ---- the laptop's layout follows its desk (docs/FORM-FACTORS.md step 5) ----
# A nested niri has one output and no built-in panel, so there is nothing to
# unplug: the state the service reads is driven through the IPC hook kept for
# it. What is checked is the promise - docked and on its own, the laptop each
# keeps the layout last used there, and a laptop that never leaves its desk
# changes nothing at all.
if [ -z "${SHANI_FORM_FACTOR:-}" ]; then
    settings '{"layoutFollowsDock": true, "layoutByDock": {}}'
    # without a built-in panel the situation is the desktop's own screen
    waitfor "d['dockState'] == 'screen' and d['dockIcon'] == 48" 5 \
        && result laptop-no-desk-without-a-panel PASS || result laptop-no-desk-without-a-panel FAIL "$(q "['dockState'], d['dockIcon']")"

    ipc dockingTest docked
    waitfor "d['dockState'] == 'docked'" 3 && result laptop-docked PASS || result laptop-docked FAIL "$(q "['dockState']")"
    ipc setting dockIconSize 56
    waitfor "d['dockIcon'] == 56" 4 && result laptop-docked-layout-set PASS || result laptop-docked-layout-set FAIL "$(q "['dockIcon']")"

    ipc dockingTest alone
    waitfor "d['dockState'] == 'alone'" 3 && result laptop-undocked PASS || result laptop-undocked FAIL "$(q "['dockState']")"
    # nothing remembered for "on its own" yet: the layout stays as it is
    waitfor "d['dockIcon'] == 56" 3 && result laptop-first-time-keeps-its-layout PASS \
        || result laptop-first-time-keeps-its-layout FAIL "$(q "['dockIcon']")"
    ipc setting dockIconSize 40
    waitfor "d['dockIcon'] == 40" 4

    ipc dockingTest docked
    waitfor "d['dockIcon'] == 56" 4 && result laptop-docked-remembers-its-own PASS \
        || result laptop-docked-remembers-its-own FAIL "$(q "['dockIcon']")"
    ipc dockingTest alone
    waitfor "d['dockIcon'] == 40" 4 && result laptop-undocked-remembers-its-own PASS \
        || result laptop-undocked-remembers-its-own FAIL "$(q "['dockIcon']")"

    # folded into a tablet: the first time, the layout made for a tablet, said so;
    # unfolded, the laptop's own comes back; folded again, the tablet's as it was left
    ipc dockingTest alone:tablet
    waitfor "d['dockStarted'] == 'alone:tablet' and d['layoutPreset'] == 'tablet' and d['dockIcon'] == 64" 5 \
        && result layout-folded-starts-in-touch PASS || result layout-folded-starts-in-touch FAIL "$(q "['dockStarted'], d['layoutPreset'], d['dockIcon']")"
    shot layout-folded-tablet 0.5
    ipc setting dockIconSize 72
    waitfor "d['dockIcon'] == 72" 4
    ipc dockingTest alone
    waitfor "d['dockIcon'] == 40" 4 && result layout-unfolded-laptop-back PASS || result layout-unfolded-laptop-back FAIL "$(q "['dockIcon']")"
    ipc dockingTest alone:tablet
    waitfor "d['dockIcon'] == 72" 4 && result layout-folded-again-as-left PASS || result layout-folded-again-as-left FAIL "$(q "['dockIcon']")"
    ipc dockingTest alone

    # the owner can turn it off: the layout then stays where it is put
    settings '{"layoutFollowsDock": false, "dockIconSize": 40, "layoutByDock": {"docked": {"dockIconSize": 56}, "alone": {"dockIconSize": 40}}}'
    waitfor "d['dockIcon'] == 40" 4
    ipc dockingTest docked
    sleep 1
    waitfor "d['dockIcon'] == 40" 3 && result laptop-can-be-left-alone PASS \
        || result laptop-can-be-left-alone FAIL "$(q "['dockIcon']")"

    settings '{}'
    ipc dockingTest ""
    waitfor "d['dockState'] == 'screen'" 3
fi