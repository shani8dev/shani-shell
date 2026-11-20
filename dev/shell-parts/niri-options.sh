# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=niri-options)
# ---- what niri can do, from Settings: each option written into shani-input.kdl,
#      niri reading it (niri validate, and the shell's guard not putting the old
#      file back), the per-screen ones and the window menu's actions known to this
#      niri, two of those actions taking effect, and a touchscreen calibration
#      solved from four touches (through the IPC: the session has no touchscreen) ----
F="$HOME/.config/niri/shani-input.kdl"
settings '{"kbLayouts":["us","in+mar"],"kbPerWindow":true,"tpDrag":false,"tpDwtp":true,"mouseScrollButton":true,"scrollButtonLock":true,
 "tballScrollButton":true,"tpointSpeed":0.4,"tpointAccel":"adaptive","cursorHideTyping":true,"cursorHideIdle":5,"warpMouseToFocus":true,
 "wsBackAndForth":true,"middlePaste":false,"powerKeyByLogind":true,"winTabbed":true,"winEmptyAbove":true,"winStrutTop":24,
 "overviewZoom":0.35,"tabletOutput":"@focused","touchMatrix":[1.05,0,-0.02,0,0.98,0.01],"startHintsDone":true}'
k=0; until grep -q "track-layout" "$F" 2>/dev/null || [ $k -ge 20 ]; do sleep 0.25; k=$((k+1)); done
missing=""
for want in 'track-layout "window"' 'drag false' '        dwtp' 'scroll-method "on-button-down"' 'scroll-button-lock' 'trackpoint {' 'trackball {' \
            'accel-speed 0.40' 'hide-when-typing' 'hide-after-inactive-ms 5000' 'warp-mouse-to-focus' 'workspace-auto-back-and-forth' \
            'disable-power-key-handling' 'disable-primary' 'default-column-display "tabbed"' 'tab-indicator {' 'insert-hint {' \
            'preset-window-heights {' 'empty-workspace-above-first' 'struts {' 'zoom 0.35' 'map-to-focused-output' \
            'calibration-matrix 1.050000 0.000000 -0.020000 0.000000 0.980000 0.010000' 'switch-events {' 'urgent-color'; do
    grep -qF -- "$want" "$F" || missing="$missing | $want"
done
[ -z "$missing" ] && result niri-options-written PASS || result niri-options-written FAIL "not in shani-input.kdl:$missing"
niri validate -c /work/dev/niri/session.kdl >/tmp/niri-validate.txt 2>&1 && result niri-options-valid PASS \
    || result niri-options-valid FAIL "$(grep -v '^\s*$' /tmp/niri-validate.txt | tail -4 | tr '\n' ' ')"
sleep 2      # the shell's guard puts the old file back when niri cannot read the new one
grep -q "track-layout" "$F" && result niri-options-kept PASS || result niri-options-kept FAIL "the guard put the old file back"

# per screen, each alone in a copy of the session's config: which this niri knows
o=$(niri msg -j outputs | python3 -c "import json,sys; print(next(iter(json.load(sys.stdin))))")
for opt in 'mode custom=true "1600x900@60"' 'max-bpc 10' 'drm-lease' 'focus-at-startup'; do
    { cat /work/dev/niri/session.kdl; printf 'output "%s" {\n    %s\n}\n' "$o" "$opt"; } > /tmp/niri-one.kdl
    name=$(echo "$opt" | cut -d' ' -f1)
    niri validate -c /tmp/niri-one.kdl >/tmp/niri-one.txt 2>&1 && result "niri-knows-output-$name" PASS \
        || result "niri-knows-output-$name" SKIP "not in this niri yet (Arch has 26.04)"
done

# the actions the window menu, the bar and the binds now use
acts=$(niri msg action --help 2>&1)
for a in toggle-windowed-fullscreen maximize-window-to-edges expand-column-to-available-width toggle-column-tabbed-display \
         swap-window-left swap-window-right move-workspace-up move-workspace-down move-workspace-to-monitor-next stop-cast \
         switch-focus-between-floating-and-tiling switch-preset-window-height reset-window-height; do
    printf '%s\n' "$acts" | grep -qw -- "$a" && result "niri-knows-$a" PASS || result "niri-knows-$a" FAIL "not in niri msg action --help"
done
niri msg -j casts >/dev/null 2>&1 && result niri-lists-casts PASS || result niri-lists-casts FAIL "$(niri msg -j casts 2>&1 | tail -1)"

# swap: two windows side by side; the right one swapped left moves a column left
ipc closeAll
foot -a swap-a -T "Swap A" sleep 120 >/dev/null 2>&1 &
sleep 0.6; foot -a swap-b -T "Swap B" sleep 120 >/dev/null 2>&1 &
col() { niri msg -j windows | python3 -c "import json,sys; w=[x for x in json.load(sys.stdin) if x.get('app_id')=='$1']; print(w[0]['layout']['pos_in_scrolling_layout'][0] if w and w[0].get('layout') and w[0]['layout'].get('pos_in_scrolling_layout') else '')"; }
k=0; until [ -n "$(col swap-b)" ] && [ -n "$(col swap-a)" ] || [ $k -ge 20 ]; do sleep 0.25; k=$((k+1)); done
b0=$(col swap-b); niri msg action focus-window --id "$(niri msg -j windows | python3 -c "import json,sys; print([x['id'] for x in json.load(sys.stdin) if x.get('app_id')=='swap-b'][0])")"
niri msg action swap-window-left; sleep 0.5; b1=$(col swap-b)
[ -n "$b0" ] && [ -n "$b1" ] && [ "$b1" -lt "$b0" ] && result niri-swap-window PASS "column $b0 > $b1" || result niri-swap-window FAIL "column '$b0' > '$b1'"
# a workspace moved down: the window's workspace goes from index i to i+1
ws() { niri msg -j workspaces | python3 -c "import json,sys; print([w['idx'] for w in json.load(sys.stdin) if w['is_focused']][0])"; }
# make sure a second workspace exists: moving down on a lone one does nothing
niri msg action focus-workspace 2 >/dev/null 2>&1; sleep 0.3
niri msg action focus-workspace 1 >/dev/null 2>&1; sleep 0.3
w0=$(ws); niri msg action move-workspace-down; sleep 0.5; w1=$(ws)
# niri renumbers after the move (it may skip an empty slot): the workspace
# moved down if its index increased, not necessarily by exactly one
[ "$w1" -gt "$w0" ] && result niri-move-workspace PASS "$w0 > $w1" || result niri-move-workspace FAIL "$w0 > $w1"
niri msg action move-workspace-up
pkill -f "foot -a swap-" 2>/dev/null

# calibration: the device lands each touch by M's inverse; four touches give M back
M="1.05 0 -0.02 0 0.98 0.01"
qs -p /work/shani ipc call shani calibrateStart touch >/dev/null
waitfor "d['calibrating'] == 'touch' and len(d['touchMatrix']) == 0" 4 && result calibrate-starts-raw PASS || result calibrate-starts-raw FAIL "$(q "['calibrating'], d['touchMatrix']")"
for t in "0.1 0.1" "0.9 0.1" "0.9 0.9" "0.1 0.9"; do
    set -- $t; sx=$(python3 -c "print(($1 + 0.02) / 1.05)"); sy=$(python3 -c "print(($2 - 0.01) / 0.98)")
    qs -p /work/shani ipc call shani calibrateTouch "$sx" "$sy" >/dev/null; sleep 0.2
done
waitfor "d['calibrateResult'] == 'ok' and all(abs(a - b) < 1e-4 for a, b in zip(d['touchMatrix'], [$(echo $M | tr ' ' ',')]))" 4 \
    && result calibrate-solves PASS "$(q "['touchMatrix']")" || result calibrate-solves FAIL "$(q "['calibrateResult'], d['touchMatrix']")"
# a touch nowhere near its target: given up, the old calibration back
qs -p /work/shani ipc call shani calibrateStart touch >/dev/null; sleep 0.3
qs -p /work/shani ipc call shani calibrateTouch 0.9 0.9 >/dev/null
waitfor "d['calibrateResult'] == 'failed' and abs(d['touchMatrix'][0] - 1.05) < 1e-4" 4 \
    && result calibrate-miss-keeps-old PASS || result calibrate-miss-keeps-old FAIL "$(q "['calibrateResult'], d['touchMatrix']")"
settings '{"startHintsDone":true}'
ipc closeAll
