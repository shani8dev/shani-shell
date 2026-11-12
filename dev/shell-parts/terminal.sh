# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=terminal)
# ---- the terminal: the chosen one everywhere, foot in the desktop's colours, Chronoa from foot ----
FOOT=/root/.config/foot/foot.ini
LIST=/root/.config/niri-xdg-terminals.list
waitfor "d['terminalFoot'] == 'written' and d['terminalList'] == 'written'" 8
head -n1 "$FOOT" | grep -q "written by shani-shell" && foot --check-config >/tmp/foot-check 2>&1 \
    && result terminal-foot-theme-loads PASS || result terminal-foot-theme-loads FAIL "$(head -c 300 /tmp/foot-check; head -3 "$FOOT" 2>&1)"
grep -qx footclient.desktop "$LIST" && result terminal-list-default-footclient PASS || result terminal-list-default-footclient FAIL "$(cat "$LIST" 2>&1)"
# picking another terminal: the list Mod+Return reads (xdg-terminal-exec) follows
settings '{"terminal": "foot"}'
i=0; until grep -qx foot.desktop "$LIST" 2>/dev/null || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
grep -qx foot.desktop "$LIST" && result terminal-list-follows-choice PASS || result terminal-list-follows-choice FAIL "$(cat "$LIST" 2>&1)"

# an open foot window turns light with the desktop (SIGUSR2), and dark again
luma() {   # average brightness of a patch in the middle of the screen (where the lone window sits)
    grim -t ppm -g "860,500 200x80" - 2>/dev/null | python3 -c "
import sys
d=sys.stdin.buffer.read(); parts=d.split(maxsplit=4); w,h=int(parts[1]),int(parts[2]); px=parts[4]
v=[0.3*px[i]+0.59*px[i+1]+0.11*px[i+2] for i in range(0, w*h*3, 3*37)]
print(int(sum(v)/len(v)))"; }
settings '{"darkMode": true}'
waitfor "d['terminalFoot'] == 'written'" 5; sleep 0.8
foot -a shani-term-test sh -c 'sleep 60' >/dev/null 2>&1 &
waitfor "d['windows'] >= 1" 6; sleep 1.5
dark=$(luma)
settings '{"darkMode": false}'
i=0; until grep -q "initial-color-theme=light" "$FOOT" 2>/dev/null || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done; sleep 1.5
light=$(luma); shot terminal-foot-light 0.2
# a window opened now has the light titlebar too (read when foot starts)
pkill -f shani-term-test; sleep 0.5
foot -a shani-term-test sh -c 'sleep 60' >/dev/null 2>&1 &
sleep 2; shot terminal-foot-new-light 0.2
# the titlebar: just under the focus ring, down the middle of the screen
bar=$(grim -t ppm -g "960,40 1x300" - 2>/dev/null | python3 -c "
import sys
d=sys.stdin.buffer.read(); p=d.split(maxsplit=4); px=p[4]
rows=[tuple(px[i:i+3]) for i in range(0, 300*3, 3)]
ring=next((y for y,(r,g,b) in enumerate(rows) if r > 200 and 90 < g < 170 and b < 120), None)
print(int(sum(0.3*r+0.59*g+0.11*b for r,g,b in rows[ring+4:ring+16]) / 12) if ring is not None else '')")
[ "${bar:-0}" -gt 150 ] && result terminal-new-window-light-titlebar PASS "titlebar luma $bar" || result terminal-new-window-light-titlebar FAIL "titlebar luma $bar"
settings '{"darkMode": true}'
i=0; until grep -q "initial-color-theme=dark" "$FOOT" 2>/dev/null || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done; sleep 1.5
back=$(luma); shot terminal-foot-dark 0.2
[ "${dark:-999}" -lt 90 ] && [ "${light:-0}" -gt 170 ] && [ "${back:-999}" -lt 90 ] \
    && result terminal-foot-follows-light-and-dark PASS "dark $dark, light $light, dark again $back" \
    || result terminal-foot-follows-light-and-dark FAIL "luma dark $dark, light $light, back $back"
pkill -f shani-term-test

# a person's own foot.ini is theirs: the shell leaves it (negative control for the writer)
printf '[main]\nfont=monospace:size=13\n' > "$FOOT"
settings '{"darkMode": false}'
waitfor "d['terminalFoot'] == 'theirs'" 6 && [ "$(head -n1 "$FOOT")" = "[main]" ] \
    && result terminal-own-foot-ini-left-alone PASS || result terminal-own-foot-ini-left-alone FAIL "$(q "['terminalFoot']"): $(head -2 "$FOOT")"
rm -f "$FOOT"; settings '{}'

# Chronoa from the terminal: what foot pipes in (Ctrl+Shift+A) is asked about, the panel open
printf 'ls: cannot access \033[1mmissing\033[0m: No such file or directory\n' | SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani chronoa explain - >/dev/null 2>&1
waitfor "'cannot access missing' in d['chronoaAsked'] and d['chronoaOpen']" 5 \
    && result terminal-output-to-chronoa PASS || result terminal-output-to-chronoa FAIL "$(q "['chronoaAsked'][:120]")"
# leave Chronoa closed: its panel holds the keyboard, and its answer arriving
# later opens it again - wait for the turn to end, then close it
waitfor "d['chronoa'] not in ('thinking', 'waiting')" 20
ipc closeChronoa; waitfor "not d['chronoaOpen']" 4
ipc closeAll
# the picker, to look at
ipc settingsCategory apps; sleep 2; shot settings-terminal 0.3
ipc closeAll
