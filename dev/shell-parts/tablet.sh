# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=tablet)
# ---- the tablet (docs/FORM-FACTORS.md step 4) ----
# The dev screen chosen as a tablet: everything 1.2 times larger, the edge strips
# up (a nested niri has no finger or pointer to swipe with, so each swipe's action
# runs through the edgeSwipe IPC - the same EdgeSwipe.run a finger reaches; which
# swipe a finger made is Common/Gestures.js, tests/test_gestures.py), and a text
# field touched brings up the screen keyboard.
if [ -z "${SHANI_FORM_FACTOR:-}" ]; then
    settings '{"formFactors": {"winit": "tablet"}}'
    waitfor "d['formFactor'] == 'tablet' and abs(d['uiScale'] - 1.2) < 0.01 and d['edgeStrips'] == 4" 5 \
        && result tablet-scale-and-edge-strips PASS "$(q "['uiScale'], d['edgeStrips']")" || result tablet-scale-and-edge-strips FAIL "$(q "['formFactor'], d['uiScale'], d['edgeStrips']")"
    ipc closeAll
    ipc edgeSwipe launcher
    waitfor "d['launcher']" 3 && result tablet-swipe-up-launcher PASS || result tablet-swipe-up-launcher FAIL "$(q "['edgeLast'], d['launcher']")"
    ipc edgeSwipe back
    waitfor "not d['launcher']" 3 && result tablet-swipe-back-closes-it PASS || result tablet-swipe-back-closes-it FAIL "$(q "['launcher']")"
    ipc edgeSwipe quick-settings
    waitfor "d['controlCenter']" 3 && result tablet-swipe-down-quick-settings PASS || result tablet-swipe-down-quick-settings FAIL "$(q "['controlCenter']")"
    shot tablet-quick-settings 0.3
    ipc closeAll
    # a text field gets the keyboard on a touch-first screen: the launcher's search
    ipc toggleLauncher; sleep 0.8
    waitfor "d['osk']" 3 && result tablet-text-field-brings-the-keyboard PASS || result tablet-text-field-brings-the-keyboard FAIL "$(q "['osk'], d['launcher']")"
    ipc closeAll; sleep 0.5
    waitfor "not d['osk']" 3 && result tablet-keyboard-goes-with-the-field PASS || result tablet-keyboard-goes-with-the-field FAIL "$(q "['osk']")"
    # a computer: no strips, and a text field does not bring the keyboard
    settings '{}'
    waitfor "d['formFactor'] == 'computer' and d['edgeStrips'] == 0" 5 \
        && result tablet-no-strips-on-a-computer PASS || result tablet-no-strips-on-a-computer FAIL "$(q "['formFactor'], d['edgeStrips']")"
    ipc toggleLauncher; sleep 0.8
    [ "$(q "['osk']")" = False ] && result tablet-no-keyboard-on-a-computer PASS || result tablet-no-keyboard-on-a-computer FAIL
    ipc closeAll
fi
