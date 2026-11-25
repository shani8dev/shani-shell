# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=layouts)
# ---- Screen and layout: every desktop layout, kept through the switcher the way
#      a person picks one, and back again. Each one must set what it says
#      (layoutPreset), and coming back must give every setting a layout owns back
#      exactly (layoutSnapshot: Services/Docking.keys) - the round trip, Cancel
#      (Esc) leaving nothing changed, and going back to an earlier layout ----
snap() { qs $QS_ARGS ipc call "$QS_TARGET" layoutSnapshot 2>/dev/null; }
use() {   # try one on, keep it with Return; 0 when it was kept
    ipc_line "layoutUse $1"
    waitfor "d['layoutSwitcher'] and d['layoutTrying'] == '$1'" 6 || return 1
    # trying one rewrites niri's config, and niri's reload takes the keyboard from
    # the switcher for a moment (it takes it back); a person reads the preview first
    sleep 1.5; wtype -k Return
    waitfor "d['layoutPreset'] == '$1' and not d['layoutSwitcher']" 8
}
IDS=$(grep -o '{ id: "[a-z0-9]*"' /work/shani/Services/Layouts.qml | cut -d'"' -f2)

# from the default, so "back to the default" has something to equal
use default; sleep 1
S0=$(snap)
[ -n "$S0" ] && result layouts-snapshot PASS || result layouts-snapshot FAIL "no layoutSnapshot"

# Cancel: try one on, then Esc - nothing may stay changed
ipc_line "layoutUse taskbar"
waitfor "d['layoutTrying'] == 'taskbar'" 6; sleep 1.5
shot layout-trying-taskbar 0.3
wtype -k Escape
waitfor "not d['layoutSwitcher']" 6; sleep 0.6
[ "$(snap)" = "$S0" ] && [ "$(q "['layoutPreset']")" = default ] \
    && result layouts-cancel-changes-nothing PASS || result layouts-cancel-changes-nothing FAIL "$(q "['layoutSwitcher'], d['layoutTrying'], d['layoutPreset']") $(snap | cut -c1-80)"

# every layout, kept, each different from the default (but the default itself)
bad=""; tmp=/tmp/layout-snaps; rm -rf $tmp; mkdir -p $tmp
for id in $IDS; do
    if use "$id"; then
        sleep 0.8; snap > "$tmp/$id"
        [ "$id" = default ] || [ "$(cat "$tmp/$id")" != "$S0" ] || bad="$bad $id(same-as-default)"
        shot "layout-$id" 0.5
    else
        bad="$bad $id(not-kept)"
    fi
done
[ -z "$bad" ] && result layouts-each-one-kept PASS "$(echo $IDS | wc -w) layouts" || result layouts-each-one-kept FAIL "$bad"

# back to earlier ones: each gives back exactly what it set the first time
bad=""
for id in taskbar launcher tv default; do
    use "$id" || { bad="$bad $id(not-kept)"; continue; }
    sleep 0.8
    [ "$(snap)" = "$(cat "$tmp/$id")" ] || bad="$bad $id"
done
[ -z "$bad" ] && result layouts-back-again-exactly PASS || result layouts-back-again-exactly FAIL "$bad"
[ "$(snap)" = "$S0" ] && result layouts-default-round-trip PASS || result layouts-default-round-trip FAIL "$(snap)"
rm -rf $tmp
