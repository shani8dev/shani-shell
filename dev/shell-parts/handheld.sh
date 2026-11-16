# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=handheld)
# ---- the handheld (docs/FORM-FACTORS.md step 3) ----
# The dev screen chosen as a handheld: everything 1.25 times larger, the TV home
# at arm's length, and the built-in pad as on a console - through InputPlumber
# (dev/fake-inputplumber.py, presses from /tmp/fake-inputplumber): the ⋯ button
# opens the quick panel over the game, Guide goes home and back to the game.
command -v winid >/dev/null 2>&1 || winid() { niri msg -j windows | python3 -c "import json,sys; print(next((w['id'] for w in json.load(sys.stdin) if w['app_id'] == '$1'), ''))"; }
F=/tmp/fake-inputplumber
hpress() { echo "$1 1" > $F; sleep 0.15; echo "$1 0" > $F; sleep 0.4; }
if [ -z "${SHANI_FORM_FACTOR:-}" ]; then
    settings '{"formFactors": {"winit": "handheld"}}'
    ipc tvHome true
    waitfor "d['formFactor'] == 'handheld' and abs(d['uiScale'] - 1.25) < 0.01 and d['tvHome']" 5 \
        && result handheld-scale-and-home PASS "$(q "['uiScale']")" || result handheld-scale-and-home FAIL "$(q "['formFactor'], d['uiScale'], d['tvHome']")"

    # a game in front (a window of its own)
    foot --app-id=handheld-game sh -c 'sleep 90' >/dev/null 2>&1 &
    i=0; until [ -n "$(winid handheld-game)" ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
    ipc tvHome false
    waitfor "d['ipRunning'] and not d['tvHome']" 5

    # Guide: the home over the game, and the controller is the desktop's
    hpress ui_guide
    waitfor "d['tvHome'] and d['ipBorrowed']" 3 && result handheld-guide-goes-home PASS || result handheld-guide-goes-home FAIL "$(q "['tvHome'], d['ipBorrowed'], d['ipLastEvent']")"

    # ⋯ opens the quick panel; the d-pad moves in it; OK changes the row
    hpress ui_quick
    waitfor "d['quickPanel'] and d['quickSelected'] != ''" 4 \
        && result handheld-quick-button-opens-the-panel PASS "$(q "['quickSelected']")" || result handheld-quick-button-opens-the-panel FAIL "$(q "['quickPanel'], d['quickSelected'], d['ipLastEvent']")"
    shot handheld-quick-panel 0.3
    q0=$(q "['quickSelected']")
    hpress ui_down
    q1=$(q "['quickSelected']")
    [ "$q0" != "$q1" ] && result handheld-quick-panel-arrows PASS "$q0 -> $q1" || result handheld-quick-panel-arrows FAIL "$q0 -> $q1, last $(q "['ipLastEvent']")"
    i=0; until [ "$(q "['quickSelected']")" = performance ] || [ $i -ge 4 ]; do hpress ui_down; i=$((i+1)); done
    p0=$(q "['powerProfile']")
    hpress ui_accept; sleep 0.5
    p1=$(q "['powerProfile']")
    [ "$(q "['quickSelected']")" = performance ] && [ "$p0" != "$p1" ] \
        && result handheld-quick-panel-changes-performance PASS "$p0 -> $p1" || result handheld-quick-panel-changes-performance FAIL "at $(q "['quickSelected']"): $p0 -> $p1"
    hpress ui_quick
    waitfor "not d['quickPanel'] and d['tvHome']" 3 && result handheld-quick-button-closes-it PASS || result handheld-quick-button-closes-it FAIL "$(q "['quickPanel'], d['tvHome']")"

    # Guide again: back to the game, and the controller with it
    hpress ui_guide
    waitfor "not d['tvHome'] and not d['ipBorrowed']" 4 \
        && result handheld-guide-back-to-the-game PASS || result handheld-guide-back-to-the-game FAIL "$(q "['tvHome'], d['ipBorrowed']")"

    w=$(winid handheld-game); [ -n "$w" ] && niri msg action close-window --id "$w" >/dev/null 2>&1
    ipc closeAll
    settings '{}'
    waitfor "d['formFactor'] == 'computer'" 5
fi
