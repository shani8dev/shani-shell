# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=desktop-extras)
# ---- after Omarchy 4.5: a captive portal, floating workspaces, the AI console ----
command -v winid >/dev/null 2>&1 || winid() { niri msg -j windows | python3 -c "import json,sys; print(next((w['id'] for w in json.load(sys.stdin) if w['app_id'] == '$1'), ''))"; }
floating() { niri msg -j windows | python3 -c "import json,sys; print(next((w['is_floating'] for w in json.load(sys.stdin) if w['app_id'] == '$1'), None))"; }
openwin() { foot --app-id="$1" sh -c 'sleep 60' >/dev/null 2>&1 & i=0; until [ -n "$(winid "$1")" ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done; }
closewin() { w=$(winid "$1"); [ -n "$w" ] && niri msg action close-window --id "$w" >/dev/null 2>&1; }

# a network that wants a sign-in (no real portal here: the dev NetworkManager's
# check is stood in for by netPortal); the bar warns, a click opens its page
ipc netPortal true
waitfor "d['netPortal'] and d['netLabel'] == 'Sign-in needed'" 3 \
    && result portal-noticed PASS || result portal-noticed FAIL "$(q "['netPortal'], d['netLabel']")"
n0=$(q "['portalOpens']"); ipc netOpenPortal; sleep 0.3
[ "$(q "['portalOpens']")" -gt "$n0" ] && result portal-sign-in-opens PASS || result portal-sign-in-opens FAIL
ipc netPortal false
waitfor "not d['netPortal']" 3 && result portal-gone-when-signed-in PASS || result portal-gone-when-signed-in FAIL

# floating workspaces: the focused one switched floats what is there and what opens there
openwin float-a
ipc workspaceLayout
waitfor "d['floatingWorkspace']" 3; sleep 0.6
fa=$(floating float-a)
openwin float-b; sleep 0.8
fb=$(floating float-b)
[ "$fa" = True ] && [ "$fb" = True ] \
    && result floating-workspace-floats-its-windows PASS || result floating-workspace-floats-its-windows FAIL "a=$fa b=$fb ws=$(q "['floatingWorkspace']")"
shot floating-workspace 0.3
ipc workspaceLayout
waitfor "not d['floatingWorkspace']" 3; sleep 0.6
[ "$(floating float-a)" = False ] && [ "$(floating float-b)" = False ] \
    && result floating-workspace-back-to-scrolling PASS || result floating-workspace-back-to-scrolling FAIL "a=$(floating float-a) b=$(floating float-b)"
closewin float-a; closewin float-b

# the AI console: dropped down on the key, the same session back on the next
ipc scratchpad ai
i=0; until [ -n "$(winid shani-pad-ai)" ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
first=$(winid shani-pad-ai)
[ -n "$first" ] && [ "$(q "['scratchpad']")" = started ] \
    && result ai-console-drops-down PASS "agent: '$(q "['aiAgent']")'" || result ai-console-drops-down FAIL "$(q "['scratchpad']")"
sleep 0.5; ipc scratchpad ai; sleep 0.5
ipc scratchpad ai; sleep 0.5
[ "$(winid shani-pad-ai)" = "$first" ] && [ "$(q "['scratchpad']")" = shown ] \
    && result ai-console-keeps-its-session PASS || result ai-console-keeps-its-session FAIL "$(q "['scratchpad']") $(winid shani-pad-ai) vs $first"
closewin shani-pad-ai

# the bar's second clock, and the IME key's bind (niri runs no binds for wtype:
# the binds are checked by niri itself, as remote.sh does)
settings '{"barWorldClock": true, "worldClocks": ["Asia/Tokyo"]}'
waitfor "True" 1
for b in 'Mod+Shift+Grave' 'Mod+Shift+Space' 'Mod+I '; do grep -q "^ *$b" /work/dev/niri/session.kdl || missing="$missing $b"; done
niri validate -c /work/dev/niri/session.kdl >/dev/null 2>&1 && [ -z "$missing" ] \
    && result desktop-extras-binds PASS || result desktop-extras-binds FAIL "missing:$missing"
settings '{}'
