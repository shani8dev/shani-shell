# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=phone)
# ---- the phone (docs/FORM-FACTORS.md step 7) ----
# The dev screen chosen as a phone: one column. The bar keeps the launcher, the
# status cluster and the clock, and drops the workspaces, the world clock and
# the date - they are what overflows a 412-point screen.
if [ -z "${SHANI_FORM_FACTOR:-}" ] || [ "${SHANI_FORM_FACTOR:-}" = phone ]; then
    settings '{"formFactors": {"winit": "phone"}}'
    waitfor "d['formFactor'] == 'phone' and abs(d['uiScale'] - 1.15) < 0.01" 5 \
        && result phone-scale PASS || result phone-scale FAIL "$(q "['formFactor'], d['uiScale']")"
    python3 - <<'PY' && result phone-output-size PASS || result phone-output-size FAIL
import json, os, subprocess
outputs = json.loads(subprocess.check_output(["niri", "msg", "-j", "outputs"]))
logical = next(iter(outputs.values()))["logical"]
assert logical["width"] == int(os.environ.get("SHANI_WIDTH", "1920")), logical
assert logical["height"] == int(os.environ.get("SHANI_SCREEN", "1080")), logical
PY
    waitfor "d['barNarrow']" 5 && result phone-bar-is-one-column PASS \
        || result phone-bar-is-one-column FAIL "$(q "['barNarrow']")"
    # at a phone's width the two clusters must still leave a gap between them
    waitfor "not d['barOverlap']" 5 && result phone-bar-fits PASS \
        || result phone-bar-fits FAIL "the clusters meet at this width"
    shot phone-bar 0.4
    # held another way with auto-rotate off: a rotate button is offered (the
    # navigation bar's), not a turn; it goes again when nobody takes it
    settings '{"formFactors": {"winit": "phone"}, "autoRotate": false}'
    sleep 1; echo left-up > /tmp/accel
    waitfor "d['rotateSuggest'] == 'left-up'" 6 && result phone-rotate-offered PASS \
        || result phone-rotate-offered FAIL "$(q "['rotateSuggest']")"
    shot phone-rotate-offer 0.3
    waitfor "d['rotateSuggest'] == ''" 10 && result phone-rotate-offer-goes PASS \
        || result phone-rotate-offer-goes FAIL "$(q "['rotateSuggest']")"
    # one app at a time: niri opens every window maximised on a phone, the bar kept
    # above it as a phone's status bar. The rule is read back from the file the shell
    # writes, checked with niri's own parser, and then with a real window - as wide
    # as the screen, and under the bar, not over it.
    kdl="${XDG_CONFIG_HOME:-$HOME/.config}/niri/shani-windows.kdl"
    i=0; until grep -q "open-maximized" "$kdl" 2>/dev/null || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
    grep -q "open-maximized" "$kdl" 2>/dev/null && result phone-windows-open-maximised PASS \
        || result phone-windows-open-maximised FAIL "niri was not told"
    niri validate -c "$kdl" >/dev/null 2>&1 && result phone-niri-accepts-the-rule PASS \
        || result phone-niri-accepts-the-rule FAIL "niri cannot read what was written"
    foot --app-id=fs-test sh -c 'sleep 25' >/dev/null 2>&1 &
    i=0; until [ -n "$(niri msg -j windows | python3 -c 'import json,sys
print(next((w["id"] for w in json.load(sys.stdin) if w["app_id"] == "fs-test"), ""))' 2>/dev/null)" ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
    python3 - <<'PY' && result phone-a-window-fills-under-the-bar PASS || result phone-a-window-fills-under-the-bar FAIL
import json, subprocess
def query(what):
    return json.loads(subprocess.check_output(["niri", "msg", "-j", what]))
window = next(w for w in query("windows") if w["app_id"] == "fs-test")
screen = next(iter(query("outputs").values()))["logical"]
width, height = window["layout"]["tile_size"]
# the whole width; the height between the status bar above and the dock and the
# navigation bar below - those stay in view, the window is not over them
assert width >= screen["width"] * 0.95 and screen["height"] * 0.6 <= height < screen["height"] - 60, (window, screen)
PY
    niri msg action close-window --id "$(niri msg -j windows | python3 -c 'import json,sys
print(next((w["id"] for w in json.load(sys.stdin) if w["app_id"] == "fs-test"), ""))' 2>/dev/null)" 2>/dev/null
    # the two surfaces a phone opens most still open at this width
    ipc launcher ""
    waitfor "d['launcher']" 4 && result phone-launcher-opens PASS || result phone-launcher-opens FAIL
    waitfor "d['launcherNarrow']" 4 && result phone-launcher-is-one-column PASS \
        || result phone-launcher-is-one-column FAIL "$(q "['launcherNarrow']")"
    shot phone-launcher 0.4
    ipc closeAll
    # Enter a query too: this is when the preview pane used to steal the width.
    ipc launcher "file"
    waitfor "d['launcher'] and d['launcherNarrow']" 4 \
        && result phone-search-stays-compact PASS || result phone-search-stays-compact FAIL
    ipc closeAll
    ipc toggleControlCenter
    waitfor "d['controlCenter']" 4 && result phone-quick-settings-opens PASS || result phone-quick-settings-opens FAIL
    waitfor "d['sidebarShade']" 4 && result phone-quick-settings-is-a-shade PASS \
        || result phone-quick-settings-is-a-shade FAIL "$(q "['sidebarShade']")"
    shot phone-quick-settings 0.4
    ipc closeAll
    # a notification is a card the width of the screen, not 437 of 412
    notify-send -a shani-test "Hello" "a card the width of the phone"
    sleep 1
    shot phone-notification 0.4
    # the lock screen, at a phone's width: the password has to exist first - the
    # suite sets it before its own lock checks, and a part runs before those
    echo 'root:shani-test' | chpasswd
    ipc lock
    waitfor "d['locked']" 6 && result phone-lock-screen PASS || result phone-lock-screen FAIL
    shot phone-lock 0.4
    unlock
    waitfor "not d['locked']" 8 && result phone-unlocks PASS || result phone-unlocks FAIL "$(q "['locked']")"
    settings '{}'
    if [ -z "${SHANI_FORM_FACTOR:-}" ]; then
        waitfor "d['formFactor'] == 'computer' and not d['barNarrow']" 5 \
            && result phone-wide-screen-keeps-everything PASS || result phone-wide-screen-keeps-everything FAIL "$(q "['formFactor'], d['barNarrow']")"
        i=0; while grep -q 'open-maximized' "$kdl" && [ "$i" -lt 20 ]; do sleep 0.25; i=$((i+1)); done
        ! grep -q 'open-maximized' "$kdl" && result phone-leaves-no-phone-rule PASS \
            || result phone-leaves-no-phone-rule FAIL
    fi
else
    result phone-profile SKIP "requires automatic or phone profile"
fi
