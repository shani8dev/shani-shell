# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=inputplumber)
# ---- InputPlumber (shani-peripherals): controllers lent to the desktop over a game ----
# Against dev/fake-inputplumber.py on the system bus (InputPlumber 0.84's interfaces):
# the controller is listed with what it plays as; with controller navigation on it is
# in "pass" (a press goes to the game, the guide button comes here); the guide button
# opens Quick Settings and takes the controller, the d-pad moves there and the game
# sees nothing; closing hands it back; "plays as" and "manage every controller" reach
# InputPlumber.
F=/tmp/fake-inputplumber; L=/tmp/fake-inputplumber.log
press() { echo "$1 1" > $F; sleep 0.15; echo "$1 0" > $F; sleep 0.4; }
waitfor "d['ipRunning'] and len(d['ipDevices']) == 1" 8 \
    && result inputplumber-controller-listed PASS "$(q "['ipDevices']")" || result inputplumber-controller-listed FAIL "running $(q "['ipRunning']"), $(q "['ipDevices']")"
q "['ipDevices'][0]" | grep -q "Legion Go Controller Microsoft X-Box Elite" \
    && result inputplumber-plays-as-in-words PASS || result inputplumber-plays-as-in-words FAIL "$(q "['ipDevices']")"
waitfor "d['ipDevices'][0].endswith(' 1')" 5 && grep -q "^intercept=1$" $L \
    && result inputplumber-pass-mode-with-nav PASS || result inputplumber-pass-mode-with-nav FAIL "$(q "['ipDevices']"); $(tr '\n' ' ' < $L)"
[ "$(q "['gamepadNavRunning']")" = False ] && result inputplumber-raw-reader-steps-aside PASS || result inputplumber-raw-reader-steps-aside FAIL

# in "pass", the d-pad is the game's
ipc closeAll; sleep 0.5
press ui_down
grep -q "^to-game=ui_down$" $L && [ "$(q "['ipBorrowed']")" = False ] \
    && result inputplumber-game-keeps-the-dpad PASS || result inputplumber-game-keeps-the-dpad FAIL "$(tail -3 $L | tr '\n' ' ')"
# the guide button: Quick Settings, and the controller is the desktop's
press ui_guide
waitfor "d['controlCenter'] and d['ipBorrowed']" 4 \
    && result inputplumber-guide-opens-quick-settings PASS || result inputplumber-guide-opens-quick-settings FAIL "cc $(q "['controlCenter']"), borrowed $(q "['ipBorrowed']"), last $(q "['ipLastEvent']")"
before=$(grep -c "^to-game=" $L)
press ui_down
[ "$(q "['ipLastEvent']")" = ui_down ] && [ "$(grep -c "^to-game=" $L)" = "$before" ] \
    && result inputplumber-dpad-drives-the-desktop PASS || result inputplumber-dpad-drives-the-desktop FAIL "last $(q "['ipLastEvent']"); $(tail -2 $L | tr '\n' ' ')"
shot inputplumber-quick-settings 0.3
# closing gives the controller back to the game
ipc closeAll
waitfor "not d['ipBorrowed'] and d['ipDevices'][0].endswith(' 1')" 4 \
    && result inputplumber-closing-gives-it-back PASS || result inputplumber-closing-gives-it-back FAIL "$(q "['ipDevices']"), borrowed $(q "['ipBorrowed']")"

# Settings: what it plays as, and every controller
ipc settingsAt input in-games; sleep 1.5
ipc inputPlumberPlaysAs "/org/shadowblip/InputPlumber/CompositeDevice0" ds5
waitfor "'Sony DualSense' in d['ipDevices'][0]" 4 && grep -q "^targets=ds5,keyboard,mouse$" $L \
    && result inputplumber-plays-as-set PASS || result inputplumber-plays-as-set FAIL "$(q "['ipDevices']"); $(grep targets $L | tail -1)"
ipc inputPlumberManageAll true
waitfor "d['ipManageAll']" 4 && grep -q "^manageAll=true$" $L \
    && result inputplumber-manage-all PASS || result inputplumber-manage-all FAIL "$(grep manageAll $L | tail -1)"
shot inputplumber-settings 0.3
# navigation off: the controller is entirely the game's (mode 0)
settings '{"gamepadNav": false}'
waitfor "d['ipDevices'][0].endswith(' 0')" 4 && result inputplumber-nav-off-all-to-game PASS || result inputplumber-nav-off-all-to-game FAIL "$(q "['ipDevices']")"
settings '{}'
ipc closeAll
