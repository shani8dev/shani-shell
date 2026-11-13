# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=hooks-sticky)
# ---- two features that had no check (audit 2026-11-13): hooks, sticky Ctrl/Alt ----

# hooks (Settings > Advanced): a command of the person's own when dark style or the
# wallpaper changes - $1 is the new value
rm -f /tmp/hook-dark /tmp/hook-wall
settings '{"hooks": {"enabled": true, "darkModeChange": "echo $1 > /tmp/hook-dark", "wallpaperChange": "echo \"$1|$3\" > /tmp/hook-wall"}}'
ipc setting darkMode false
for i in $(seq 20); do [ -s /tmp/hook-dark ] && break; sleep 0.25; done
[ "$(cat /tmp/hook-dark 2>/dev/null)" = false ] && result hooks-dark-style-runs PASS || result hooks-dark-style-runs FAIL "'$(cat /tmp/hook-dark 2>&1)'"
sleep 1; rm -f /tmp/hook-wall      # the style switch changed the wallpaper shown, and said so
ipc setting wallpaperLight /usr/share/backgrounds/shani/shani-night.jpg   # the light style's: the one shown now
for i in $(seq 20); do [ -s /tmp/hook-wall ] && break; sleep 0.25; done
grep -q "shani-night.jpg|light" /tmp/hook-wall 2>/dev/null && result hooks-wallpaper-runs PASS "$(cat /tmp/hook-wall)" || result hooks-wallpaper-runs FAIL "'$(cat /tmp/hook-wall 2>&1)'"
# off: nothing runs
rm -f /tmp/hook-dark
# (dark style kept as it is in the same write: a write that changed both at once
# would leave which one the hook saw first to chance)
settings '{"darkMode": false, "hooks": {"enabled": false, "darkModeChange": "echo $1 > /tmp/hook-dark"}}'
sleep 1; rm -f /tmp/hook-dark
ipc setting darkMode true; sleep 1.5
[ ! -e /tmp/hook-dark ] && result hooks-off-run-nothing PASS || result hooks-off-run-nothing FAIL
settings '{}'

# sticky Ctrl on the screen keyboard: one tap - the next key only; two - held
rm -f /tmp/osk-keys
foot -a osk-sticky sh -c 'stty raw -echo; head -c 3 | od -An -tx1 > /tmp/osk-keys' >/dev/null 2>&1 &
i=0; until niri msg -j focused-window 2>/dev/null | grep -q osk-sticky || [ $i -ge 40 ]; do sleep 0.25; i=$((i+1)); done; sleep 0.5
ipc oskTapMod ctrl
[ "$(q "['oskCtrl']")" = 1 ] && result osk-sticky-ctrl-armed PASS || result osk-sticky-ctrl-armed FAIL "$(q "['oskCtrl']")"
ipc oskPress a; sleep 0.4                       # Ctrl+A: 0x01, and Ctrl lets go
[ "$(q "['oskCtrl']")" = 0 ] && result osk-sticky-ctrl-one-key PASS || result osk-sticky-ctrl-one-key FAIL "$(q "['oskCtrl']")"
ipc oskTapMod ctrl; ipc oskTapMod ctrl          # held
ipc oskPress b; sleep 0.3; ipc oskPress c; sleep 0.6   # Ctrl+B, Ctrl+C: 0x02 0x03
[ "$(q "['oskCtrl']")" = 2 ] && result osk-sticky-ctrl-held PASS || result osk-sticky-ctrl-held FAIL "$(q "['oskCtrl']")"
for i in $(seq 20); do [ -s /tmp/osk-keys ] && break; sleep 0.25; done
[ "$(tr -d ' \n' < /tmp/osk-keys 2>/dev/null)" = 010203 ] && result osk-sticky-ctrl-reaches-the-app PASS "$(cat /tmp/osk-keys)" \
    || result osk-sticky-ctrl-reaches-the-app FAIL "the app got '$(cat /tmp/osk-keys 2>&1)'"
ipc oskTapMod ctrl                              # off
pkill -f osk-sticky
