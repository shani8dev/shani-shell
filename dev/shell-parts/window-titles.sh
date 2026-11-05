# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=window-titles)
# ---- a window whose title ticks (a terminal's clock, a download's percent) costs little ----
# niri sends the whole window again for a title change; the shell's CPU while a
# title changes 10 times a second, beside the same seconds with nothing changing
# (measured: +290 ms/s when each change rebuilt the windows map, +35 ms/s after)
qpid=$(pgrep -o -x qs)
for n in 1 2 3; do foot -a shani-filler -T "Filler $n" sleep 600 >/dev/null 2>&1 & done
foot -a shani-ticker -T "tick start" sh -c 'i=0; while :; do printf "\033]2;tick %d\007" $i; i=$((i+1)); sleep 0.1; done' >/dev/null 2>&1 &
waitfor "d['windows'] >= 4" 8 || true
sleep 1
# behind another window: nothing on screen shows its title, so nothing should redraw
ipc windowFocus "Filler 1"
sleep 2
cputicks() { awk '{print $14+$15}' /proc/$qpid/stat; }
# the ticker running in front of nothing else: the shell's cost per second, 10 s
c0=$(cputicks); sleep 10; c1=$(cputicks)
ticking=$(( (c1 - c0) * 10 / 10 ))
pkill -f "tick %d" ; sleep 2
c0=$(cputicks); sleep 10; c1=$(cputicks)
quiet=$(( (c1 - c0) * 10 / 10 ))
extra=$((ticking - quiet))
echo "  title ticking 10/s: shell CPU ${ticking} ms/s, quiet ${quiet} ms/s"
[ "$extra" -le "${TITLE_TICK_BUDGET_MS:-80}" ] && result window-title-tick-cheap PASS "+${extra} ms/s for 10 title changes a second (${ticking} vs ${quiet})" \
    || result window-title-tick-cheap FAIL "+${extra} ms/s for 10 title changes a second (${ticking} vs ${quiet}; budget ${TITLE_TICK_BUDGET_MS:-80})"
pkill -f "shani-filler" 2>/dev/null; pkill -f "Filler" 2>/dev/null
# and a title shown still follows: the focused window's title on the bar, and the
# launcher finds a background window by its new title
foot -a shani-ticker -T "count start" sh -c 'sleep 1; printf "\033]2;count one\007"; sleep 1.5; printf "\033]2;count two\007"; sleep 600' >/dev/null 2>&1 &
waitfor "d['focusedTitle'] == 'count one'" 6 && waitfor "d['focusedTitle'] == 'count two'" 6 \
    && result window-title-follows PASS || result window-title-follows FAIL "$(q "['focusedTitle']")"
ipc windowFocus "Filler 2"; sleep 0.5
[ "$(qs -p /work/shani ipc call shani windowFocus "count two" 2>/dev/null)" = "focused count two" ] \
    && result window-title-found-by-new-title PASS || result window-title-found-by-new-title FAIL
pkill -f "count start" 2>/dev/null; pkill -f "count one" 2>/dev/null
