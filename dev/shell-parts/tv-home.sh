# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=tv-home)
# ---- the TV home (Modules/TvHome, docs/FORM-FACTORS.md step 2) ----
# The dev screen chosen as a TV in Settings > Displays gets the 10-foot home;
# driven with real key presses through niri (wtype), as a remote sends its
# arrows and OK; Home and Back through the remote* IPC the niri binds call
# (niri runs no binds for a virtual keyboard - remote.sh).
command -v winid >/dev/null 2>&1 || winid() { niri msg -j windows | python3 -c "import json,sys; print(next((w['id'] for w in json.load(sys.stdin) if w['app_id'] == '$1'), ''))"; }
if [ -z "${SHANI_FORM_FACTOR:-}" ]; then
    settings '{"formFactors": {"winit": "tv"}}'
    ipc tvHome true
    waitfor "d['tvHome'] and d['tvSelected'] != ''" 5 \
        && result tv-home-shown-on-a-tv PASS "$(q "['tvSelected']")" || result tv-home-shown-on-a-tv FAIL "$(q "['formFactor'], d['tvHome'], d['tvSelected']")"
    shot tv-home 0.4

    # the arrows move along a shelf and between shelves
    s0=$(q "['tvSelected']")
    wtype -k Down; sleep 0.3; s1=$(q "['tvSelected']")
    wtype -k Right; sleep 0.3; s2=$(q "['tvSelected']")
    [ "$s0" != "$s1" ] && [ "$s1" != "$s2" ] \
        && result tv-home-arrows-move PASS "$s0 -> $s1 -> $s2" || result tv-home-arrows-move FAIL "$s0 -> $s1 -> $s2"

    # down to the Settings shelf; OK opens that page and the home steps aside
    i=0; until q "['tvSelected']" | grep -q '^settings:' || [ $i -ge 8 ]; do wtype -k Down; sleep 0.3; i=$((i+1)); done
    wtype -k Return
    waitfor "d['settingsOpen'] and not d['tvHome']" 4 \
        && result tv-home-ok-opens-settings PASS || result tv-home-ok-opens-settings FAIL "$(q "['tvSelected'], d['settingsOpen'], d['tvHome']")"
    ipc closeAll; ipc remoteHome
    waitfor "d['tvHome'] and not d['settingsOpen'] and not d['launcher']" 3 \
        && result tv-home-home-button-brings-it-back PASS || result tv-home-home-button-brings-it-back FAIL "$(q "['tvHome'], d['settingsOpen'], d['launcher']")"

    # an open app is on the first shelf; OK goes to it, Home and Back come and go
    foot --app-id=tv-home-app sh -c 'sleep 60' >/dev/null 2>&1 &
    i=0; until [ -n "$(winid tv-home-app)" ] || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
    ipc remoteHome
    waitfor "d['tvHome'] and d['tvSelected'].startswith('window:')" 4
    wtype -k Return
    waitfor "not d['tvHome']" 3 && [ "$(niri msg -j focused-window | python3 -c 'import json,sys; print(json.load(sys.stdin)["app_id"])')" = tv-home-app ] \
        && result tv-home-open-now-goes-to-the-app PASS || result tv-home-open-now-goes-to-the-app FAIL "$(q "['tvHome'], d['tvSelected']")"
    ipc remoteHome; waitfor "d['tvHome']" 3
    ipc remoteBack
    waitfor "not d['tvHome']" 3 \
        && result tv-home-back-returns-to-the-app PASS || result tv-home-back-returns-to-the-app FAIL "$(q "['tvHome']")"
    w=$(winid tv-home-app); [ -n "$w" ] && niri msg action close-window --id "$w" >/dev/null 2>&1

    # a computer screen never shows it
    settings '{}'
    ipc tvHome true
    waitfor "d['formFactor'] == 'computer'" 5
    [ "$(q "['tvHome']")" = False ] \
        && result tv-home-not-on-a-computer PASS || result tv-home-not-on-a-computer FAIL "$(q "['formFactor'], d['tvHome']")"
fi
