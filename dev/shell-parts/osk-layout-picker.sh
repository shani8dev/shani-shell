# Exercise the visible OSK controls with the same navigation used by a pad.
settings '{"oskLanguages":["en","mr","ru","in+tam"]}'
ipc launcher ""
waitfor "d['osk']" 1 || ipc osk
waitfor "d['osk']" 5

pad_until() {
    direction=$1
    label=$2
    for i in $(seq 1 18); do
        [ "$(q "['oskCursor']")" = "$label" ] && return 0
        ipc oskPad "$direction"
        sleep 0.12
    done
    return 1
}

pad_until down '☺' && pad_until up '?123' && pad_until right 'Keyboard layouts' && ipc oskPad press
pad_until down 'मराठी' && ipc oskPad press
waitfor "d['oskLang'] == 'mr' and d['oskPage'] == 'letters'" 5 \
    && result osk-pad-selects-marathi-from-layout-picker PASS \
    || result osk-pad-selects-marathi-from-layout-picker FAIL "cursor $(q "['oskCursor']") layout $(q "['oskLang']")"

# Reopen from a different script and move through more than one layout row.
waitfor "d['oskCursor'] == 'Keyboard layouts'" 3 && ipc oskPad press
shot osk-layout-picker 0.3
pad_until up 'English' && ipc oskPad press
waitfor "d['oskLang'] == 'en'" 4 && result osk-pad-switches-back-to-english PASS \
    || result osk-pad-switches-back-to-english FAIL "cursor $(q "['oskCursor']")"

# Emoji must remain reachable with a correction on screen.
ipc osk
ipc osk
waitfor "d['osk']" 5
for k in t e h; do ipc oskPress "$k"; sleep 0.25; done
waitfor "d['oskCorrection'] == 'the'" 4
pad_until down '☺' && ipc oskPad press
waitfor "d['oskPage'] == 'emoji' and d['emojiGroups'] >= 8" 5 \
    && result osk-emoji-reachable-with-predictions PASS \
    || result osk-emoji-reachable-with-predictions FAIL "cursor $(q "['oskCursor']")"
shot osk-emoji-with-picker 0.3

ipc oskPage letters
ipc osk
ipc osk
waitfor "d['osk']" 5
pad_until down '☺' && pad_until up '?123' && pad_until right 'Keyboard layouts' && ipc oskPad press
pad_until down 'Add a layout…' && ipc oskPad press
waitfor "d['settingsOpen'] and d['settingsCat'] == 'input' and not d['osk']" 5 \
    && result osk-picker-opens-layout-settings PASS \
    || result osk-picker-opens-layout-settings FAIL "cursor $(q "['oskCursor']")"
shot osk-layout-settings 0.6
ipc closeAll
settings '{}'
