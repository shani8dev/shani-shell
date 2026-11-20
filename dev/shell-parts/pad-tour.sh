# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=pad-tour)
# ---- the whole desktop with a game controller only: every surface a pad opens ----
# Raw events into a FIFO the gamepad bridge reads (bridge/gamepad.py nav), no
# keyboard or pointer: Start Quick Settings, Y the launcher, Select the overview,
# X the window menu, LB/RB workspaces, a notification reached from Quick Settings,
# the lock screen. Each surface: it opens, the d-pad moves something there, A acts,
# B (or the same button) leaves - and the desktop is never left with no way back.
# InputPlumber stands aside for this (with it, the presses come through it instead:
# dev/shell-parts/inputplumber.sh).
pkill -f fake-inputplumber.py; waitfor "not d['ipRunning']" 5
cp /work/dev/input-devices.txt /tmp/input-devices
rm -f /tmp/fake-input/event21 /tmp/fake-input/event23; mkfifo /tmp/fake-input/event21 /tmp/fake-input/event23
exec 7<>/tmp/fake-input/event21 8<>/tmp/fake-input/event23
settings '{"gamepadNav": true, "gamepadHintDone": true}'
# a controller unplugged and another plugged in, as udev says it: the reader
# (stopped when the last pads' nodes closed) starts again for the new one. The
# same "add" again would change nothing - plugwatch already has that device.
sed 's/054C:0CE6/054C:0DF2/; s|5/54c/ce6|5/54c/df2|; s/^ACTION=add/ACTION=remove/; s/\] add /] remove /' /work/dev/udev/controller.txt > /tmp/udev-events
sleep 1
sed 's/054C:0CE6/054C:0E5F/; s|5/54c/ce6|5/54c/e5f|' /work/dev/udev/controller.txt > /tmp/udev-events
waitfor "d['gamepadNavRunning']" 8 && result pad-tour-reader PASS || { result pad-tour-reader FAIL "the controller reader never started"; return 0 2>/dev/null || exit 0; }
pad() { python3 -c "import struct,sys; sys.stdout.buffer.write(struct.pack('llHHi',0,0,1,int(sys.argv[1],16),1)+struct.pack('llHHi',0,0,1,int(sys.argv[1],16),0))" "$1" >&7; sleep "${2:-0.35}"; }
UP=0x220 DOWN=0x221 LEFT=0x222 RIGHT=0x223 A=0x130 B=0x131 X=0x134 Y=0x133 SELECT=0x13a START=0x13b LB=0x136 RB=0x137
ipc closeAll; sleep 0.5
foot -a pad-tour -T "Pad one" sleep 300 >/dev/null 2>&1 &
sleep 0.8
foot -a pad-tour -T "Pad two" sleep 300 >/dev/null 2>&1 &
waitfor "d['windows'] >= 2 and d['focusedTitle'] == 'Pad two'" 8

# Start: Quick Settings; the d-pad walks its tiles; B closes it
pad $START; waitfor "d['controlCenter'] and d['navFocus'] != ''" 4; f1=$(q "['navFocus']")
pad $DOWN; f2=$(q "['navFocus']"); pad $RIGHT; f3=$(q "['navFocus']")
[ -n "$f1" ] && [ "$f1" != "$f2" ] && [ "$f2" != "$f3" ] && result pad-tour-quick-settings-walks PASS "$f1 > $f2 > $f3" \
    || result pad-tour-quick-settings-walks FAIL "$f1 > $f2 > $f3"
[ "$(q "['controlCenter']")" = True ] && pad $B && waitfor "not d['controlCenter']" 3 && result pad-tour-quick-settings-b-closes PASS || result pad-tour-quick-settings-b-closes FAIL "open $(q "['controlCenter']")"

# Y: the launcher; the d-pad moves the highlight; B closes it
pad $Y; waitfor "d['launcher'] and d['launcherSelected'] != ''" 3; t1=$(q "['launcherSelected']")
pad $DOWN; t2=$(q "['launcherSelected']")
[ "$(q "['launcher']")" = True ] && [ -n "$t2" ] && [ "$t1" != "$t2" ] && result pad-tour-launcher-moves PASS "$t1 > $t2" \
    || result pad-tour-launcher-moves FAIL "launcher $(q "['launcher']"): '$t1' > '$t2'"
# its search field takes the keys by itself on opening: no screen keyboard over the results
[ "$(q "['osk']")" = False ] && result pad-tour-launcher-no-keyboard PASS || result pad-tour-launcher-no-keyboard FAIL "the keyboard came up over the launcher"
shot pad-tour-launcher 0.2
[ "$(q "['launcher']")" = True ] && pad $B && waitfor "not d['launcher']" 3 && result pad-tour-launcher-b-closes PASS || result pad-tour-launcher-b-closes FAIL "open $(q "['launcher']")"

# Select: the overview; the d-pad picks another window; A takes it
w1=$(q "['focusedTitle']")
pad $SELECT; waitfor "d['overview']" 3
pad $LEFT 0.6
shot pad-tour-overview 0.2
pad $A; waitfor "not d['overview'] and d['focusedTitle'] not in (None, '$w1')" 3   # niri names no focused window while the overview has the keys
w2=$(q "['focusedTitle']")
[ "$w1" != "$w2" ] && [ "$w2" = "Pad one" ] && [ "$(q "['overview']")" = False ] \
    && result pad-tour-overview-picks-a-window PASS "$w1 > $w2" || result pad-tour-overview-picks-a-window FAIL "'$w1' > '$w2', overview $(q "['overview']")"

# X: the focused window's menu; the d-pad walks it; B closes it
pad $X; waitfor "d['windowMenu']" 3; m1=$(q "['windowMenuSel']")
pad $DOWN; m2=$(q "['windowMenuSel']")       # the menu's own highlight (it is not KeyFocus's)
[ "$(q "['windowMenu']")" = True ] && [ -n "$m2" ] && [ "$m1" != "$m2" ] && result pad-tour-window-menu-walks PASS "$m1 > $m2" \
    || result pad-tour-window-menu-walks FAIL "menu $(q "['windowMenu']"): '$m1' > '$m2'"
[ "$(q "['windowMenu']")" = True ] && pad $B && waitfor "not d['windowMenu']" 3 && result pad-tour-window-menu-b-closes PASS || result pad-tour-window-menu-b-closes FAIL "open $(q "['windowMenu']")"

# LB / RB: the workspace before / after
ws1=$(q "['focusedWorkspace']"); pad $RB 0.6; ws2=$(q "['focusedWorkspace']"); pad $LB 0.6; ws3=$(q "['focusedWorkspace']")
[ "$ws1" != "$ws2" ] && [ "$ws3" = "$ws1" ] && result pad-tour-workspaces PASS "$ws1 > $ws2 > $ws3" || result pad-tour-workspaces FAIL "$ws1 > $ws2 > $ws3"

# a notification: shown as a pop-up, reached from Quick Settings with the d-pad alone
notify-send -a "Pad tour" "Pad tour message" "from a game" ; waitfor "d['popups'] >= 1" 4
pad $START; waitfor "d['controlCenter']" 3
# LB / RB jump a section (a controller's Shift+Tab / Tab): the notifications are
# the last section, so one LB from the top wraps to them, then Down onto the card
# - three presses, not 30-odd Downs through every tile
seen=""; pad $LB 0.4; seen="$seen > $(q "['navFocus']")"; i=1
until q "['navFocus']" | grep -q "Pad tour" || [ $i -ge 5 ]; do pad $DOWN 0.25; i=$((i+1)); seen="$seen > $(q "['navFocus']")"; done
q "['navFocus']" | grep -q "Pad tour" && result pad-tour-reaches-a-notification PASS "$i presses: $(q "['navFocus']")" \
    || result pad-tour-reaches-a-notification FAIL "not in $i presses:$seen"
shot pad-tour-notification 0.2
pad $B; waitfor "not d['controlCenter']" 3
# ...and with Down alone, from the top: through every tile and the note to type in
# (a few lines that must let the d-pad out at their edges), to the same card
pad $START; waitfor "d['controlCenter'] and d['navFocus'] != ''" 3
downs=0; until q "['navFocus']" | grep -q "Pad tour" || [ $downs -ge 70 ]; do pad $DOWN 0.12; downs=$((downs+1)); done
q "['navFocus']" | grep -q "Pad tour" && result pad-tour-down-walks-all-of-quick-settings PASS "$downs presses" \
    || result pad-tour-down-walks-all-of-quick-settings FAIL "stopped at '$(q "['navFocus']")' after $downs"
pad $B; waitfor "not d['controlCenter']" 3 && result pad-tour-quick-settings-b-closes-anywhere PASS || result pad-tour-quick-settings-b-closes-anywhere FAIL "still open"

# Guide: the assistant's conversation; Guide again closes it
pad 0x13c; waitfor "d['chronoaOpen']" 3 && result pad-tour-guide-assistant PASS || result pad-tour-guide-assistant FAIL "open $(q "['chronoaOpen']")"
[ "$(q "['chronoaOpen']")" = True ] && pad 0x13c && waitfor "not d['chronoaOpen']" 3

# one of the shell's apps: X on something with no menu of its own opens the
# window's menu (close, move...), B closes it; the d-pad onto a text field brings
# the screen keyboard, driven by the pad; B hides it
ipc passwordsOpen; waitfor "d['passwordsShown'] and d['focusedTitle'] == 'Passwords and Keys'" 4
pad $X; waitfor "d['windowMenu']" 3 && result pad-tour-app-x-window-menu PASS || result pad-tour-app-x-window-menu FAIL "window '$(q "['focusedTitle']")', focus '$(q "['navFocus']")', menu $(q "['windowMenu']")"
[ "$(q "['windowMenu']")" = True ] && pad $B && waitfor "not d['windowMenu']" 3
sleep 0.4
[ "$(q "['osk']")" = False ] && result pad-tour-no-keyboard-unasked PASS || result pad-tour-no-keyboard-unasked FAIL "the keyboard came up before a field was reached"
seen=""; presses=0         # (not i: waitfor counts with that)
until [ "$(q "['textFocus']")" = True ] || [ $presses -ge 8 ]; do pad $RIGHT 0.3; presses=$((presses+1)); seen="$seen > $(q "['navFocus']")"; done
waitfor "d['osk'] and d['oskPadDriven'] and d['textByKeys']" 3 && result pad-tour-field-brings-keyboard PASS "$presses presses:$seen" \
    || result pad-tour-field-brings-keyboard FAIL "field $(q "['textFocus']"), keyboard $(q "['osk']") pad $(q "['oskPadDriven']"):$seen"
shot pad-tour-field-keyboard 0.2
pad $B; waitfor "not d['osk']" 3 && result pad-tour-keyboard-b-hides PASS || result pad-tour-keyboard-b-hides FAIL "still shown"
ipc closeAll

# a document being edited: RB goes on to the next control, typing nothing into it
# (a Tab keystroke would have put a tab character in the text)
ipc textEditorNew; ipc textEditorSetText "abc"; waitfor "d['textEditor'] and d['focusedTitle'].endswith('Text Editor')" 4
c1=$(q "['textEditorChars']"); pad $RB 0.5; c2=$(q "['textEditorChars']")
[ "$c1" = "$c2" ] && [ -n "$(q "['navFocus']")" ] && result pad-tour-rb-leaves-a-document PASS "focus '$(q "['navFocus']")'" \
    || result pad-tour-rb-leaves-a-document FAIL "'$c1' > '$c2', focus '$(q "['navFocus']")'"
ipc closeAll

# the lock screen: the d-pad reaches its buttons, and B does not leave it
echo 'root:shani-test' | chpasswd     # the main script sets it; a solo run of this part has none
ipc lock; waitfor "d['locked']" 6; sleep 1
l1=$(q "['navFocus']"); pad $DOWN; pad $DOWN; l2=$(q "['navFocus']"); pad $B
[ "$(q "['locked']")" = True ] && [ "$l1" != "$l2" ] && result pad-tour-lock-screen PASS "'$l1' > '$l2'" \
    || result pad-tour-lock-screen FAIL "locked $(q "['locked']"): '$l1' > '$l2'"
shot pad-tour-lock 0.2
unlock

pkill -f "sleep 300"; settings '{}'
exec 7>&- 8>&-
python3 /work/dev/fake-inputplumber.py >/work/out/logs/fake-inputplumber.log 2>&1 &
waitfor "d['ipRunning']" 8
