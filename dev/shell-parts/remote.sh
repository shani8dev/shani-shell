# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=remote)
# ---- a TV remote: the whole desktop with arrows, OK, Back, Home, Menu, Keyboard ----
# Real key presses through niri (wtype), as a Bluetooth/USB remote sends them:
# Home opens the launcher, Up past its top row reaches the search bar, OK there
# brings the screen keyboard in remote mode (it takes the keys: arrows move, OK
# types into its own line, Done hands the text to the field), Back goes one
# level back - and with nothing of the shell open it is the app's back (Alt+Left).
#
# niri runs no key binding for a virtual keyboard (wtype): measured, even
# Mod+Space does nothing that way. So the remote's own keys (Home, Back, Menu,
# Keyboard) are checked in two halves: the binds - both niri configs validate
# and bind each key to its call - and what each call does, through the same
# IPC the bind runs. Arrows and OK go to the shell's surfaces, not to niri's
# binds, so those are real key presses.
binds_ok=1
for cfg in /work/dev/niri/session.kdl /desk/etc/niri/config.kdl; do      # the dev session and the packaged one
    [ -f "$cfg" ] || continue
    niri validate -c "$cfg" >/dev/null 2>&1 || binds_ok=0
    for kv in XF86HomePage:remoteHome XF86Back:remoteBack XF86MenuKB:remoteMenu XF86Keyboard:remoteKeyboard; do
        grep -qE "^ *${kv%%:*} +\{ spawn \"qs\".* \"${kv##*:}\"; \}" "$cfg" || binds_ok=0
    done
done
[ $binds_ok = 1 ] && result remote-keys-bound-in-niri PASS || result remote-keys-bound-in-niri FAIL
remote() { qs -p /work/shani ipc call shani "remote$1" >/dev/null 2>&1; }
# the suite's helpers, when this part runs alone (they are defined further down the main script)
command -v winid >/dev/null 2>&1 || winid() { niri msg -j windows | python3 -c "import json,sys; print(next((w['id'] for w in json.load(sys.stdin) if w['app_id'] == '$1'), ''))"; }
command -v typein >/dev/null 2>&1 || typein() { rm -f "$2"; foot --app-id="$1" sh -c "stty raw -echo; head -c $3 > $2" >/dev/null 2>&1 &
    i=0; until [ -n "$(winid "$1")" ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
    niri msg action focus-window --id "$(winid "$1")"; sleep 0.5; }
ipc closeAll; sleep 0.5
remote Home
waitfor "d['launcher']" 4 && result remote-home-opens-the-launcher PASS || result remote-home-opens-the-launcher FAIL
sleep 0.5
wtype -k Up; sleep 0.3; wtype -k Return
waitfor "d['oskRemote'] and d['osk']" 4 && result remote-ok-on-the-search-bar-brings-the-keyboard PASS \
    || result remote-ok-on-the-search-bar-brings-the-keyboard FAIL "remote $(q "['oskRemote']"), shown $(q "['osk']")"
wtype -k Down; sleep 0.3; c1=$(q "['oskCursor']")              # the cursor appears on the first key
wtype -k Right; sleep 0.3; c2=$(q "['oskCursor']")
wtype -k Return; sleep 0.4                                         # OK types it - into the keyboard's own line
waitfor "d['oskDraft'] == '$c2'" 3 && [ -n "$c2" ] && [ "$c1" != "$c2" ] \
    && result remote-arrows-and-ok-type PASS "$c1 -> $c2" || result remote-arrows-and-ok-type FAIL "'$c1' -> '$c2', draft '$(q "['oskDraft']")'"
[ -n "$(q "['oskDraft']")" ] && [ "$(q "['launcherText']")" = "" ] && result remote-typing-waits-for-done PASS || result remote-typing-waits-for-done FAIL "the query is already '$(q "['launcherText']")'"
shot 42-remote-keyboard 0.3
ipc oskPad enter                                                   # Done (Start on a pad)
waitfor "not d['oskRemote'] and d['launcherText'] == '$c2'" 4 && result remote-done-hands-the-text-over PASS "$(q "['launcherText']")" \
    || result remote-done-hands-the-text-over FAIL "query '$(q "['launcherText']")', remote $(q "['oskRemote']")"
remote Back
waitfor "not d['launcher']" 3 && result remote-back-closes-the-launcher PASS || result remote-back-closes-the-launcher FAIL
# the Keyboard key, and Back cancels: nothing typed anywhere
remote Keyboard
waitfor "d['oskRemote']" 3 && wtype -k Down && sleep 0.3 && wtype -k Return && sleep 0.3
remote Back
waitfor "not d['oskRemote'] and not d['osk']" 3 && [ -n "$c2" ] && [ "$(q "['oskCommitted']")" = "$c2" ] \
    && result remote-back-cancels-typing PASS || result remote-back-cancels-typing FAIL "remote $(q "['oskRemote']"), committed '$(q "['oskCommitted']")'"
# nothing of the shell open: Back is the app's back (Alt+Left: ESC [1;3D in a terminal)
typein remote-back-app /tmp/remote-back 6
remote Back
for i in $(seq 12); do [ -s /tmp/remote-back ] && break; sleep 0.25; done
od -An -c /tmp/remote-back 2>/dev/null | tr -d ' \n' | grep -q '033\[1;3D' && result remote-back-in-an-app-is-its-back PASS \
    || result remote-back-in-an-app-is-its-back FAIL "the app got '$(od -An -c /tmp/remote-back 2>/dev/null | tr -d '\n')'"
# Menu: the focused window's menu, as a controller's X
remote Menu
waitfor "d['windowMenu']" 3 && result remote-menu-opens-the-window-menu PASS || result remote-menu-opens-the-window-menu FAIL
remote Back; waitfor "not d['windowMenu']" 3
pkill -f "head -c 6 > /tmp/remote-back" 2>/dev/null
ipc closeAll
