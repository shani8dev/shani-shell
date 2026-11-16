# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=laptop)
# ---- the laptop's layout follows its desk (docs/FORM-FACTORS.md step 5) ----
# A nested niri has one output and no built-in panel, so there is nothing to
# unplug: the state the service reads is driven through the IPC hook kept for
# it. What is checked is the promise - docked and on its own, the laptop each
# keeps the layout last used there, and a laptop that never leaves its desk
# changes nothing at all.
if [ -z "${SHANI_FORM_FACTOR:-}" ]; then
    settings '{"layoutFollowsDock": true, "layoutByDock": {}}'
    waitfor "d['dockState'] == '' and d['dockIcon'] == 48" 5 \
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

    # the owner can turn it off: the layout then stays where it is put
    settings '{"layoutFollowsDock": false, "dockIconSize": 40, "layoutByDock": {"docked": {"dockIconSize": 56}, "alone": {"dockIconSize": 40}}}'
    waitfor "d['dockIcon'] == 40" 4
    ipc dockingTest docked
    sleep 1
    waitfor "d['dockIcon'] == 40" 3 && result laptop-can-be-left-alone PASS \
        || result laptop-can-be-left-alone FAIL "$(q "['dockIcon']")"

    settings '{}'
    ipc dockingTest ""
    waitfor "d['dockState'] == ''" 3
fi